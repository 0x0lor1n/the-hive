# dev: code + agents. Rootless docker: `docker` group membership is root. No
# ports < 1024, --net=host or --privileged.
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
