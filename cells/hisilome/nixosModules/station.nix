# process-compose.yaml's graph as systemd units. Absent on purpose: build-site
# (a derivation, built off-host) and tag-music (run on the workstation before
# rsync; ReplayGain tags travel inside the files).
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hisilome;
  runtime = cfg.stateDir;
  radioState = "${runtime}/radio/state";

  # "liquidsoap cannot write outside its state dir" -- what a container would
  # buy, at no closure cost.
  hardening = {
    ReadWritePaths = [radioState];
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
  };

  # build-queue exits 1 on an empty library, which failed the first activation
  # before the library was rsynced. Empty is valid: serve the site, no station.
  emptyTolerantQueue = pkgs.writeShellApplication {
    name = "build-queue-if-music";
    runtimeInputs = [
      cell.packages.build-queue
      pkgs.findutils
      pkgs.coreutils
    ];
    text = ''
      if [ -z "$(find music -type f \
            \( -iname "*.flac" -o -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.opus" \
               -o -iname "*.ogg" -o -iname "*.wav" \) -print -quit 2>/dev/null)" ]; then
        echo "build-queue-if-music: no playable files under $PWD/music -- skipping."
        exit 0
      fi
      exec build-queue --rounds ${toString cfg.queueRounds} music
    '';
  };
in {
  config = lib.mkIf cfg.enable {
    systemd.services.icecast = {
      description = "Icecast stream server";
      wantedBy = ["multi-user.target"];
      after = ["hisilome-setup.service"];
      requires = ["hisilome-setup.service"];
      serviceConfig =
        {
          ExecStart = "${pkgs.icecast}/bin/icecast -c ${runtime}/radio/icecast.xml";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = runtime;
          Restart = "on-failure";
          RestartSec = 2;
        }
        // hardening;
    };

    # Before liquidsoap: reload_mode="watch" on a missing playlist is not
    # recoverable.
    systemd.services.hisilome-build-queue = {
      description = "Rebuild the Hísilómë play queue";
      after = ["hisilome-setup.service"];
      requires = ["hisilome-setup.service"];
      wantedBy = ["multi-user.target"];
      before = ["liquidsoap.service"];
      environment = {
        DIR = "music";
        OUT = "radio/state";
      };
      serviceConfig =
        {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${emptyTolerantQueue}/bin/build-queue-if-music";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = runtime;
        }
        // hardening;
    };

    systemd.timers.hisilome-build-queue = {
      description = "Reshuffle the Hísilómë queue daily";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };

    systemd.services.liquidsoap = {
      description = "Liquidsoap encoder for Hísilómë";
      wantedBy = ["multi-user.target"];
      after = [
        "hisilome-setup.service"
        "icecast.service"
        "hisilome-build-queue.service"
      ];
      requires = [
        "hisilome-setup.service"
        "hisilome-build-queue.service"
      ];
      # After icecast but not bound to it: liquidsoap retries the source.
      # Condition, not failure, on a missing queue: an unsynced library serves
      # the site with no station instead of crash-looping.
      unitConfig.ConditionPathExists = "${radioState}/queue.m3u";
      serviceConfig =
        {
          ExecStart = "${pkgs.liquidsoap}/bin/liquidsoap ${runtime}/radio/radio.liq";
          EnvironmentFile = "${radioState}/source.env";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = runtime;
          Restart = "always";
          RestartSec = 5;
        }
        // hardening;
    };

    systemd.services.hisilome-listeners = {
      description = "Poll icecast for the listener count";
      wantedBy = ["multi-user.target"];
      after = ["icecast.service"];
      environment.OUT = "radio/state/listeners.txt";
      serviceConfig =
        {
          ExecStart = "${cell.packages.listener-count}/bin/listener-count";
          EnvironmentFile = "${radioState}/admin.env";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = runtime;
          Restart = "always";
          RestartSec = 10;
        }
        // hardening;
    };
  };
}
