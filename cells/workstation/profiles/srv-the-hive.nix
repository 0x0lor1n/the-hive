# /srv/the-hive: the ONE checkout of this repo on the workstation, read by
# both accounts (decision 2026-09-14).
#
#   /srv/the-hive           <local>:hive 0750 -- group reads, only the owner
#                           (who rebuilds) writes. cells/ inherits that.
#   /srv/the-hive/dotfiles  group-writable through a DEFAULT POSIX ACL --
#                           nvim/tmux/zsh live here and home-manager points
#                           at them with mkOutOfStoreSymlink, so either
#                           account edits in place without a rebuild.
#
# Why an ACL and not the obvious things (all measured on penrose 2026-09-14):
# core.sharedRepository only touches .git/, setgid fixes the group but not
# the mode, umask is per shell and a checkout under 022 silently drops the
# group bit. A default ACL is inherited by every file git creates later,
# under any umask. ACLs are not in git and are lost on a fresh clone, so the
# rule is re-applied by tmpfiles at every boot (A+ is recursive).
#
# Safety: the symlink target is a runtime path string, never an eval-time
# input -- nothing in dotfiles/ can influence a build, so group write there
# does not leak into what root builds.
#
# The dataset (rpool/safe/srv/the-hive, disks/<host>.nix) is not subject to
# the @blank rollback. The clone itself is a one-off user step:
#   sudo zfs create -o canmount=off -o mountpoint=none rpool/safe/srv
#   sudo zfs create -o mountpoint=legacy rpool/safe/srv/the-hive
#   (rebuild, so the mount + rules below are live)
#   git clone <this repo> /srv/the-hive     # as the local user
#   sudo systemd-tmpfiles --create         # or wait for the next boot
{
  lib,
  host,
  ...
}: {
  # Local for the local user; the Entra account gets it from himmelblau's
  # local_groups (auth-entra.nix), same as networkmanager.
  users.groups.hive = {};
  users.users.${host.userName}.extraGroups = ["hive"];

  # The mount itself comes from disko (disks/<host>.nix declares the
  # dataset with mountpoint = "/srv/the-hive"); nothing to repeat here.

  # .envrc is trusted for both accounts without `direnv allow`: the checkout
  # is 0750 owner-only writable and its .envrc is pinned by content hash.
  # Here and not in home-manager: the NixOS direnv module (common/base.nix)
  # sets DIRENV_CONFIG=/etc/direnv, so only its settings are ever read.
  programs.direnv.settings.whitelist.prefix = ["/srv/the-hive"];

  systemd.tmpfiles.rules = [
    # `z`, not `d`: adjust the mountpoint's owner/mode, never create a dir
    # that would then block `git clone` into it.
    "z /srv/the-hive 0750 ${host.userName} hive -"
    # No `d` for dotfiles/ either (same clone reason); before the clone the
    # line is a no-op with a warning. Named-group entries so the files' own
    # group (users, from the cloning account) does not matter.
    "A+ /srv/the-hive/dotfiles - - - - d:group:hive:rwx,group:hive:rwx"
    # .ren/ is rensa's direnv layout (REN_STATE): the hook writes
    # .ren/.gitignore and .ren/direnv/ on every load, for whichever account
    # cd's in. Same ACL as dotfiles, or the Entra side dies with EACCES right
    # after git's safe.directory lets it through (2026-09-15). `d` is fine
    # here: the dir is gitignored and the clone never has to create it.
    "d  /srv/the-hive/.ren 2770 ${host.userName} hive -"
    "A+ /srv/the-hive/.ren - - - - d:group:hive:rwx,group:hive:rwx"
  ];
}
