#!/usr/bin/env bash
#
# newvm.sh — interactive helper to add/remove/list lab VMs.
#
# It does NOT create VMs itself: it maintains terraform/vms.auto.tfvars.json
# (which Terraform loads automatically and which OVERRIDES the default "vms"
# map in variables.tf), then offers to run terraform + ansible. The VM is
# born through the normal IaC pipeline.
#
# Usage:  ./scripts/newvm.sh add | remove <name> | list
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_DIR/terraform"
VMS_FILE="$TF_DIR/vms.auto.tfvars.json"

FLAVORS=("m1.small" "m1.medium" "m1.large")
GROUPS_ALLOWED=("proxy" "apps" "monitoring" "web" "drive")
SUBNET_PREFIX="192.168.213"

command -v jq >/dev/null || { echo "jq is required: apt install -y jq"; exit 1; }

# Seed the file with the current lab if it does not exist yet.
seed_file() {
  [ -f "$VMS_FILE" ] && return
  cat > "$VMS_FILE" <<'EOF'
{
  "vms": {
    "proxy-01":   { "vm_id": 211, "group": "proxy",      "flavor": "m1.small",  "ip": "192.168.213.51/24" },
    "apps-01":    { "vm_id": 212, "group": "apps",       "flavor": "m1.large",  "ip": "192.168.213.52/24" },
    "monitor-01": { "vm_id": 213, "group": "monitoring", "flavor": "m1.medium", "ip": "192.168.213.53/24" },
    "web-01":     { "vm_id": 214, "group": "web",        "flavor": "m1.small",  "ip": "192.168.213.54/24" }
  }
}
EOF
  echo "Seeded $VMS_FILE with the current 4 VMs."
}

list_vms() {
  seed_file
  echo
  printf "%-14s %-6s %-11s %-10s %s\n" "NAME" "ID" "GROUP" "FLAVOR" "IP"
  jq -r '.vms | to_entries[] | [.key, (.value.vm_id|tostring), .value.group, .value.flavor, .value.ip] | @tsv' "$VMS_FILE" \
    | awk -F'\t' '{ printf "%-14s %-6s %-11s %-10s %s\n", $1, $2, $3, $4, $5 }'
  echo
}

ask() { # ask "question" "default" -> REPLY
  local q="$1" d="$2"
  read -rp "$q [$d]: " REPLY
  REPLY="${REPLY:-$d}"
}

add_vm() {
  seed_file

  # Suggest next free VM id and IP last octet.
  local next_id next_octet
  next_id=$(jq '[.vms[].vm_id] | max + 1' "$VMS_FILE")
  next_octet=$(jq -r --arg p "$SUBNET_PREFIX" \
    '[.vms[].ip | capture("\\.(?<o>[0-9]+)/").o | tonumber] | max + 1' "$VMS_FILE")

  ask "VM name" "vm-$next_id"
  local name="$REPLY"
  jq -e --arg n "$name" '.vms[$n]' "$VMS_FILE" >/dev/null && { echo "ERROR: '$name' already exists."; exit 1; }

  ask "VM id" "$next_id"
  local vm_id="$REPLY"
  jq -e --argjson i "$vm_id" '.vms[] | select(.vm_id == $i)' "$VMS_FILE" >/dev/null && { echo "ERROR: id $vm_id already used."; exit 1; }

  echo "Groups: ${GROUPS_ALLOWED[*]} (drives which Ansible roles apply)"
  ask "Group" "apps"
  local group="$REPLY"
  printf '%s\n' "${GROUPS_ALLOWED[@]}" | grep -qx "$group" || { echo "ERROR: unknown group '$group'."; exit 1; }

  echo "Flavors: ${FLAVORS[*]} (1c/2G/20G · 2c/4G/30G · 4c/8G/40G)"
  ask "Flavor" "m1.small"
  local flavor="$REPLY"
  printf '%s\n' "${FLAVORS[@]}" | grep -qx "$flavor" || { echo "ERROR: unknown flavor '$flavor'."; exit 1; }

  ask "IP last octet ($SUBNET_PREFIX.X)" "$next_octet"
  local ip="$SUBNET_PREFIX.$REPLY/24"
  jq -e --arg ip "$ip" '.vms[] | select(.ip == $ip)' "$VMS_FILE" >/dev/null && { echo "ERROR: $ip already used."; exit 1; }

  read -rp "Data disk? (empty = none, else '<storage>:<sizeGB>' e.g. hdd1:200): " dd
  local dd_json="null"
  if [ -n "$dd" ]; then
    local dd_store="${dd%%:*}" dd_size="${dd##*:}"
    [[ "$dd_size" =~ ^[0-9]+$ ]] || { echo "ERROR: bad data disk format, expected storage:sizeGB"; exit 1; }
    dd_json=$(jq -n --arg s "$dd_store" --argjson g "$dd_size" '{datastore_id: $s, size_gb: $g}')
  fi

  echo
  echo ">> $name  (id $vm_id, $group, $flavor, $ip, data_disk: $dd)"
  read -rp "Add this VM? [y/N]: " ok
  [[ "$ok" =~ ^[yYoO] ]] || { echo "Aborted."; exit 0; }

  local tmp; tmp=$(mktemp)
  jq --arg n "$name" --argjson i "$vm_id" --arg g "$group" --arg f "$flavor" --arg ip "$ip" \
     --argjson dd "$dd_json" \
     '.vms[$n] = {vm_id: $i, group: $g, flavor: $f, ip: $ip} + (if $dd == null then {} else {data_disk: $dd} end)' "$VMS_FILE" > "$tmp" && mv "$tmp" "$VMS_FILE"
  echo "Written to $VMS_FILE."
  offer_apply
}

remove_vm() {
  seed_file
  local name="${1:?usage: newvm.sh remove <name>}"
  jq -e --arg n "$name" '.vms[$n]' "$VMS_FILE" >/dev/null || { echo "ERROR: '$name' not found."; exit 1; }
  read -rp "Remove '$name'? Terraform will DESTROY the VM on apply. [y/N]: " ok
  [[ "$ok" =~ ^[yYoO] ]] || { echo "Aborted."; exit 0; }
  local tmp; tmp=$(mktemp)
  jq --arg n "$name" 'del(.vms[$n])' "$VMS_FILE" > "$tmp" && mv "$tmp" "$VMS_FILE"
  echo "Removed from $VMS_FILE."
  offer_apply
}

offer_apply() {
  read -rp "Run terraform apply now? [y/N]: " ok
  [[ "$ok" =~ ^[yYoO] ]] || { echo "OK — run it later: cd terraform && terraform apply"; return; }
  (cd "$TF_DIR" && terraform apply)
  read -rp "Run ansible-playbook site.yml now? [y/N]: " ok2
  [[ "$ok2" =~ ^[yYoO] ]] || { echo "OK — run it later: cd ansible && ansible-playbook site.yml"; return; }
  (cd "$REPO_DIR/ansible" && ansible-playbook site.yml)
}

case "${1:-}" in
  add)    add_vm ;;
  remove) remove_vm "${2:-}" ;;
  list)   list_vms ;;
  *)      echo "Usage: $0 add | remove <name> | list"; exit 1 ;;
esac
