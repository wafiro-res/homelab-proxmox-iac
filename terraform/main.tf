locals {
  # Resolve each VM's flavor into concrete resources.
  vm_specs = {
    for name, vm in var.vms : name => merge(vm, var.flavors[vm.flavor])
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vm_specs

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id
  tags      = ["terraform", "homelab", each.value.group, each.value.flavor]

  clone {
    vm_id = var.template_vm_id
    full  = var.full_clone
  }

  # qemu-guest-agent is baked into the template (see docs/proxmox-setup.md),
  # so the agent channel can be enabled safely: the provider docs warn that
  # enabling it without the agent running in the guest causes long timeouts.
  agent {
    enabled = true
  }

  # Hard stop on destroy keeps lab teardowns fast.
  stop_on_destroy = true

  cpu {
    cores = each.value.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk_gb
  }

  # Optional data disk on another datastore (e.g. HDD for bulk storage).
  dynamic "disk" {
    for_each = each.value.data_disk == null ? [] : [each.value.data_disk]
    content {
      datastore_id = disk.value.datastore_id
      interface    = "scsi1"
      size         = disk.value.size_gb
      file_format  = "raw"
    }
  }

  network_device {
    bridge = var.network_bridge
    # The Proxmox firewall only filters NICs that opt in.
    firewall = each.value.dmz
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.datastore_id
    interface    = "ide0" # same slot as the template's cloud-init drive

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.gateway
      }
    }

    user_account {
      username = var.vm_username
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_file)))]
    }
  }
}

# ---------------------------------------------------------------------------
# DMZ: per-VM Proxmox firewall for exposed machines (dmz = true).
# Defense in depth — this is OUTSIDE the VM, so it holds even if the VM
# itself is compromised (unlike its internal UFW).
# ---------------------------------------------------------------------------

locals {
  dmz_vms        = { for name, vm in local.vm_specs : name => vm if vm.dmz }
  monitoring_ips = [for vm in var.vms : split("/", vm.ip)[0] if vm.group == "monitoring"]
}

# The datacenter-level firewall must be enabled for VM rules to apply.
# Policies stay ACCEPT here: nothing changes for the host or other VMs,
# filtering only happens on the NICs that opted in.
resource "proxmox_virtual_environment_cluster_firewall" "this" {
  enabled = true

  # Explicitly permissive at the datacenter level: filtering only happens on
  # the DMZ VMs' NICs. Without these, the provider defaults input to DROP on
  # the host itself.
  input_policy   = "ACCEPT"
  output_policy  = "ACCEPT"
  forward_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_options" "dmz" {
  for_each = local.dmz_vms

  node_name = var.node_name
  vm_id     = each.value.vm_id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"

  depends_on = [proxmox_virtual_environment_vm.vm]
}

resource "proxmox_virtual_environment_firewall_rules" "dmz" {
  for_each = local.dmz_vms

  node_name = var.node_name
  vm_id     = each.value.vm_id

  # Inbound: web for everyone, SSH only from the management host,
  # node_exporter only from the monitoring host(s).
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80,443"
    comment = "web"
  }
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = var.mgmt_ip
    comment = "SSH from mgmt only"
  }
  dynamic "rule" {
    for_each = local.monitoring_ips
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = "tcp"
      dport   = "9100"
      source  = rule.value
      comment = "node_exporter scrape from monitoring"
    }
  }

  # Outbound: DNS allowed anywhere, then the whole LAN is denied —
  # a compromised DMZ VM cannot pivot to the other machines.
  rule {
    type    = "out"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "53"
    comment = "DNS"
  }
  rule {
    type    = "out"
    action  = "DROP"
    dest    = var.lan_cidr
    comment = "no lateral movement to the LAN"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.dmz]
}
