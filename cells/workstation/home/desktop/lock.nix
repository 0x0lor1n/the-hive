# Plain swaylock (not swaylock-effects) — no blur/images, just locking.
# PAM config lives in layer-session.nix instead (HM can't install PAM).
{pkgs, ...}: {
  programs.swaylock = {
    enable = true;
    settings = {
      color = "1e1e2e";
      font-size = 24;
      indicator-idle-visible = true;
      indicator-radius = 100;
      show-failed-attempts = true;
    };
  };
}
