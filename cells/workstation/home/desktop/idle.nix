# swayidle — idle management daemon for Wayland.
# Vanilla dwl has no dwl-msg IPC binary, so the DPMS toggle uses wlopm.
{
  pkgs,
  lib,
  idleLock,
  ...
}: let
  lock = "${pkgs.swaylock}/bin/swaylock -fF";
in {
  services.swayidle = {
    enable = true;
    events = lib.optionals idleLock [
      {
        event = "before-sleep";
        command = lock;
      }
      {
        event = "lock";
        command = lock;
      }
    ];
    timeouts =
      lib.optional idleLock {
        timeout = 300;
        command = lock;
      }
      ++ [
        {
          timeout = 600;
          command = "${pkgs.wlopm}/bin/wlopm --off '*'";
          resumeCommand = "${pkgs.wlopm}/bin/wlopm --on '*'";
        }
      ]
      ++ lib.optional idleLock {
        timeout = 1800;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      };
  };
}
