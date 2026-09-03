# mako registers both a user systemd unit and a D-Bus activation file,
# so it starts on first notification even without being in the DWL
# startup script — do not also start it from there.
{
  pkgs,
  theme,
  ...
}: let
  k = theme.colors;
in {
  # notify-send, for testing mako from the terminal.
  home.packages = [pkgs.libnotify];

  services.mako = {
    enable = true;
    settings = {
      default-timeout = 5000;
      ignore-timeout = true;
      font = "monospace 11";
      background-color = "#${k.sumiInk3}ff";
      text-color = "#${k.fujiWhite}ff";
      border-color = "#${k.crystalBlue}ff";
      border-size = 2;
      padding = "10";
    };
  };
}
