#!/bin/bash

PVE_COMMIT=69b55c504cab6549ee4ddcf8cef87c32699fbdb0
PVE_VERSION=6.8.8-3
NOTES="UNetLab Kernel for PVE 6.8.4-2\nOriginal commit:\n\n- Title: update ABI file for ${PVE_VERSION}-pve\n- Hash: \`${PVE_COMMIT}\`\n- Link: [git.proxmox.com](https://git.proxmox.com/?p=pve-kernel.git;a=commit;h=${PVE_COMMIT})"

set -e

# Check local environment
PVE=$(dpkg -l | egrep "proxmox-kernel-[0-9.-]+-pve-signed" | wc -l)
if [ $PVE -ne 1 ]; then
    echo ERROR: script must run on a dedicated PVE installation
    exit 1
fi

# Adding prerequisites
apt-get install -y git build-essential dh-make dh-python sphinx-common asciidoc-base bison dwarves flex libdw-dev libelf-dev libiberty-dev libnuma-dev libslang2-dev libssl-dev lintian lz4 python3-dev xmlto zlib1g-dev

# Removing conflicting packages
HEADERS=$(dpkg -l | egrep "proxmox-headers" | wc -l)
if [ $HEADERS -ne 0 ]; then
    apt-get purge -y proxmox-headers*
fi

# Cloning UNetLab patch
git clone https://github.com/dainok/unetlab-kernel /usr/src/unetlab-kernel

# Cloning PVE kernel
rm -rf /usr/src/pve-kernel
git clone git://git.proxmox.com/git/pve-kernel.git /usr/src/pve-kernel
cd /usr/src/pve-kernel
git checkout $PVE_COMMIT
make clean
make build-dir-fresh

# Patching the kernel
sed -i /usr/src/pve-kernel/Makefile -e "s/^EXTRAVERSION=.*/EXTRAVERSION=-\$\(KREL\)-pve-unl/"
patch -p1 < /usr/src/unetlab-kernel/patches/transparent-bridge.patch

# Compile the kernel
make

# Tag
git tag ${PVE_VERSION} -a
git push origin --tags

# Create release
echo -e $NOTES
# gh release create ${PVE_VERSION} --latest --target=master --title ${PVE_VERSION} --notes "${NOTES}" /usr/src/pve-kernel/proxmox-headers-*unl_*.deb /usr/src/pve-kernel/proxmox-kernel-*unl-signed*.deb /usr/src/pve-kernel/proxmox-kernel-*unl_*.deb
