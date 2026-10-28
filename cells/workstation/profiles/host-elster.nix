# elster-only: docker, DisplayLink. Split out when a second host
# wants any of it.
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  ...
}: {
  virtualisation.docker = {
    enable = true;
    # /var/lib/docker is a legacy-mounted ZFS dataset; overlay2 on top of it
    # works. The `zfs` storage driver would want to manage datasets itself.
    storageDriver = "overlay2";
    # Nothing runs at boot on a laptop; the socket starts the daemon on demand.
    enableOnBoot = false;
    autoPrune.enable = true;
  };
  # dialout: flash and talk to the bench MCUs (/dev/ttyACM*, root:dialout)
  # without sudo; under sudo nix runs as root, which lacks safe.directory.
  # docker: the rootful socket, i.e. root without sudo -- admin only.
  users.users = lib.mkMerge [
    (lib.genAttrs config.hive.localUsers (_: {extraGroups = ["dialout"];}))
    (lib.genAttrs config.hive.roleHolders.admin (_: {extraGroups = ["docker"];}))
  ];
  # The Entra account: himmelblau reconciles group membership on login
  # (local_groups_reconcile_interval), same path as `hive`/`networkmanager`
  # in auth-entra.nix.
  services.himmelblau.settings.local_groups = ["dialout"];

  # DisplayLink through the nixpkgs module: it keys on the xserver driver
  # list, but everything that matters for a Wayland session (evdi module,
  # udev rules, the DisplayLinkManager service) is gated on that same
  # switch. dwl/wlroots picks the evdi DRM node up like any other card.
  # Unfree manual download: nix-prefetch-url the Synaptics zip before a build.
  services.xserver.videoDrivers = ["displaylink"];
  # The monitor is on evdi, whose cursor plane DLM appears to drop updates
  # for (the pointer vanishes until the next shape change). A software
  # cursor is drawn into the frame, which DLM always ships.
  session.compositorEnvironment.WLR_NO_HARDWARE_CURSORS = "1";
  # The nixpkgs unit orders after display-manager.service, which greetd does
  # not provide; anchor it on the seat instead so it comes up at boot.
  systemd.services.dlm = {
    after = lib.mkForce ["systemd-udev-settle.service"];
    wantedBy = ["multi-user.target"];
    # chaotic-nyx's cachyos module overlay strips the userspace half of evdi
    # ("Don't build userspace stuff": no lib/libevdi.so), but the nixpkgs
    # module links displaylink against boot.kernelPackages.evdi, so DLM's
    # dlopen("libevdi.so") fails and it idles without ever creating a DRM
    # node (strace: ENOENT on every RPATH entry, no /sys/devices/evdi/add).
    # The library is kernel-agnostic; borrow it from the stock kernel set,
    # which the evdiOverlay bumps to the same 1.15.1.
    environment.LD_LIBRARY_PATH = "${pkgs.linuxPackages.evdi}/lib";
  };
}
