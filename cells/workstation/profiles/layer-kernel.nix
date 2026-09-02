# CachyOS kernel + the matching ZFS module, both from chaotic-cx/nyx so they
# are built against each other. The nyx overlay is applied to `ren.pkgs` in
# nixosConfigurations.nix (NOT via nixpkgs.overlays: utils.mkSystem hands the
# module system a ready `pkgs`, which makes that option a no-op).
#
# Second boot entry "safe" (PedroHLC/system-setup seat.nix): stock nixpkgs
# kernel + stock zfs, for when a CachyOS bump breaks boot, ZFS or the GPU.
# Both zfs builds are the same upstream release (2.4.4 at the 34ab9907 pin),
# so a pool touched by one imports on the other; keep it that way when
# bumping -- a pool with feature flags the fallback cannot read is a pool
# that will not import.
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
