output "vm_ipv4_addresses" {
  description = "Static IPv4 address of each VM"
  value       = { for name, spec in var.vms : name => split("/", spec.ip)[0] }
}

# Generate the Ansible inventory from the Terraform state, so both tools
# always agree on which machines exist and where they live.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    vms      = var.vms
    username = var.vm_username
  })
}
