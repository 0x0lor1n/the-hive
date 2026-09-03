# Plain swaylock (not swaylock-effects) — no blur/images, just locking.
# PAM config lives in layer-session.nix instead (HM can't install PAM).
{pkgs, ...}: let
  k = import ./kanagawa.nix;
in {
  programs.swaylock = {
    enable = true;
    settings = {
      color = k.sumiInk3;
      inside-color = k.sumiInk4;
      ring-color = k.crystalBlue;
      key-hl-color = k.springGreen;
      bs-hl-color = k.autumnRed;
      inside-ver-color = k.sumiInk4;
      ring-ver-color = k.oniViolet;
      inside-wrong-color = k.sumiInk4;
      ring-wrong-color = k.autumnRed;
      text-color = k.fujiWhite;
      text-ver-color = k.fujiWhite;
      text-wrong-color = k.fujiWhite;
      line-color = k.sumiInk3;
      separator-color = k.sumiInk3;
      font-size = 24;
      indicator-idle-visible = true;
      indicator-radius = 100;
      show-failed-attempts = true;
    };
  };
}
