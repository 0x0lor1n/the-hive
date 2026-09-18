# recorder: wl-screenrec screen capture -> ~/Videos/Recordings/*.mp4, file://
# URI on the clipboard, mako notification with open / open-in-fm actions,
# thumbnail from ffmpegthumbnailer. Second call while recording stops it.
# Bound in packages/dwl/config.h to Super+Alt+R (--area). The bar (bar.nix)
# polls `recorder --status` and shows a REC badge while one runs; clicking it
# stops.
#
# wl-screenrec encodes through VA-API (intel-media-driver from
# profiles/gpu-intel.nix); without a working va device it falls back to
# software x264 and only warns.
{
  pkgs,
  theme,
  ...
}: let
  recorder = pkgs.writeShellApplication {
    name = "recorder";
    runtimeInputs = with pkgs; [
      wl-screenrec
      slurp
      ffmpegthumbnailer
      imagemagick
      wl-clipboard
      libnotify
      inotify-tools
      xdg-user-dirs
      xdg-utils
      procps
      coreutils
    ];
    text =
      builtins.replaceStrings
      ["@theme_bg@" "@theme_focus@"]
      [theme.roles.bg theme.roles.focus]
      (builtins.readFile ./recorder.sh);
  };
in {
  home.packages = [recorder];
}
