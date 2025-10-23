#!/bin/bash
set -euo pipefail

# Macula Infrastructure Bootstrap Script
# Creates libvirt network and VMs for Macula PoC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$INFRA_DIR")"

# Configuration
NETWORK_NAME="macula-net"
NETWORK_XML="$INFRA_DIR/libvirt/macula-net.xml"
SSH_KEY_PATH="$HOME/.ssh/macula_rsa"

# Base OS image for VMs (Debian 12 Bookworm - minimal, lightweight)
BASE_OS_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
BASE_OS_IMAGE_PATH="/var/lib/libvirt/images/debian-12-generic-amd64.qcow2"

# VM Specifications
declare -A HUB_VM=(
  [name]="macula-hub-01"
  [ram]=4096
  [vcpus]=2
  [disk]=20
  [ip]="192.168.100.10"
  [mac]="52:54:00:00:00:10"
)

declare -A EDGE_VMS=(
  [edge-01]="192.168.100.11:52:54:00:00:00:11"
  [edge-02]="192.168.100.12:52:54:00:00:00:12"
  [edge-03]="192.168.100.13:52:54:00:00:00:13"
  [edge-04]="192.168.100.14:52:54:00:00:00:14"
)

EDGE_RAM=2048
EDGE_VCPUS=2
EDGE_DISK=15

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check if running on Linux
  if [[ "$(uname)" != "Linux" ]]; then
    log_error "This script only works on Linux with KVM support"
    exit 1
  fi

  # Check for required commands
  local required_cmds=("virsh" "virt-install" "qemu-img" "curl" "ssh-keygen")
  for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      log_error "Required command not found: $cmd"
      log_info "Ubuntu/Debian: sudo apt install libvirt-daemon-system libvirt-clients virtinst qemu-kvm"
      log_info "Arch Linux: sudo pacman -S qemu-full libvirt virt-install"
      exit 1
    fi
  done

  # Check for ISO creation tool (mkisofs or genisoimage)
  if ! command -v mkisofs &>/dev/null && ! command -v genisoimage &>/dev/null; then
    log_error "Neither mkisofs nor genisoimage found"
    log_info "Ubuntu/Debian: sudo apt install genisoimage"
    log_info "Arch Linux: sudo pacman -S cdrtools"
    exit 1
  fi

  # Check if user is in libvirt group
  if ! groups | grep -q libvirt; then
    log_warn "User not in 'libvirt' group. You may need sudo for virsh commands."
    log_info "Add yourself with: sudo usermod -aG libvirt \$USER && newgrp libvirt"
  fi

  # Check KVM support
  if [[ ! -e /dev/kvm ]]; then
    log_error "/dev/kvm not found. KVM support required."
    exit 1
  fi

  log_info "Prerequisites OK"
}

generate_ssh_key() {
  if [[ -f "$SSH_KEY_PATH" ]]; then
    log_info "SSH key already exists: $SSH_KEY_PATH"
  else
    log_info "Generating SSH key pair: $SSH_KEY_PATH"
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "macula-infrastructure"
  fi

  export SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")
}

download_base_image() {
  if [[ -f "$BASE_OS_IMAGE_PATH" ]]; then
    log_info "Base OS image already exists: $BASE_OS_IMAGE_PATH"
  else
    log_info "Downloading Debian 12 cloud image..."
    sudo curl -L "$BASE_OS_IMAGE_URL" -o "$BASE_OS_IMAGE_PATH"
    sudo chmod 644 "$BASE_OS_IMAGE_PATH"
  fi
}

create_network() {
  log_info "Setting up libvirt network: $NETWORK_NAME"

  # Check if network already exists
  if sudo virsh net-info "$NETWORK_NAME" &>/dev/null; then
    log_warn "Network $NETWORK_NAME already exists. Destroying and recreating..."
    sudo virsh net-destroy "$NETWORK_NAME" 2>/dev/null || true
    sudo virsh net-undefine "$NETWORK_NAME"
  fi

  # Define and start network (requires sudo for bridge creation)
  sudo virsh net-define "$NETWORK_XML"
  sudo virsh net-start "$NETWORK_NAME"
  sudo virsh net-autostart "$NETWORK_NAME"

  log_info "Network $NETWORK_NAME created and started"
}

