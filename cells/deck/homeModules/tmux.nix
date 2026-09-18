# tmux: sesh sessions, resurrect + continuum persistence, a custom status
# bar. config.conf, the status bar script and sesh.toml are live-edited from
# /srv/the-hive/dotfiles/tmux (out-of-store symlinks, same as zsh/nvim).
#
# No catppuccin.tmux: the status bar reads ~/.config/scripts/theme-colors.sh,
# generated from the kanagawa palette (roles.*) below.
{
  inputs,
  cell,
}: {
  config,
  pkgs,
  lib,
  ...
}: let
  dotfiles = "/srv/the-hive/dotfiles/tmux";
  live = f: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${f}";
  theme = inputs.cells.theme.palettes.kanagawa;
  r = theme.roles;

  # resurrect's process capture greps `ps` output per pane; zsh-histdb's
  # sqlite3 child shows up with a multi-line command and corrupts the save
  # file. Filter it out.
  resurrect-patched = pkgs.tmuxPlugins.resurrect.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        substituteInPlace $out/share/tmux-plugins/resurrect/save_command_strategies/ps.sh \
          --replace-fail \
            'grep "^''${PANE_PID}" |' \
            'grep "^''${PANE_PID}" | grep -v "sqlite3.*history.db" | head -1 |'
      '';
  });
in {
  home.packages = [pkgs.sesh];

  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -gu default-command
      set -g default-shell ${pkgs.zsh}/bin/zsh

      set -g popup-border-style "bg=default,fg=#${r.focus}"
      set -g pane-active-border-style "fg=#${r.focus}"
      set -g pane-border-style "fg=#${r.border}"
      set -g pane-border-lines single
      set -g popup-border-lines rounded
      set -g status off

      run-shell ${config.xdg.configHome}/tmux/plugins/status-bar/status-bar.tmux

      source-file ${config.xdg.configHome}/tmux/config.conf
    '';
  };

  xdg.configFile = {
    "tmux/config.conf".source = live "config.conf";
    "tmux/plugins/status-bar/status-bar.tmux".source = live "status-bar.tmux";
    "sesh/sesh.toml".source = live "sesh.toml";

    "tmux/plugins/resurrect".source = "${resurrect-patched}/share/tmux-plugins/resurrect";
    "tmux/plugins/continuum".source = "${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum";
    "tmux/plugins/yank".source = "${pkgs.tmuxPlugins.yank}/share/tmux-plugins/yank";
    "tmux/plugins/sensible".source = "${pkgs.tmuxPlugins.sensible}/share/tmux-plugins/sensible";

    # Sourced by status-bar.tmux, which uses exactly these three names.
    "scripts/theme-colors.sh" = {
      executable = true;
      text = ''
        base="#${r.bg}"
        surface1="#${r.border}"
        lavender="#${r.focus}"
      '';
    };
  };

  # The server outlives the login session so continuum can restore it.
  #
  # `tmux start-server \; set -g exit-empty off`: the client forks the server
  # and exits 0; Type=forking + GuessMainPID makes the daemonised server the
  # unit's main process. `tmux -D` is not usable here: tmux 3.7 insists on a
  # controlling tty under systemd and dies with "open terminal failed: not a
  # terminal" (2026-09-14).
  #
  # No ExecStop: with one, every `nixos-rebuild switch` rewrote the unit, HM
  # reloaded it, systemd ran kill-server (all sessions gone) and the clean
  # stop meant Restart=on-failure never brought it back (2026-09-14).
  # KillMode=process leaves panes' children alone, and exit-empty is forced
  # off on the command line so the server stays up with zero sessions until
  # continuum restores them or a client attaches.
  systemd.user.services.tmux-server = {
    Unit = {
      Description = "tmux server (session persistence)";
      Documentation = "man:tmux(1)";
      # No After=default.target: on the Entra account home-manager-entra is
      # itself wanted by default.target and its sd-switch starts this unit
      # (blocking) -> this unit waits for the target -> the target waits for
      # home-manager-entra -> deadlock until TimeoutStartSec (3 min, measured
      # 2026-09-15). The server needs nothing from the session.
      # HM's sd-switch must not stop+start this unit on every rebuild
      # (that would kill every session). Restart only on explicit request.
      X-SwitchMethod = "keep-old";
      # A broken config must not wedge sd-switch / nixos-rebuild.
      StartLimitIntervalSec = "60";
      StartLimitBurst = "5";
    };
    Service = {
      Type = "forking";
      Environment = ["TERM=xterm-256color" "COLORTERM=truecolor"];
      ExecStart = "${pkgs.tmux}/bin/tmux start-server \\; set -g exit-empty off";
      Restart = "on-failure";
      RestartSec = "2";
      KillMode = "process";
    };
    Install.WantedBy = ["default.target"];
  };
}
