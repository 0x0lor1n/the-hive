# CachyOS kernel + zfs from nyx. specialisation.safe must keep the same zfs
# release, or the pool won't import there.
{
  config,
  pkgs,
  lib,
  ...
}: {
  # mkOverride 99 rather than mkDefault (1000): the specialisation below wins
  # with 98, and nothing else in this repo should silently replace the kernel.
  boot.kernelPackages = lib.mkOverride 99 pkgs.linuxPackages_cachyos;
  boot.zfs.package = lib.mkOverride 99 pkgs.zfs_cachyos;

  specialisation.safe.configuration = {
    system.nixos.tags = ["lts" "zfs-stable"];
    boot.kernelPackages = lib.mkOverride 98 pkgs.linuxPackages;
    boot.zfs.package = lib.mkForce pkgs.zfs;
  };

  # Guest nix daemon: fetch the kernel from nyx instead of rebuilding it on a
  # `nixos-rebuild` inside the VM. Same values as nyx's flake.nix nixConfig.
  nix.settings = {
    extra-substituters = ["https://nyx-cache.chaotic.cx/"];
    extra-trusted-public-keys = ["nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="];
  };
}
