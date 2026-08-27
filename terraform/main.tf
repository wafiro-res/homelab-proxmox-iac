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

  network_device {
    bridge = var.network_bridge
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
