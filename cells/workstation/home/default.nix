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
  # What the account is for, a subset of admin|dev|freelance|employer. Each
  # role with a home side is ./roles/<role>.nix; admin has none (the deck
  # shell below is everyone's).
  roles ? [],
  # dwl session apps and theming (./desktop). Off for an admin-only account.
  desktop ? true,
  # What the role modules need from outside home/: `packages` (the
  # sandboxed apps in cell.packages) and `git` ({name, email}, the personal
  # commit identity from public globals).
  roleInputs ? {},
  # Per-account attrset from home/secrets.nix (merge of secrets/roles/*.nix.age):
  # git.includes (includeIf blocks), ssh.includes and ssh.matchBlocks, the
  # latter pointing at the account's own age.secrets keys
  # (profiles/secrets.nix). {} when the file is absent, so a host without
  # secrets still evaluates.
  secrets ? {},
  # cells/deck/homeModules: the shell toolkit, shared by every account on
  # every workstation. Passed in, not imported: home/ has no `inputs`.
  deck ? {},
  # cells/repo/packages: claude-code, opencode, oh-my-opencode, rtk -- the
  # agent CLIs dev/agents.nix installs -- plus herdr and its generated
  # integrations (cells/workstation). Same reason as deck: no `inputs` here.
  agentPkgs ? {},
  # Where a plain login shell lands (tty, ssh, `su -`). null keeps $HOME.
  startDir ? null,
}: {lib, ...}: let
  sec = secrets;
  known = ["admin" "dev" "freelance" "employer"];
  unknown = lib.subtractLists known roles;
in
  assert lib.assertMsg (unknown == [])
  "home: unknown role(s) ${toString unknown} (expected ${toString known})"; {
    # Every ./desktop module reads the palette from this arg; ssh matchBlocks /
    # git includes below read the account's encrypted set.
    _module.args.theme = theme;
    _module.args.secrets = sec;
    _module.args.agentPkgs = agentPkgs;
    _module.args.accountRoles = roles;
    _module.args.roleInputs = roleInputs;

    home.username = userName;
    home.homeDirectory = homeDir;
    # Must match system.stateVersion in nixosConfigurations.nix.
    home.stateVersion = "24.11";
    programs.home-manager.enable = true;
    # nixpkgs is unstable, home-manager is release-25.05: intentional.
    home.enableNixpkgsReleaseCheck = false;

    imports =
      lib.optional desktop ./desktop
      ++ map (role: ./roles + "/${role}.nix") (lib.remove "admin" roles)
      ++ builtins.attrValues deck;

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
    # No author here: roles/dev.nix sets the default one; the includeIf
    # blocks below override it per work remote.
    programs.git = {
      enable = true;
      # includeIf per remote glob (git >= 2.36 hasconfig): the encrypted half
      # decides which remotes get which author. Only remotes this account holds
      # a key for are listed there, so alias, glob and key stay in lockstep.
      includes = sec.git.includes or [];
      # Agent working state (`<repo>/.hermes/state/*.md`, see the stateful-*
      # skills) is per-checkout scratch: never committed, in any repo. Global so
      # a fresh clone needs no per-repo .gitignore line.
      ignores = [".hermes/"];
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
        # /srv/the-hive, /srv/workspace and /srv/agents are shared by both
        # accounts over the hive group, so most checkouts there are owned by
        # the other one. Without this git refuses them ("dubious ownership"),
        # which also kills the rensa direnv hook, and nix cannot fetch them as
        # git+file inputs. "*" rather than path globs: nix goes through libgit2,
        # which has no glob support. No boundary lost -- both accounts already
        # have group rwx on all of /srv (srv-the-hive.nix, srv-workspace.nix).
        safe.directory = ["*"];
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
  }
