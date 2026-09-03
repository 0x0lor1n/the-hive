# The desktop home-manager config. Built twice by profiles/layer-compositor.nix:
# as a NixOS module for the local user (home-manager.users.<name>) and as a
# standalone activationPackage for the Entra user, who is not in users.users
# and so cannot go through the NixOS module. utils.mkHome is broken upstream
# (bee.home).
#
# Takes the username/home explicitly: both live in the encrypted half of
# globals and cannot be attribute names in a public file. Desktop only for
# now; editor/agent tooling is a separate later step.
{
  userName,
  homeDir,
  theme,
}: {pkgs, ...}: let
  k = theme.colors;
  ansi = theme.ansi;
in {
  # Every desktop module below reads the palette from this arg.
  _module.args.theme = theme;

  home.username = userName;
  home.homeDirectory = homeDir;
  # Must match system.stateVersion in nixosConfigurations.nix.
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  # nixpkgs is unstable, home-manager is release-25.05: intentional.
  home.enableNixpkgsReleaseCheck = false;

  imports = [./desktop];

  # DWL's terminal keybind execs `foot` by name, so it must be on PATH.
  programs.foot = {
    enable = true;
    settings = {
      # 10 fits more on 1920x1080 than the default 12 and stays readable.
      main.font = "monospace:size=10";
      main.pad = "8x8";
      # Palette from cells/theme (foot uses rrggbb, no #); the 16 ANSI slots
      # come from theme.ansi, same list the VT console uses.
      # foot >= 1.23 moved cursor.color into the colors section, and 1.27
      # renamed [colors] -> [colors-dark] ([colors] is deprecated, cursor.color
      # is a hard error). The CachyOS nixpkgs pin ships 1.27.
      colors-dark =
        {
          foreground = k.fujiWhite;
          background = k.sumiInk3;
          cursor = "${k.sumiInk3} ${k.oldWhite}";
          selection-foreground = k.oldWhite;
          selection-background = k.waveBlue2;
        }
        // builtins.listToAttrs (pkgs.lib.imap0 (i: c: {
            name =
              if i < 8
              then "regular${toString i}"
              else "bright${toString (i - 8)}";
            value = c;
          })
          ansi);
    };
  };
}
