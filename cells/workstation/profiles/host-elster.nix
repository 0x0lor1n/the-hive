# elster-only hardware/workload bits: what the ZBook needs that penrose must
# not carry (state: port-jarvis-home, phase 5). Kept out of intelLaptop on
# purpose -- one host, one file; split into profiles when a second host wants
# any of it.
#
# - docker: some work projects need it. Both accounts in the `docker` group
#   (Entra via himmelblau local_groups, not users.users -- it has no entry).
#   /var/lib/docker is its own dataset (disks/elster.nix, rpool/safe/docker),
#   so nothing to persist here. Old jarvis volumes are NOT migrated (user
#   2026-09-15).
# - DisplayLink: Lenovo ThinkPad Hybrid USB-C dock (17e9:6015). On TB4 the
#   first output is DP alt-mode; the extra heads are DisplayLink (evdi).
#   Unfree with a manual download: the Synaptics zip must be in the store
#   before build (nix-prefetch-url, see pkgs.displaylink.src.message).
# - 5G modem (mtk_t7xx, 14c3:4d75): unused, driver is in-kernel, no
#   ModemManager. Nothing to declare.
# - kernel: layer-kernel's CachyOS 7.2.2 already covers Raptor Lake i915 and
#   AX211 (iwlwifi); no override.
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  host,
  ...
}: {
  virtualisation.docker = {
    enable = true;
    # /var/lib/docker is a legacy-mounted ZFS dataset; overlay2 on top of it
    # works and is what the Ubuntu install ran. The `zfs` storage driver would
    # want to manage datasets itself -- not wanted.
    storageDriver = "overlay2";
    # Nothing runs at boot on a laptop; the socket starts the daemon on demand.
    enableOnBoot = false;
    autoPrune.enable = true;
  };
  users.users.${host.userName}.extraGroups = ["docker"];
  # The Entra account: himmelblau reconciles group membership on login
  # (local_groups_reconcile_interval), same path as `hive`/`networkmanager`
  # in auth-entra.nix.
  services.himmelblau.settings.local_groups = ["docker"];

  # DisplayLink through the nixpkgs module: it keys on the xserver driver
  # list, but everything that matters for a Wayland session (evdi module,
  # udev rules, the DisplayLinkManager service) is gated on that same
  # switch. dwl/wlroots picks the evdi DRM node up like any other card.
  services.xserver.videoDrivers = ["displaylink"];
  # The nixpkgs unit orders after display-manager.service, which greetd does
  # not provide; anchor it on the seat instead so it comes up at boot.
  systemd.services.dlm = {
    after = lib.mkForce ["systemd-udev-settle.service"];
    wantedBy = ["multi-user.target"];
  };
}
