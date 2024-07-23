# UNetLab kernel for Proxmox VE

This repository contains the script to compile a custom Proxmox Kernel in order to customize L2 forwarding. The script must run on a dedicated PVE server with the original kernel.

Once the kernel is installed, bridges can be enabled to forward any frame with:

```bash
echo 65535 > /sys/class/net/vmbr1/bridge/group_fwd_mask
echo 0 > /sys/devices/virtual/net/vmbr1/bridge/multicast_snooping
```

The scripts can be added to `/etc/network/interfaces` so they are called once when interfaces transition to the `up` state.

## Build/update the patch

To to update the script in order to patch latest kernel, please:

- Identify the commit for latest kernel: in the [web repository](https://git.proxmox.com/?p=pve-kernel.git;a=summary "Linux Kernel for Proxmox projects"), look for the commit `update ABI file for 6.8.4-2-pve` and get the commit ID (`4cab886f26f9c8638593b8c553996c97ca9acc21`).
- Adjust the `scripts/build.sh` script.
- Update the `patches/transparent-bridge.patch` patch using the `diff -Naur` command.
