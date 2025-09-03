#!/bin/bash
set -euo pipefail

# Check platform compatibility
if [[ "$(uname -s)" != "Linux" ]] || [[ "$(uname -m)" != "x86_64" ]]; then
  echo "❌ This script must be run on Linux x86_64"
  exit 1
fi

# Check for required tools
for cmd in git make gcc curl mcopy mmd mkfs.vfat dd; do
  if ! command -v $cmd &>/dev/null; then
    echo "❌ Missing required command: $cmd"
    exit 1
  fi
done

# Prompt for IP/host
read -p "Enter IP or hostname for netboot.xyz menu (e.g. 10.12.0.42 or netbooty.local): " SERVER
echo "➡️  Using $SERVER as the target for netboot.xyz"

# Set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/ipxe_build"
IPXE_REPO="https://github.com/ipxe/ipxe.git"
IPXE_SRC_DIR="$BUILD_DIR/ipxe/src"
EMBED_SCRIPT="$IPXE_SRC_DIR/embed.ipxe"
IMG_NAME="$SCRIPT_DIR/ipxe-uefi-$(date +%Y%m%d%H%M%S).img"

mkdir -p "$BUILD_DIR"

# Clone iPXE if needed
if [[ ! -d "$IPXE_SRC_DIR" ]]; then
  echo "📥 Cloning iPXE repo..."
  git clone --depth 1 "$IPXE_REPO" "$BUILD_DIR/ipxe"
fi

# Write the embedded iPXE script
cat > "$EMBED_SCRIPT" <<'EOF'
#!ipxe
echo "===> Embedded iPXE script running"
sleep 2

dhcp
isset ${ip} || goto no_ip

echo "===> Got IP: ${ip} via ${net0/mac}"
echo "===> Attempting to chain to http://172.30.0.5/menu.ipxe"
sleep 2

chain http://172.30.0.5/menu.ipxe || goto fail
exit

:no_ip
echo "===> No IP address acquired"
shell

:fail
echo "===> Failed to chain to netboot.xyz"
shell
EOF

# Replace placeholder address
sed -i "s|http://172.30.0.5|http://$SERVER|g" "$EMBED_SCRIPT"

echo "🔧 Building iPXE..."
cd "$IPXE_SRC_DIR"
make bin-x86_64-efi/ipxe.efi EMBED=embed.ipxe NO_GIT=1 VERSION_MAJOR=1 VERSION_MINOR=21 VERSION_PATCH=1

cd "$SCRIPT_DIR"

echo "💽 Creating UEFI FAT image: $IMG_NAME"
dd if=/dev/zero of="$IMG_NAME" bs=1M count=64
mkfs.vfat "$IMG_NAME"
mmd -i "$IMG_NAME" ::/EFI
mmd -i "$IMG_NAME" ::/EFI/BOOT
mcopy -i "$IMG_NAME" "$IPXE_SRC_DIR/bin-x86_64-efi/ipxe.efi" ::/EFI/BOOT/BOOTX64.EFI

echo ""
echo "✅ Image ready: $IMG_NAME"
echo ""
echo "👉 Upload to Oxide:"
echo "oxide disk import --project <project> --path $IMG_NAME --description 'UEFI iPXE for $SERVER' --disk ipxe-uefi-$(date +%Y%m%d%H%M%S)"
