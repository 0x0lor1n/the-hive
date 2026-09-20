# /srv/the-hive: the one checkout of this repo on the workstation, read by
# both accounts.
#
#   /srv/the-hive           <local>:hive 0750 at the mountpoint (others: no
#                           traversal), group-writable throughout via a
#                           default POSIX ACL. Either account edits cells/,
#                           dotfiles/ and the rest in place; the owner still
#                           runs the rebuild and reviews the diff first.
#
# History: until 2026-09-20 only dotfiles/ (nvim/tmux/zsh, mkOutOfStoreSymlink
# targets) and .ren/ carried the ACL, so that group write could not influence
# what root builds. In practice the Entra account is the one doing the work
# and kept hitting EACCES on profiles/ (e.g. llm-destyle.nix drifted from its
# copy in the destyle repo because vkokurin could edit one and not the other).
# The boundary was never a real one -- the owner rebuilds from the working
# tree and reads the diff -- so it was dropped in favour of one ACL for the
# whole checkout.
#
# An ACL rather than the obvious alternatives (measured 2026-09-14):
# core.sharedRepository only touches .git/, setgid fixes the group but not the
# mode, umask is per shell and a checkout under 022 silently drops the group
# bit. A default ACL is inherited by every file git creates later, under any
# umask. ACLs are not in git and are lost on a fresh clone, so the rule is
# re-applied by tmpfiles at every boot (A+ is recursive).
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

  # The mount comes from disko (disks/<host>.nix declares the dataset with
  # mountpoint = "/srv/the-hive").

  # .envrc is trusted for both accounts without `direnv allow`: only the two
  # hive members can write it and it is pinned by content hash anyway.
  # Here and not in home-manager: the NixOS direnv module (common/base.nix)
  # sets DIRENV_CONFIG=/etc/direnv, so only its settings are ever read.
  programs.direnv.settings.whitelist.prefix = ["/srv/the-hive"];

  systemd.tmpfiles.rules = [
    # `z`, not `d`: adjust the mountpoint's owner/mode, never create a dir
    # that would then block `git clone` into it.
    "z /srv/the-hive 0750 ${host.userName} hive -"
    # One recursive ACL for the whole checkout (.git/ included, so either
    # account can commit). Named-group entries so the files' own group
    # (users, from the cloning account) does not matter. Before the clone the
    # line is a no-op with a warning. This also covers .ren/ (rensa's direnv
    # layout, written on every cd by whichever account) which used to need
    # its own rule (2026-09-15).
    "A+ /srv/the-hive - - - - d:group:hive:rwx,group:hive:rwx"
  ];
}
