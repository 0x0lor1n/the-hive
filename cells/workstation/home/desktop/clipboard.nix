# cliphist + wl-clipboard — clipboard history manager.
# cliphist needs two background processes watching text and image
# selections. Both are invoked from the DWL startup script (see
# cells/workstation/profiles/layer-compositor.nix). No systemd unit — HM has no
# services.cliphist module as of HM release-25.05.
{pkgs, ...}: {
  home.packages = [
    pkgs.wl-clipboard # provides wl-copy / wl-paste
    pkgs.cliphist # history daemon + picker
  ];
}
