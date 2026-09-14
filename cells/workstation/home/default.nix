# The desktop home-manager config. Built twice by profiles/layer-compositor.nix:
# as a NixOS module for the local user (home-manager.users.<name>) and as a
# standalone activationPackage for the Entra user, who is not in users.users
# and so cannot go through the NixOS module. utils.mkHome is broken upstream
# (bee.home).
#
# Takes the username/home explicitly: both live in the encrypted half of
# globals and cannot be attribute names in a public file. Desktop only for
# now; editor/agent tooling is a separate later step.
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
  # git.includes (includeIf blocks) and ssh.matchBlocks, both pointing at
  # the account's own age.secrets keys (profiles/secrets.nix). {} when the
  # file is absent, so a host without secrets still evaluates.
  secrets ? {},
}: {
  pkgs,
  lib,
  ...
}: let
  k = theme.colors;
  ansi = theme.ansi;
  sec = secrets;
in {
  # Every module below reads the palette from this arg; security/ reads the
  # account's encrypted key/vpn set.
  _module.args.theme = theme;
  _module.args.secrets = sec;

  home.username = userName;
  home.homeDirectory = homeDir;
  # Must match system.stateVersion in nixosConfigurations.nix.
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  # nixpkgs is unstable, home-manager is release-25.05: intentional.
  home.enableNixpkgsReleaseCheck = false;

  imports = [./desktop ./cli ./dev ./security];

  home.packages = extraPackages;

  # Default browser for the OpenURI portal: sandboxed apps (Slack SSO
  # redirect) hand links to xdg-desktop-portal, which resolves the
  # x-scheme-handler default via GAppInfo and, with one set, launches it
  # without an app-chooser dialog. Edge is a systemPackage, so its .desktop
  # is on XDG_DATA_DIRS for both users.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "microsoft-edge.desktop";
      "x-scheme-handler/https" = "microsoft-edge.desktop";
      "text/html" = "microsoft-edge.desktop";
      # The way back: slack.com hands the SSO token to the app through a
      # slack:// link Edge must route to the (sandboxed) Slack entry.
      "x-scheme-handler/slack" = "slack.desktop";
    };
  };

  # Declared, not `git config --global`: ~/.gitconfig is not persisted and
  # the repo-local user.* that got set by hand is what this replaces.
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
    };
  };

  # Host aliases + IdentityFile from the encrypted half; the keys themselves
  # are age.secrets owned by this account (profiles/secrets.nix). The
  # private halves carry a passphrase, so an agent per account: keys are
  # added on first use and the passphrase is typed once per session.
  programs.ssh = {
    enable = true;
    addKeysToAgent = "yes";
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
