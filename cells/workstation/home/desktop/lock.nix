# Plain swaylock (not swaylock-effects) — no blur/images, just locking.
# PAM config lives in layer-session.nix instead (HM can't install PAM).
{
  pkgs,
  theme,
  ...
}: let
  k = theme.roles;
in {
  programs.swaylock = {
    enable = true;
    settings = {
      color = k.bg;
      inside-color = k.bgAlt;
      ring-color = k.focus;
      key-hl-color = k.accent;
      bs-hl-color = k.urgent;
      inside-ver-color = k.bgAlt;
      ring-ver-color = k.hover;
      inside-wrong-color = k.bgAlt;
      ring-wrong-color = k.urgent;
      text-color = k.fg;
      text-ver-color = k.fg;
      text-wrong-color = k.fg;
      line-color = k.bg;
      separator-color = k.bg;
      font-size = 24;
      indicator-idle-visible = true;
      indicator-radius = 100;
      show-failed-attempts = true;
    };
  };
}