create_cloud_init_iso() {
  local vm_name=$1
  local hostname=$2
  local cloud_init_template=$3
  local iso_path="/var/lib/libvirt/images/${vm_name}-cloud-init.iso"
  local temp_dir=$(mktemp -d)

  # Output to stderr since this function returns a value via echo
  log_info "Creating cloud-init ISO for $vm_name..." >&2

  # Prepare meta-data
  cat > "$temp_dir/meta-data" <<EOF
instance-id: $vm_name
local-hostname: $hostname
EOF

  # Prepare user-data (replace SSH key placeholder)
  sed "s|SSH_PUBLIC_KEY_PLACEHOLDER|$SSH_PUBLIC_KEY|g" \
    "$cloud_init_template" | \
    sed "s|HOSTNAME_PLACEHOLDER|$hostname|g" \
    > "$temp_dir/user-data"

  # Create ISO (use mkisofs or genisoimage, whichever is available)
  if command -v mkisofs &>/dev/null; then
    mkisofs -output "$temp_dir/${vm_name}-cloud-init.iso" \
      -volid cidata \
      -joliet \
      -rock \
      "$temp_dir/user-data" \
      "$temp_dir/meta-data" &>/dev/null
  elif command -v genisoimage &>/dev/null; then
    genisoimage -output "$temp_dir/${vm_name}-cloud-init.iso" \
      -volid cidata \
      -joliet \
      -rock \
      "$temp_dir/user-data" \
      "$temp_dir/meta-data" &>/dev/null
  else
    log_error "Neither mkisofs nor genisoimage found. Install cdrtools or genisoimage." >&2
    exit 1
  fi

  sudo mv "$temp_dir/${vm_name}-cloud-init.iso" "$iso_path"
  sudo chmod 644 "$iso_path"
  rm -rf "$temp_dir"

  echo "$iso_path"
}

create_vm_disk() {
  local vm_name=$1
  local disk_size=$2
  local disk_path="/var/lib/libvirt/images/${vm_name}.qcow2"

  if [[ -f "$disk_path" ]]; then
    log_warn "Disk already exists: $disk_path (reusing)"
    return
  fi

  log_info "Creating disk for $vm_name (${disk_size}GB)..."
  sudo qemu-img create -f qcow2 -F qcow2 -b "$BASE_OS_IMAGE_PATH" "$disk_path" "${disk_size}G" &>/dev/null
  sudo qemu-img resize "$disk_path" "${disk_size}G" &>/dev/null
  sudo chmod 644 "$disk_path"
}

create_hub_vm() {
  local vm_name="${HUB_VM[name]}"
  local ram="${HUB_VM[ram]}"
  local vcpus="${HUB_VM[vcpus]}"
  local disk_size="${HUB_VM[disk]}"
  local mac="${HUB_VM[mac]}"

  log_info "Creating Hub VM: $vm_name"

  # Check if VM already exists
  if virsh dominfo "$vm_name" &>/dev/null; then
    log_warn "VM $vm_name already exists. Destroying..."
    virsh destroy "$vm_name" 2>/dev/null || true
    virsh undefine "$vm_name" --remove-all-storage 2>/dev/null || true
  fi

  # Create disk
  create_vm_disk "$vm_name" "$disk_size"

  # Create cloud-init ISO
  local cloud_init_iso=$(create_cloud_init_iso "$vm_name" "$vm_name" "$INFRA_DIR/libvirt/cloud-init-hub.yaml")

  # Create VM
  sudo virt-install \
    --name "$vm_name" \
    --ram "$ram" \
    --vcpus "$vcpus" \
    --disk path="/var/lib/libvirt/images/${vm_name}.qcow2",format=qcow2,bus=virtio \
    --disk path="$cloud_init_iso",device=cdrom \
    --network network="$NETWORK_NAME",mac="$mac" \
    --os-variant debian12 \
    --virt-type kvm \
    --graphics none \
    --console pty,target_type=serial \
    --noautoconsole \
    --import

  log_info "Hub VM $vm_name created"
}

