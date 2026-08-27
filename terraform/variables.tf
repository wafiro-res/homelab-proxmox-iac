variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint, e.g. https://192.168.213.3:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token in the form user@realm!tokenid=uuid"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (self-signed certificate)"
  type        = bool
  default     = true
}

variable "node_name" {
  description = "Proxmox node name (see the left panel of the web UI)"
  type        = string
  default     = "Proxmox"
}

variable "template_vm_id" {
  description = "VM ID of the cloud-init template to clone (built with qemu-guest-agent baked in, see docs/proxmox-setup.md)"
  type        = number
  default     = 9000
}

variable "datastore_id" {
  description = "Datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "IPv4 gateway for the VMs"
  type        = string
  default     = "192.168.213.1"
}

# Linked clones (false) are near-instant and write almost nothing: each VM
# only stores its differences from the template. Trade-off: the template
# cannot be deleted while linked clones exist. Full clones (true) are fully
# independent but copy the whole template disk for every VM.
variable "full_clone" {
  description = "true = full clone (independent, slow), false = linked clone (instant, depends on the template)"
  type        = bool
  default     = false
}

variable "cpu_type" {
  description = "CPU type for the VMs (x86-64-v2-AES is recommended by the provider docs for modern CPUs)"
  type        = string
  default     = "x86-64-v2-AES"
}

variable "vm_username" {
  description = "Admin user created by cloud-init on each VM"
  type        = string
  default     = "ansible"
}

variable "ssh_public_key_file" {
  description = "Path to the SSH public key injected into the VMs"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# OpenStack-style sizing presets: a VM references a flavor by name
# instead of hardcoding its resources.
variable "flavors" {
  description = "VM sizing presets (name => resources)"
  type = map(object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  }))
  default = {
    "m1.small" = {
      cores     = 1
      memory_mb = 2048
      disk_gb   = 20
    }
    "m1.medium" = {
      cores     = 2
      memory_mb = 4096
      disk_gb   = 30
    }
    "m1.large" = {
      cores     = 4
      memory_mb = 8192
      disk_gb   = 40
    }
  }
}

variable "vms" {
  description = "Map of VMs to create (name => spec). The flavor must exist in var.flavors."
  type = map(object({
    vm_id  = number
    group  = string
    flavor = string
    ip     = string # CIDR notation, e.g. 192.168.213.51/24
  }))
  default = {
    proxy-01 = {
      vm_id  = 211
      group  = "proxy"
      flavor = "m1.small"
      ip     = "192.168.213.51/24"
    }
    apps-01 = {
      vm_id  = 212
      group  = "apps"
      flavor = "m1.large"
      ip     = "192.168.213.52/24"
    }
    monitor-01 = {
      vm_id  = 213
      group  = "monitoring"
      flavor = "m1.medium"
      ip     = "192.168.213.53/24"
    }
    web-01 = {
      vm_id  = 214
      group  = "web"
      flavor = "m1.small"
      ip     = "192.168.213.54/24"
    }
  }

  validation {
    condition     = alltrue([for v in var.vms : contains(["proxy", "apps", "monitoring", "web"], v.group)])
    error_message = "Each VM's group must be one of: proxy, apps, monitoring, web."
  }
}
