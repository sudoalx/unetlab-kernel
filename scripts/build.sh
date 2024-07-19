#!/bin/bash

PVE_COMMIT=4cab886f26f9c8638593b8c553996c97ca9acc21

set -e

# Check local environment
PVE=$(dpkg -l | egrep "proxmox-kernel-[0-9.-]+-pve-signed" | wc -l)
if [ $PVE -ne 1 ]; then
    echo ERROR: script must run on a dedicated PVE installation
    exit 1
fi

# Adding prerequisites
apt-get install -y git build-essential dh-make dh-python sphinx-common asciidoc-base bison dwarves flex libdw-dev libelf-dev libiberty-dev libnuma-dev libslang2-dev libssl-dev lintian lz4 python3-dev xmlto zlib1g-dev

# Cloning UNetLab patch
git clone https://github.com/dainok/unetlab-kernel /usr/src/unetlab-kernel

# Cloning PVE kernel
git clone git://git.proxmox.com/git/pve-kernel.git /usr/src/pve-kernel
cd /usr/src/pve-kernel
git checkout $PVE_COMMIT
make clean
make build-dir-fresh

# Patching the kernel
sed -i /usr/src/pve-kernel/Makefile -e "s/EXTRAVERSION=.*/EXTRAVERSION=-\$\(KREL\)-pve-unl/"
patch -p1 < /usr/src/unetlab-kernel/patches/transparent-bridge.patch

# Compile the kernel
make
