# Accounts and their roles; consumers read `hive.roleHolders`, so keys and
# tunnels follow the role, not the login.
{
  lib,
  config,
  host,
  globals,
  ...
}: let
  roles = ["admin" "dev" "freelance" "employer"];
  entra = globals.entra.user;
  account = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Login name (the cn for an Entra account).";
      };
      auth = lib.mkOption {type = lib.types.enum ["local" "entra"];};
      # What chown and systemd's User= take: the name for a local account,
      # the uid for an Entra one (nothing resolves its name at activation).
      owner = lib.mkOption {type = lib.types.str;};
      roles = lib.mkOption {type = lib.types.listOf (lib.types.enum roles);};
      home = lib.mkOption {type = lib.types.str;};
      # Gets the dwl session and home/desktop: any role but admin.
      desktop = lib.mkOption {type = lib.types.bool;};
    };
  };
  holders = role: lib.filter (a: lib.elem role a.roles) config.hive.accounts;
in {
  options.hive = {
    accounts = lib.mkOption {
      type = lib.types.listOf account;
      description = "Accounts on this host. Order matters: the first holder of a shared role owns its secrets.";
    };
    roleHolders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      readOnly = true;
      description = "role -> owners (account.owner) of the accounts holding it, in account order.";
    };
    localUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Names of the auth = local accounts, i.e. the ones in users.users.";
    };
  };

  config = {
    hive.accounts = map (a: let
      named =
        if a.auth == "local"
        then {
          name = host.userName;
          owner = host.userName;
          home = host.homeDir;
        }
        else let
          cn = lib.head (lib.splitString "@" entra.upn);
        in {
          name = cn;
          owner = toString entra.uid;
          # The home_alias himmelblau creates (auth-entra.nix).
          home = "/home/${cn}";
        };
    in
      named
      // {
        inherit (a) auth roles;
        desktop = lib.subtractLists ["admin"] a.roles != [];
      })
    host.accounts;

    hive.roleHolders = lib.genAttrs roles (r: map (a: a.owner) (holders r));
    hive.localUsers = map (a: a.name) (lib.filter (a: a.auth == "local") config.hive.accounts);

    assertions = [
      {
        # One name per auth in globals (host.userName, entra.user).
        assertion = lib.all (auth: lib.length (lib.filter (a: a.auth == auth) host.accounts) <= 1) ["local" "entra"];
        message = "accounts: at most one local and one entra account per host.";
      }
      {
        assertion = lib.any (a: a.auth == "entra") host.accounts -> (entra.upn != null && entra.uid != null);
        message = "accounts: an entra account needs globals.entra.user.{upn,uid}.";
      }
      {
        # sudo, the checkout and the PIN identity for eval-time secrets all
        # hang off one users.users entry (role-admin.nix).
        assertion = lib.length (holders "admin") == 1 && (lib.head (holders "admin")).auth == "local";
        message = "accounts: exactly one account must hold admin, and it must be local (auth = \"local\").";
      }
    ];
  };
}
