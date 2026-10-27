# dev: the account that writes code and runs the agents (home side:
# home/roles/dev.nix). System side is rootless docker: the work projects
# need a daemon, and the rootful one is root with no human in the chain
# (`docker run -v /:/host` from any member of `docker`,
# accounts-as-roles baseline p.1). rootless runs dockerd in the account's
# own user namespace: the daemon, every container and the socket are the
# account itself, and host root stays with admin's rootful daemon.
#
# What rootless cannot do, and is accepted: ports < 1024 (sysctl
# ip_unprivileged_port_start), `--net=host` without privileges, no
# `--privileged` access to host devices, no overlay2 on a ZFS home without
# fuse-overlayfs (moby picks that up from PATH). Images do not carry over
# from the rootful /var/lib/docker: `docker save | docker load` the few
# that matter, pull the rest.
{
  lib,
  config,
  globals,
  ...
}: let
  devs = lib.filter (a: lib.elem "dev" a.roles) config.hive.accounts;
in
  lib.mkIf (devs != []) {
    virtualisation.docker.rootless = {
      enable = true;
      # DOCKER_HOST for the dev role only: home/roles/dev.nix. The module's
      # extraInit would point every login, admin included, at a socket that
      # is not there for it.
      setSocketVariable = false;
    };

    # The nixpkgs unit is wantedBy default.target for every user manager, with
    # only `!root` as condition. Add the dev holders: a `|` condition line is
    # an OR group that must hold alongside the plain ones, so admin's manager
    # skips the unit instead of failing it every login.
    systemd.user.services.docker.unitConfig.ConditionUser =
      map (a: "|${a.owner}") devs;

    # The daemon's data-root is ~/.local/share/docker, on the rolled-back root
    # for a local account and under the himmelblau-recreated home for an
    # Entra one. Images and volumes survive the reboot the same way the rest
    # of the home does (layer-users-local.nix, auth-entra.nix). An Entra home
    # is /home/<upn>, not the /home/<cn> alias: himmelblau makes that symlink
    # at login, and a bind mount through it at boot would leave a real
    # directory in its place.
    environment.persistence."/persist" = lib.mkMerge (map (a:
      if a.auth == "local"
      then {users.${a.name}.directories = [".local/share/docker"];}
      else {
        directories = [
          {
            directory = "/home/${globals.entra.user.upn}/.local/share/docker";
            user = a.owner;
            group = a.owner;
            mode = "0700";
          }
        ];
      })
    devs);
  }
