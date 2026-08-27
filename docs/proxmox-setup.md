# One-time Proxmox setup / Préparation Proxmox (une seule fois)

Two things must exist on the Proxmox host before `terraform apply`:
an **API token** and an **Ubuntu cloud-init template**.

## 1. API token for Terraform

In the Proxmox shell (or web UI → Datacenter → Permissions):

```bash
# Dedicated user for Terraform
pveum user add terraform@pve

# Role with the required privileges
pveum role add TerraformProv -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify SDN.Use VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt"

# Assign the role at the root of the resource tree
pveum aclmod / -user terraform@pve -role TerraformProv

# Create the token (SAVE THE SECRET, it is shown only once)
pveum user token add terraform@pve iac --privsep=0
```

The `proxmox_api_token` variable then takes the form:
`terraform@pve!iac=<the-secret-uuid>`

## 2. Ubuntu 24.04 cloud-init template (VM ID 9000)

```bash
cd /var/lib/vz/template/iso  # or any scratch directory
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

qm create 9000 --name ubuntu-2404-tpl --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 noble-server-cloudimg-amd64.img local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot order=scsi0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1
qm template 9000
```

Adjust `local-lvm` and `vmbr0` if your storage/bridge differ — the same
values go into `terraform.tfvars`.
