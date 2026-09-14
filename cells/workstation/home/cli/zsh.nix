# zsh: p10k prompt, vi mode, zsh-autocomplete menu, sqlite history (histdb)
# with skim Ctrl-R, autosuggestions, fast-syntax-highlighting. Ported from
# jarvis's users/shared/cli/zsh with the standalone-only parts dropped
# (the non-NixOS guards, make-zsh-default-shell, catppuccin fsh theme).
#
# The four hand-edited files (config.zsh, functions.zsh, key-bindings.zsh,
# .p10k.zsh) are NOT store-backed: they are symlinked from
# /srv/the-hive/dotfiles/zsh (profiles/srv-the-hive.nix) so either account
# edits them in place. mkOutOfStoreSymlink never reads the target, so
# dotfiles/ cannot influence a build.
#
# Both halves are needed for zsh to be the login shell: this module writes
# ~/.config/zsh/.zshrc; the SYSTEM side (programs.zsh.enable, the login
# shell per account) is layer-users-local.nix and auth-entra.nix.
{
  config,
  pkgs,
  lib,
  cellPackages,
  ...
}: let
  dotfiles = "/srv/the-hive/dotfiles/zsh";
  # Out-of-store: a plain symlink to the runtime path, no copy into the store.
  live = f: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${f}";

  # All plugins from the nixpkgs pin except zsh-histdb: nixpkgs ships
  # 90a6c10 (2024-04-18), which merged the HISTORY_IGNORE change (7b010a6 +
  # f73d9c8) that broke this setup on jarvis. 30797f0 is the last commit
  # before that series (checked against upstream master 2026-09-15; nothing
  # else in between), so the derivation stays nixpkgs', only src moves.
  zshHistdb = pkgs.zsh-histdb.overrideAttrs (_: {
    version = "0-unstable-2022-01-18";
    src = pkgs.fetchFromGitHub {
      owner = "larkery";
      repo = "zsh-histdb";
      rev = "30797f0c50c31c8d8de32386970c5d480e5ab35d";
      hash = "sha256-PQIFF8kz+baqmZWiSr+wc4EleZ/KD8Y+lxW2NT35/bg=";
    };
  });
  fsh = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh";
  histdb = "${zshHistdb}/share/zsh-histdb/sqlite-history.zsh";
  histdbSkim = "${cellPackages.zsh-histdb-skim}/share/zsh-histdb-skim/zsh-histdb-skim.plugin.zsh";
in {
  home.packages = with pkgs; [
    sqlite-interactive # histdb queries
    zsh-completions
  ];

  programs.zsh = {
    enable = true;
    dotDir = ".config/zsh";
    enableCompletion = true;
    history = {
      save = 1000500;
      size = 1000000;
      # ~/.local/share/zsh is the impermanence carve-out for BOTH accounts
      # (layer-users-local.nix, auth-entra.nix); the home root itself is
      # rolled back at boot. histdb's sqlite file sits next to it.
      path = "${config.xdg.dataHome}/zsh/history";
    };

    completionInit = ''
      # Completion plugin
      setopt GLOB_DOTS # show dotfiles in completion menus
      zstyle ':autocomplete:key-bindings' enabled no
      zstyle ':autocomplete:*' delay 0.1  # Add delay to reduce lag
      zstyle ':autocomplete:*' min-input 2  # Only complete after 2 chars
      source ${pkgs.zsh-autocomplete}/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
      source ${pkgs.zsh-defer}/share/zsh-defer/zsh-defer.plugin.zsh
    '';

    initContent = lib.mkMerge [
      (lib.mkBefore ''
        # Powerlevel10k instant prompt.
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')
      (lib.mkOrder 550 ''
        [[ ! -f ${config.xdg.configHome}/zsh/.p10k.zsh ]] || source ${config.xdg.configHome}/zsh/.p10k.zsh
        # Theme
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      '')
      ''
        export HISTDB_DEFAULT_TAB="Directory"
        export HISTDB_FILE="${config.xdg.dataHome}/zsh/history.db"

        source ${histdb}
        source ${config.xdg.configHome}/zsh/config.zsh
        source ${config.xdg.configHome}/zsh/functions.zsh

        # Autosuggestions (ghost text from history/completion)
        export ZSH_AUTOSUGGEST_MANUAL_REBIND=true
        export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
        export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
        export ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=()
        export ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS=()
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh

        # Syntax highlighting
        zle_highlight=('paste:fg=white,bold') # Remove background from pasted text
        source ${fsh}

        # Clipboard (cross-platform clipcopy/clippaste)
        source ${pkgs.oh-my-zsh}/share/oh-my-zsh/lib/clipboard.zsh

        # History reverse search
        source ${histdbSkim}
        # FIXME: only shell.nix and eza.nix shellAliases are displayed
        source ${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins/aliases/aliases.plugin.zsh
        # ZSH in Nix-Shell
        source ${pkgs.zsh-nix-shell}/share/zsh-nix-shell/nix-shell.plugin.zsh

        # Vi mode configuration (called before zsh-vi-mode loads)
        function zvm_config() {
          ZVM_ESCAPE_KEYTIMEOUT=0
          ZVM_KEYTIMEOUT=0.2
          ZVM_VI_HIGHLIGHT_BACKGROUND=black
          ZVM_VI_HIGHLIGHT_FOREGROUND=white
          ZVM_VI_SURROUND_BINDKEY=s-prefix
          ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT
          ZVM_INSERT_MODE_CURSOR=$ZVM_CURSOR_BLINKING_BEAM
          ZVM_OPPEND_MODE_CURSOR=$ZVM_CURSOR_BLINKING_BLOCK
        }

        # Called after zsh-vi-mode initializes (load keybindings here)
        function zvm_after_init() {
          # Load skim key-bindings (must be after zsh-vi-mode to avoid conflicts)
          if [[ $options[zle] = on ]]; then
            source ${pkgs.skim}/share/skim/completion.zsh
            source ${pkgs.skim}/share/skim/key-bindings.zsh
          fi
          source ${config.xdg.configHome}/zsh/key-bindings.zsh
        }

        source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
      ''
    ];
  };

  # Live-editable, see the header. .zshrc sources them by their
  # ~/.config/zsh path, so the store never sees dotfiles/.
  xdg.configFile = {
    "zsh/.p10k.zsh".source = live ".p10k.zsh";
    "zsh/config.zsh".source = live "config.zsh";
    "zsh/functions.zsh".source = live "functions.zsh";
    "zsh/key-bindings.zsh".source = live "key-bindings.zsh";
  };
}
