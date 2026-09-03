# The local user's home-manager config, consumed as a NixOS module via
# home-manager.users.<name> in profiles/layer-compositor.nix. utils.mkHome is
# broken upstream (bee.home), and standalone HM is not wanted anyway: the
# system and the home must switch together.
#
# Takes `host` (this host's globals entry) rather than a username: the
# username lives in the encrypted half of globals and cannot be an attribute
# name in a public file. Desktop only for now; editor/agent tooling is a
# separate later step.
{host}: {pkgs, ...}: let
  k = import ./desktop/kanagawa.nix;
in {
  home.username = host.userName;
  home.homeDirectory = host.homeDir;
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
      # Kanagawa Wave, as shipped in foot's themes/ (foot uses rrggbb, no #).
      cursor.color = "${k.sumiInk3} ${k.oldWhite}";
      colors = {
        foreground = k.fujiWhite;
        background = k.sumiInk3;
        selection-foreground = k.oldWhite;
        selection-background = k.waveBlue2;
        regular0 = "090618"; # black
        regular1 = k.autumnRed;
        regular2 = k.autumnGreen;
        regular3 = k.boatYellow2;
        regular4 = k.crystalBlue;
        regular5 = k.oniViolet;
        regular6 = k.waveAqua1;
        regular7 = k.oldWhite;
        bright0 = k.fujiGray;
        bright1 = k.samuraiRed;
        bright2 = k.springGreen;
        bright3 = k.carpYellow;
        bright4 = k.springBlue;
        bright5 = k.springViolet1;
        bright6 = k.waveAqua2;
        bright7 = k.fujiWhite;
      };
    };
  };
}
