# DisplayLink docks (elster's at work, penrose's ThinkPad Hybrid USB-C at
# home). kanshi picks the evdi head up as DVI-I-1 (home/desktop/outputs.nix).
{
  inputs,
  cell,
}: {
  lib,
  pkgs,
  ...
}: {
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
