# The desktop home-manager config. Built twice by profiles/layer-compositor.nix:
# as a NixOS module for the local user (home-manager.users.<name>) and as a
# standalone activationPackage for the Entra user, who is not in users.users
# and so cannot go through the NixOS module. utils.mkHome is broken upstream
# (bee.home).
#
# Takes the username/home explicitly: both live in the encrypted half of
# globals and cannot be attribute names in a public file.
{
  userName,
  homeDir,
  theme,
  # Per-user additions on top of the shared desktop (Entra-only apps etc).
  extraPackages ? [],
  # Commit identity ({name, email}) or null: only the local user, who holds
  # the checkout, commits; the Entra account gets git without a configured
  # author so a stray commit fails loudly instead of leaking a work UPN.
  git ? null,
  # Per-role attrset from home/secrets.nix (secrets/user-<role>.nix.age):
  # git.includes (includeIf blocks), ssh.includes and ssh.matchBlocks, the
  # latter pointing at the account's own age.secrets keys
  # (profiles/secrets.nix). {} when the file is absent, so a host without
  # secrets still evaluates.
  secrets ? {},
  # The personal account: osint + tor (home/security). The Entra home gets
  # neither -- the employer's desktop plane carries no bridges or recon kit.
  personal ? false,
  # cells/deck/homeModules: the shell toolkit, shared by every account on
  # every workstation. Passed in, not imported: home/ has no `inputs`.
  deck ? {},
  # cells/repo/packages: claude-code, opencode, oh-my-opencode, rtk -- the
  # agent CLIs dev/agents.nix installs. Same reason as deck: no `inputs` here.
  agentPkgs ? {},
  # Where a plain login shell lands (tty, ssh, `su -`). null keeps $HOME.
  startDir ? null,
  # .desktop that gets https:// links. Only the Entra account overrides it,
  # with himmelblau's o365-url-handler (profiles/auth-entra.nix).
  httpsHandler ? "firefox.desktop",
}: {
  pkgs,
  lib,
  ...
}: let
  k = theme.colors;
  ansi = theme.ansi;
  sec = secrets;
