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
  globals,
  host,
  ...
}: {
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
    # himmelblaud: auth-entra.nix hands /dev/tpmrm0 to that group (Hello PIN);
    # the local user needs it too for age-plugin-tpm (unlock-secrets / rage).
    extraGroups = ["wheel" "himmelblaud"];

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

  security.sudo.wheelNeedsPassword = true;

  # The home lives on the rolled-back root; anything not listed here is gone
  # at next reboot. Paths are relative to the home, stored under
  # /persist/<homeDir>/<...>. Declared here, not in storage-impermanence: it
  # names the account this file creates.
  environment.persistence."/persist".users.${host.userName} = {
    directories = [
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
    ];
    files = [".bash_history"];
  };

  # Eval-time plaintext of secrets/globals.nix.age (nix/rageImportEncrypted.sh).
  # Keyed by ciphertext hash, so a changed secret misses the cache and needs one
  # TPM PIN (prompted by eval itself, or via `unlock-secrets` without a tty);
  # an unchanged one never touches the TPM again. Persisted so a reboot does
  # not force the PIN either. Accepted risk: 0700 to the local user, the only
  # account that can rebuild anyway (trusted-users, checkout, PIN identity),
  # and the pool itself is encrypted.
  environment.persistence."/persist".directories = [
    {
      directory = "/var/tmp/nix-import-encrypted";
      user = host.userName;
      group = "users";
      mode = "0700";
    }
  ];
}
