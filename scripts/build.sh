#!/usr/bin/bash
# Description: Script to build the UNetLab kernel for Proxmox VE.

# Variables for colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
PVE_COMMIT=144fbc40a5f18743b9831a70de9046a0ffdc206e
PVE_VERSION=6.8.12-2
PATCHES_REPO="sudoalx/unetlab-kernel"
GH_REPO="https://github.com/${PATCHES_REPO}.git"
PVE_REPO="git://git.proxmox.com/git/pve-kernel.git"
PVE_KERNEL_DIR="/usr/src/pve-kernel"
UNETLAB_KERNEL_DIR="/usr/src/unetlab-kernel"
CUSTOM_POSTFIX="pnetlab" # Custom postfix for the kernel version: -pve-${CUSTOM_POSTFIX}
NOTES="UNetLab Kernel for PVE ${PVE_VERSION}\nOriginal commit:\n\n- Title: update ABI file for ${PVE_VERSION}-pve\n- Hash: \`${PVE_COMMIT}\`\n- Link: [git.proxmox.com](https://git.proxmox.com/?p=pve-kernel.git;a=commit;h=${PVE_COMMIT})"

# Exit on error
set -e

# Set default git repository
gh repo set-default ${PATCHES_REPO}

# Function to check if required packages are installed
function check_package() {
    PACKAGE=$1
    if ! dpkg -l | grep -q "$PACKAGE"; then
        echo -e "${YELLOW}Installing missing package: $PACKAGE${NC}"
        apt-get install -y "$PACKAGE"
    else
        echo -e "${GREEN}$PACKAGE is already installed.${NC}"
    fi
}

# Function to install prerequisites
function install_prerequisites() {
    echo -e "${BLUE}Updating package lists...${NC}"
    apt-get update
    REQUIRED_PACKAGES=(git build-essential dh-make dh-python sphinx-common asciidoc-base bison dwarves flex libdw-dev libelf-dev libiberty-dev libnuma-dev libslang2-dev libssl-dev lintian lz4 python3-dev xmlto zlib1g-dev)
    for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
        check_package "$PACKAGE"
    done
}

# Check local environment
PVE=$(dpkg -l | egrep "proxmox-kernel-[0-9.-]+-pve-signed" | wc -l)
if [ "$PVE" -ne 1 ]; then
    echo -e "${RED}ERROR: Script must run on a dedicated PVE installation.${NC}"
    echo -e "${YELLOW}Are you sure you want to continue?${NC}"
    read -p "Do you want to continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    else
        echo -e "${YELLOW}Continuing on a non-PVE system.${NC}"
    fi
fi

# Install prerequisites
install_prerequisites

# Remove conflicting packages (proxmox-headers)
HEADERS=$(dpkg -l | grep -c "proxmox-headers")
if [ "$HEADERS" -ne 0 ]; then
    echo -e "${YELLOW}Removing conflicting proxmox-headers packages.${NC}"
    apt-get purge -y proxmox-headers* || true # Ignore errors
fi

# Clone the UNetLab patches
if [ ! -d "${UNETLAB_KERNEL_DIR}" ]; then
    echo -e "${BLUE}Cloning UNetLab patches.${NC}"
    git clone ${GH_REPO} ${UNETLAB_KERNEL_DIR}
else
    echo -e "${YELLOW}UNetLab kernel already exists, skipping clone. Do you want to overwrite it?${NC}"
    read -p "Do you want to overwrite the existing UNetLab kernel? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf ${UNETLAB_KERNEL_DIR}
        echo -e "${BLUE}Cloning UNetLab patch.${NC}"
        git clone ${GH_REPO} ${UNETLAB_KERNEL_DIR}
    fi
fi

# Clone the PVE kernel
if [ ! -d "${PVE_KERNEL_DIR}" ]; then
    echo -e "${BLUE}Cloning Proxmox VE kernel.${NC}"
    git clone ${PVE_REPO} ${PVE_KERNEL_DIR}
else
    echo -e "${YELLOW}Proxmox VE kernel already exists, skipping clone. Do you want to overwrite it?${NC}"
    read -p "Do you want to overwrite the existing Proxmox VE kernel? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf ${PVE_KERNEL_DIR}
        echo -e "${BLUE}Cloning Proxmox VE kernel.${NC}"
        git clone ${PVE_REPO} ${PVE_KERNEL_DIR}
    fi
fi

# Switch to PVE kernel directory and checkout commit
cd ${PVE_KERNEL_DIR}
git checkout $PVE_COMMIT

# Ask before cleaning make
read -p "Do you want to clean the make files? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Clean and prepare build directory
    echo -e "${BLUE}Cleaning and preparing build directory.${NC}"
    make clean
    make build-dir-fresh
fi

# Apply the transparent bridge patch
echo -e "${BLUE}Patching the kernel.${NC}"
sed -i 's/^EXTRAVERSION=.*/EXTRAVERSION=-$(KREL)-pve-'$CUSTOM_POSTFIX'/' ${PVE_KERNEL_DIR}/Makefile
patch -p1 <${UNETLAB_KERNEL_DIR}/patches/transparent-bridge.patch

# Compile the kernel
echo -e "${BLUE}Compiling the kernel.${NC}"
make

# Go back to the PATCHES_REPO directory
echo -e "${BLUE}Switching back to the UNetLab patches repository.${NC}"
cd ${UNETLAB_KERNEL_DIR}

# Tag the kernel version in the PVE kernel repo
echo -e "${BLUE}Tagging the kernel with version: ${PVE_VERSION}.${NC}"

# Check if the tag already exists
if git rev-parse -q --verify "refs/tags/${PVE_VERSION}" &>/dev/null; then
    echo -e "${YELLOW}Tag ${PVE_VERSION} already exists.${NC}"
    read -p "Do you want to overwrite the existing tag or create a new one with a different name? (o/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Oo]$ ]]; then
        git tag -d ${PVE_VERSION}
        git push origin --delete ${PVE_VERSION}
        git tag ${PVE_VERSION} -a
        git push origin --tags
    else
        read -p "Enter the new tag name: " NEW_TAG
        git tag "${NEW_TAG}" -a
        git push origin --tags
    fi
else
    git tag ${PVE_VERSION} -a
    git push origin --tags
fi

# Check if GitHub CLI is installed
if ! command -v gh &>/dev/null; then
    echo -e "${RED}GitHub CLI (gh) not found, please install it to create releases.${NC}"
else
    # Create a release in the PATCHES_REPO
    read -p "Do you want to create a release on GitHub? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Creating GitHub release for version: ${PVE_VERSION} in the ${PATCHES_REPO} repository.${NC}"
        # Display release notes
        echo -e "$NOTES"
        gh release create ${PVE_VERSION} --latest --target=master --title "${PVE_VERSION}" --notes "${NOTES}" ${PVE_KERNEL_DIR}/proxmox-headers-*${CUSTOM_POSTFIX}_*.deb ${PVE_KERNEL_DIR}/proxmox-kernel-*${CUSTOM_POSTFIX}-signed*.deb ${PVE_KERNEL_DIR}/proxmox-kernel-*${CUSTOM_POSTFIX}_*.deb
        echo -e "${GREEN}Release created successfully. You can find it at: https://github.com/${PATCHES_REPO}/releases/tag/${PVE_VERSION}${NC}"
    fi
    echo -e "${GREEN}You can find the compiled kernel in the ${PVE_KERNEL_DIR} directory.${NC}"
fi

# Display success message
echo -e "${GREEN}Build task completed successfully!${NC}"
