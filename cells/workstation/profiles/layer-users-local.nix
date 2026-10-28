# The local (non-Entra) unix user: account, sudo policy, and the carve-outs
# that survive the @blank rollback of its home.
#
# Workstation-only: osgiliath is root-key-only and stops at
# common/layer-users-root.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  config,
  globals,
  host,
  ...
}: let
  roles = (lib.findFirst (a: a.auth == "local") {roles = [];} config.hive.accounts).roles;
  has = role: lib.elem role roles;
in {
  # tss owns /dev/tpmrm0 (0660) when himmelblau's udev rule does not.
  security.tpm2.enable = !config.services.himmelblau.enable;

  # /etc/zshenv + /run/current-system/sw/bin/zsh (also what auth-entra.nix
  # names as himmelblau's shell). Completion and prompt stay OFF here:
  # deck/homeModules/zsh.nix runs compinit through zsh-autocomplete, which must be
  # the only compinit call, and p10k is the prompt.
  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
    promptInit = "";
  };

  users.users.${host.userName} = {
    isNormalUser = true;
    uid = globals.user.uid;
    # /dev/tpmrm0 for age-plugin-tpm (unlock-secrets / rage): auth-entra.nix
    # hands it to himmelblaud (Hello PIN) where there is an Entra account,
    # security.tpm2's tss group (below) everywhere else.
    # wheel comes with the admin role (role-admin.nix).
    extraGroups =
      if config.services.himmelblau.enable
      then ["himmelblaud"]
      else ["tss"];

    # Fleet default from the encrypted half of globals, per-host public
    # override for the playground VMs (AGENTS.md documents the passphrase).
    # The encrypted value must satisfy the tenant's Intune Linux password
    # policy (>=8 chars, digit + lowercase + symbol) or enrolment reports the
    # device non-compliant.
    hashedPassword =
      if host.hashedPassword != null
      then host.hashedPassword
      else globals.user.hashedPassword;
    home = host.homeDir;
    # deck/homeModules/zsh.nix writes the rc files; the login shell is a system
    # setting and HM alone would leave the account on bash.
    shell = pkgs.zsh;

    # Per host, matching secrets.nix's generatedSecretsDir, so a playground
    # key can never be authorised on real hardware.
    openssh.authorizedKeys.keyFiles = [
      (inputs.self.outPath + "/secrets/generated/${host.hostName}/user-ssh-key.pub")
    ];
  };

  # The home lives on the rolled-back root; anything not listed here is gone
  # at next reboot. Paths are relative to the home, stored under
  # /persist/<homeDir>/<...>. Declared here, not in storage-impermanence: it
  # names the account this file creates.
  environment.persistence."/persist".users.${host.userName} = {
    directories =
      [
        # sshd refuses keys at anything looser than 0700.
        {
          directory = ".ssh";
          mode = "0700";
        }
        # The fleet repo checkout: what `nixos-rebuild --flake .#<host>` runs from.
        "the-hive"
        # direnv's allow-list, so `cd the-hive` does not re-prompt every boot.
        ".local/share/direnv"
        # Agent state: hermes config/sessions/skills; claude credentials +
        # settings, and ~/.claude.json too via CLAUDE_CONFIG_DIR (layer-session).
        # 0700: both hold API keys.
        {
          directory = ".hermes";
          mode = "0700";
        }
        {
          directory = ".claude";
          mode = "0700";
        }
        # cli/dev state — keep in sync with the Entra allowlist in auth-entra.nix.
        ".local/share/zsh"
        # zoxide's frecency db (db.zo) — empty after every boot otherwise.
        ".local/share/zoxide"
        # tmux-resurrect snapshots (prefix+C-s), restored with prefix+C-r.
        ".local/share/tmux/resurrect"
        # lazygit state.yml: recent repos, dismissed startup popups. Without it
        # every first lazygit after boot behaves like a fresh install.
        ".local/state/lazygit"
        # neovim state: lazy.nvim plugin clones (~110 repos), mason binaries,
        # compiled treesitter parsers. Nothing authoritative (lazy-lock.json
        # pins it), but without it every first nvim after boot re-clones and
        # re-compiles for minutes.
        ".local/share/nvim"
        # whisper.cpp + Parakeet models (transcribe), ~1 GB, fetched from HF.
        ".local/share/asr-models"
        # Whole ~/.cache: powerlevel10k hardcodes its dump/instant-prompt files
        # to $XDG_CACHE_HOME root (typeset -gr, no override), and without them
        # the first zsh after boot pays ~10 s (measured 2026-09-14). Nothing
        # here is authoritative — every app rebuilds its cache on miss.
        ".cache"
        # Firefox profile dir -- see the same entry in auth-entra.nix.
        # Firefox 154+ uses XDG_CONFIG_HOME/mozilla instead of ~/.mozilla.
        ".config/mozilla"
        ".config/opencode"
        {
          directory = ".local/share/opencode";
          mode = "0700";
        }
        # home/desktop/chat.nix (unsandboxed): Mattermost is Electron
        # (~/.config/<productName>), SimpleX keeps its db under XDG_DATA_HOME.
        ".config/Mattermost"
        ".local/share/simplex"
        # home/desktop/music: mpd db, queue/state, playlists.
        ".local/share/mpd"
        # home/desktop/keepass.nix: settings (.config) and the vault itself
        # (.local/share/keepassxc/*.kdbx). Recent-db list is under .cache.
        ".config/keepassxc"
        {
          directory = ".local/share/keepassxc";
          mode = "0700";
        }
        # home/desktop/torrent.nix: settings, resume data (BT_backup).
        ".config/qBittorrent"
        ".local/share/qBittorrent"
        # home/dev/agents.nix: herdr keeps session.json (workspaces, cwds,
        # agent names + native session ids) in .config/herdr, next to the
        # config.toml symlink and the sockets. Without it every reboot starts
        # with one empty workspace. resume_agents_on_restore is on by default,
        # so hermes/claude/opencode panes come back with `--resume <id>`.
        # .local/state/herdr: agent-detection cache, cheap to keep.
        ".config/herdr"
        ".local/state/herdr"
      ]
      # The role's apps (home/roles/*.nix); nixpak keeps each app's state under
      # one Flatpak-style dir. Same list as the Entra side in auth-entra.nix.
      ++ lib.optionals (has "dev") [
        ".var/app/org.telegram.desktop"
        ".local/share/Grayjay"
      ]
      ++ lib.optionals (has "employer") [
        ".var/app/com.slack.Slack"
        # Horizon: server list, prefs, plus the gm sign-in Chromium profile.
        ".omnissa"
      ];
    files = [".bash_history"];
  };

  programs.ssh = {
    knownHosts = {
      minas-tirith = {
        hostNames = ["minas-tirith" "192.168.10.1"];
        publicKeyFile = inputs.self.outPath + "/secrets/hosts/minas-tirith/ssh_host_ed25519_key.pub";
      };
      minas-tirith-initrd = {
        hostNames = ["minas-tirith-initrd" "[192.168.10.1]:2222"];
        publicKeyFile = inputs.self.outPath + "/secrets/hosts/minas-tirith/initrd_ssh_host_ed25519_key.pub";
      };
      imladris = {
        hostNames = ["imladris" "192.168.10.10"];
        publicKeyFile = inputs.self.outPath + "/secrets/hosts/imladris/ssh_host_ed25519_key.pub";
      };
    };
    extraConfig = ''
      Host minas-tirith
        HostName 192.168.10.1
        User ${host.userName}
        IdentityFile /run/agenix/user-ssh-key
        IdentitiesOnly yes
      # ZFS passphrase prompt when the TPM unseal fails (server/initrd-ssh).
      Host minas-tirith-initrd
        HostName 192.168.10.1
        Port 2222
        User root
        HostKeyAlias minas-tirith-initrd
        IdentityFile /run/agenix/user-ssh-key
        IdentitiesOnly yes
      Host imladris
        HostName 192.168.10.10
        User ${host.userName}
        IdentityFile /run/agenix/user-ssh-key
        IdentitiesOnly yes
    '';
  };
}
