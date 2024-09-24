#!/bin/bash

# Variables
PVE_COMMIT=144fbc40a5f18743b9831a70de9046a0ffdc206e
PVE_VERSION=6.8.12-2
NOTES="UNetLab Kernel for PVE ${PVE_VERSION}\nOriginal commit:\n\n- Title: update ABI file for ${PVE_VERSION}-pve\n- Hash: \`${PVE_COMMIT}\`\n- Link: [git.proxmox.com](https://git.proxmox.com/?p=pve-kernel.git;a=commit;h=${PVE_COMMIT})"
PATCHES_REPO="https://github.com/sudoalx/unetlab-kernel"
PVE_REPO="git://git.proxmox.com/git/pve-kernel.git"

# Exit on error
set -e

# Function to check if required packages are installed
function check_package() {
    PACKAGE=$1
    if ! dpkg -l | grep -q "$PACKAGE"; then
        echo "Installing missing package: $PACKAGE"
        apt-get install -y "$PACKAGE"
    else
        echo "$PACKAGE is already installed."
    fi
}

# Function to install prerequisites
function install_prerequisites() {
    apt-get update
    REQUIRED_PACKAGES=(git build-essential dh-make dh-python sphinx-common asciidoc-base bison dwarves flex libdw-dev libelf-dev libiberty-dev libnuma-dev libslang2-dev libssl-dev lintian lz4 python3-dev xmlto zlib1g-dev)
    for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
        check_package "$PACKAGE"
    done
}

# Check local environment
PVE=$(dpkg -l | egrep "proxmox-kernel-[0-9.-]+-pve-signed" | wc -l)
if [ "$PVE" -ne 1 ]; then
    echo ERROR: script must run on a dedicated PVE installation
    exit 1
fi

# Install prerequisites
install_prerequisites

# Remove conflicting packages (proxmox-headers)
HEADERS=$(dpkg -l | grep -c "proxmox-headers")
if [ "$HEADERS" -ne 0 ]; then
    echo "Removing conflicting proxmox-headers packages."
    apt-get purge -y proxmox-headers*
fi

# Clone the UNetLab patches
if [ ! -d "/usr/src/unetlab-kernel" ]; then
    echo "Cloning UNetLab patches."
    git clone ${PATCHES_REPO} /usr/src/unetlab-kernel
else
    echo "UNetLab kernel already exists, skipping clone. Do you want to overwrite it?"
    read -p "Do you want to overwrite the existing UNetLab kernel? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf /usr/src/unetlab-kernel
        echo "Cloning UNetLab patch."
        git clone ${PATCHES_REPO} /usr/src/unetlab-kernel
    fi
fi

# Clone the PVE kernel
if [ ! -d "/usr/src/pve-kernel" ]; then
    echo "Cloning Proxmox VE kernel."
    git clone ${PVE_REPO} /usr/src/pve-kernel
else
    echo "Proxmox VE kernel already exists, skipping clone. Do you want to overwrite it?"
    read -p "Do you want to overwrite the existing Proxmox VE kernel? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf /usr/src/pve-kernel
        echo "Cloning Proxmox VE kernel."
        git clone ${PVE_REPO} /usr/src/pve-kernel
    fi
fi
cd /usr/src/pve-kernel
git checkout $PVE_COMMIT

# Clean and prepare build directory
echo "Cleaning and preparing build directory."
make clean
make build-dir-fresh

# Apply the transparent bridge patch
echo "Patching the kernel."
sed -i 's/^EXTRAVERSION=.*/EXTRAVERSION=-$(KREL)-pve-unl/' /usr/src/pve-kernel/Makefile
patch -p1 </usr/src/unetlab-kernel/patches/transparent-bridge.patch

# Compile the kernel
echo "Compiling the kernel."
make -j"$(nproc)"

# Tag the kernel version
echo "Tagging the kernel with version: ${PVE_VERSION}."
git tag ${PVE_VERSION} -a
git push origin --tags

# Check if GitHub CLI is installed
if ! command -v gh &>/dev/null; then
    echo "GitHub CLI (gh) not found, please install it to create releases."
else
    # Create a release
    read -p "Do you want to create a release on GitHub? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Creating GitHub release for version: ${PVE_VERSION}."
        gh release create ${PVE_VERSION} --latest --target=master --title "${PVE_VERSION}" --notes "${NOTES}" /usr/src/pve-kernel/proxmox-headers-*unl_*.deb /usr/src/pve-kernel/proxmox-kernel-*unl-signed*.deb /usr/src/pve-kernel/proxmox-kernel-*unl_*.deb
    fi
fi

# Display release notes
echo -e "$NOTES"