create_edge_vm() {
  local vm_name=$1
  local ip=$2
  local mac=$3

  log_info "Creating Edge VM: macula-$vm_name"

  local full_name="macula-$vm_name"

  # Check if VM already exists
  if virsh dominfo "$full_name" &>/dev/null; then
    log_warn "VM $full_name already exists. Destroying..."
    virsh destroy "$full_name" 2>/dev/null || true
    virsh undefine "$full_name" --remove-all-storage 2>/dev/null || true
  fi

  # Create disk
  create_vm_disk "$full_name" "$EDGE_DISK"

  # Create cloud-init ISO
  local cloud_init_iso=$(create_cloud_init_iso "$full_name" "$full_name" "$INFRA_DIR/libvirt/cloud-init-edge.yaml")

  # Create VM
  sudo virt-install \
    --name "$full_name" \
    --ram "$EDGE_RAM" \
    --vcpus "$EDGE_VCPUS" \
    --disk path="/var/lib/libvirt/images/${full_name}.qcow2",format=qcow2,bus=virtio \
    --disk path="$cloud_init_iso",device=cdrom \
    --network network="$NETWORK_NAME",mac="$mac" \
    --os-variant debian12 \
    --virt-type kvm \
    --graphics none \
    --console pty,target_type=serial \
    --noautoconsole \
    --import

  log_info "Edge VM $full_name created"
}

wait_for_vm_ssh() {
  local vm_name=$1
  local ip=$2
  local max_attempts=60
  local attempt=0

  log_info "Waiting for $vm_name to be SSH-accessible at $ip..."

  while (( attempt < max_attempts )); do
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=2 ubuntu@"$ip" "echo OK" &>/dev/null; then
      log_info "$vm_name is ready!"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 5
  done

  log_error "$vm_name did not become accessible after ${max_attempts} attempts"
  return 1
}

main() {
  log_info "=== Macula Infrastructure Bootstrap ==="

  check_prerequisites
  generate_ssh_key
  download_base_image
  create_network

  # Create Hub VM
  create_hub_vm

  # Create Edge VMs
  for edge in "${!EDGE_VMS[@]}"; do
    IFS=':' read -r ip mac <<< "${EDGE_VMS[$edge]}"
    create_edge_vm "$edge" "$ip" "$mac"
  done

  log_info "All VMs created. Waiting for them to boot..."

  # Wait for VMs to be accessible
  wait_for_vm_ssh "${HUB_VM[name]}" "${HUB_VM[ip]}"

  for edge in "${!EDGE_VMS[@]}"; do
    IFS=':' read -r ip mac <<< "${EDGE_VMS[$edge]}"
    wait_for_vm_ssh "macula-$edge" "$ip"
  done

  log_info ""
  log_info "=== Bootstrap Complete ==="
  log_info "Next steps:"
  log_info "  1. Provision Hub VM: ./scripts/provision-hub.sh"
  log_info "  2. Provision Edge VMs: ./scripts/provision-edge.sh <edge-name>"
  log_info "  3. Or use macula-ctl TUI: cd macula-ctl && go run . dashboard"
  log_info ""
  log_info "SSH access:"
  log_info "  Hub:  ssh -i $SSH_KEY_PATH ubuntu@${HUB_VM[ip]}"
  for edge in "${!EDGE_VMS[@]}"; do
    IFS=':' read -r ip mac <<< "${EDGE_VMS[$edge]}"
    log_info "  $edge: ssh -i $SSH_KEY_PATH ubuntu@$ip"
  done
}

main "$@"