in {
  # Every module below reads the palette from this arg; ssh matchBlocks /
  # git includes below read the account's encrypted set.
  _module.args.theme = theme;
  _module.args.secrets = sec;
  _module.args.agentPkgs = agentPkgs;

  home.username = userName;
  home.homeDirectory = homeDir;
  # Must match system.stateVersion in nixosConfigurations.nix.
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  # nixpkgs is unstable, home-manager is release-25.05: intentional.
  home.enableNixpkgsReleaseCheck = false;

  imports = [./desktop ./dev] ++ lib.optional personal ./security ++ builtins.attrValues deck;

  home.packages = extraPackages;

  # Default browser for the OpenURI portal: sandboxed apps (Slack SSO
  # redirect) hand links to xdg-desktop-portal, which resolves the
  # x-scheme-handler default via GAppInfo and, with one set, launches it
  # without an app-chooser dialog. Firefox is a systemPackage
  # (browser-firefox.nix), so its .desktop is on XDG_DATA_DIRS for both users.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = httpsHandler;
      "text/html" = "firefox.desktop";
      # slack.com hands the SSO token to the app through a slack:// link that
      # must route to the (sandboxed) Slack entry, not the browser.
      "x-scheme-handler/slack" = "slack.desktop";
    };
  };

  # Where a login shell starts. foot already lands in tmux at /srv/the-hive
  # (sesh.toml), so this only covers tty / ssh / `su -`. The $PWD guard keeps
  # `ssh <host> 'cd /tmp && ...'` and any non-login subshell where they were.
  programs.zsh.initContent = lib.mkIf (startDir != null) (lib.mkOrder 1500 ''
    if [[ -o interactive && $PWD == $HOME ]]; then
      cd ${lib.escapeShellArg startDir}
    fi
  '');

  # Declared, not `git config --global`: ~/.gitconfig is not persisted.
  # userName/userEmail/extraConfig: the release-25.05 API (settings is 25.11+).
  programs.git = {
    enable = true;
    userName = lib.mkIf (git != null) git.name;
    userEmail = lib.mkIf (git != null) git.email;
    # includeIf per remote glob (git >= 2.36 hasconfig): the encrypted half
    # decides which remotes get which author. Only remotes this account holds
    # a key for are listed there, so alias, glob and key stay in lockstep.
    includes = sec.git.includes or [];
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      # /srv/the-hive is owned by the local account but shared with the Entra
      # user over the hive group (0750). Without this git refuses every
      # command there under Entra ("dubious ownership"), which also kills the
      # rensa direnv hook (`git rev-parse --show-toplevel` -> "Not inside a
      # git repository"). /srv/workspace/* the same way for cross-owned
      # checkouts. Trailing /* needs git >= 2.46 (pinned 2.55).
      safe.directory = ["/srv/the-hive" "/srv/workspace/*"];
    };
  };

  # Host aliases + IdentityFile from the encrypted half; the keys themselves
  # are age.secrets owned by this account (profiles/secrets.nix). Most private
  # halves carry a passphrase, so an agent per account: keys are added on first
  # use and the passphrase is typed once per session.
  programs.ssh = {
    enable = true;
    addKeysToAgent = "yes";
    # Globs relative to ~/.ssh, read before the blocks below. The files they
    # name are plaintext and not managed here: a per-pod HostName/Port can be
    # rewritten between jobs without a TPM PIN. An unmatched glob is fine.
    includes = sec.ssh.includes or [];
    matchBlocks = sec.ssh.matchBlocks or {};
  };
  services.ssh-agent.enable = true;

  # DWL's terminal keybind execs `foot` by name, so it must be on PATH.
  programs.foot = {
    enable = true;
    settings = {
      # 10 fits more on 1920x1080 than the default 12 and stays readable.
      main.font = "monospace:size=10";
      main.pad = "8x8";
      # Every foot window lands in tmux: sesh attaches to the "the-hive"
      # session or creates it. Ctrl+Shift+<key> is translated to CSI-u so the
      # tmux prefix (C-S-b) and the C-S-* binds actually arrive; foot's own
      # bindings for those chords are disabled so they don't eat them.
      main.shell = "${pkgs.sesh}/bin/sesh connect the-hive";
      key-bindings = {
        scrollback-up-page = "none";
        scrollback-down-page = "none";
        spawn-terminal = "none";
        unicode-input = "none";
        prompt-prev = "none";
        prompt-next = "none";
      };
      text-bindings = {
        "\\x1b[98;6u" = "Control+Shift+b";
        "\\x1b[100;6u" = "Control+Shift+d";
        "\\x1b[102;6u" = "Control+Shift+f";
        "\\x1b[107;6u" = "Control+Shift+k";
        "\\x1b[108;6u" = "Control+Shift+l";
        "\\x1b[110;6u" = "Control+Shift+n";
        "\\x1b[112;6u" = "Control+Shift+p";
        "\\x1b[113;6u" = "Control+Shift+q";
        "\\x1b[116;6u" = "Control+Shift+t";
        "\\x1b[117;6u" = "Control+Shift+u";
        "\\x1b[119;6u" = "Control+Shift+w";
        # Enter chords: tmux binds C-Enter / C-S-Enter (swap / split), and
        # hermes/claude take Shift+Enter as newline. foot only encodes these
        # once an app pushes kitty-keyboard/modifyOtherKeys — which never
        # reaches it through tmux — so emit CSI-u unconditionally.
        # Super+Shift+Return is the muscle-memory split chord; tmux has no
        # Super modifier, so it is sent as the same C-S-Enter sequence (dwl
        # does not bind it -- new window is Super+Alt+T).
        "\\x1b[13;2u" = "Shift+Return";
        "\\x1b[13;5u" = "Control+Return";
        "\\x1b[13;6u" = "Control+Shift+Return Super+Shift+Return";
      };
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
