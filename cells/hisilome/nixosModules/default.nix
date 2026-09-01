# The Zola site and the radio station as a NixOS module. Host-agnostic; the
# consumer sets domain, secrets and firewall.
#
# radio.liq and the scripts address everything relative to the working
# directory (`radio/state/...`, `music`, `public`); the module reproduces that
# shape under stateDir and runs every unit with WorkingDirectory there.
{
  inputs,
  cell,
  ...
}: let
  args = {inherit inputs cell;};
in {
  default = {
    config,
    lib,
    ...
  }: let
    cfg = config.services.hisilome;
    inherit (lib) mkOption mkEnableOption mkIf types;
  in {
    imports = [
      (import ./setup.nix args)
      (import ./station.nix args)
      (import ./nginx.nix args)
    ];

    options.services.hisilome = {
      enable = mkEnableOption "the Hísilómë site and radio station";

      domain = mkOption {
        type = types.str;
        example = "hisilo.me";
      };

      enableACME = mkOption {
        type = types.bool;
        default = true;
      };

      stateDir = mkOption {
        type = types.path;
        default = "/var/lib/hisilome";
        description = ''
          Holds the library and the queue. On an impermanent host point this
          inside the persistent volume; the paths are used directly, not
          bind-mounted.
        '';
      };

      site = mkOption {
        type = types.package;
        default = cell.packages.site;
        defaultText = "cell.packages.site";
      };

      user = mkOption {
        type = types.str;
        default = "hisilome";
      };
      group = mkOption {
        type = types.str;
        default = "hisilome";
      };

      sourcePasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Read at unit start, never copied into the store. null keeps
          icecast.xml's committed dev value; safe only because icecast binds
          127.0.0.1.
        '';
      };

      adminPasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
      };

      queueRounds = mkOption {
        type = types.int;
        default = 8;
        description = "Shuffled passes concatenated into the play queue.";
      };
    };

    config = mkIf cfg.enable {
      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        description = "Hísilómë radio";
      };
      users.groups.${cfg.group} = {};
    };
  };
}
