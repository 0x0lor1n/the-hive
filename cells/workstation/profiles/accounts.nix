# Who logs into this host and what each account is for. Role profiles
# (role-*.nix) and secrets.nix read `hive.roleHolders` instead of naming an
# account, so a key or tunnel follows the role, not the login method.
#
# Roles: admin (rebuilds the host, wheel), dev (code + agents), freelance and
# employer (that organisation's keys and tunnels). `auth` is how the account
# exists: "local" is in users.users, "entra" is an NSS user from himmelblau
# (auth-entra.nix) with no users.users entry, so it is owned by numeric uid.
#
# The list is fixed here until globals carries per-host accounts; the roles
# match the ones layer-compositor.nix hands each home.
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
  };

  config = {
    hive.accounts =
      [
        {
          name = host.userName;
          auth = "local";
          owner = host.userName;
          roles = ["admin" "dev"];
        }
      ]
      ++ lib.optional (entra.upn != null && entra.uid != null) {
        name = lib.head (lib.splitString "@" entra.upn);
        auth = "entra";
        owner = toString entra.uid;
        roles = ["dev" "freelance" "employer"];
      };

    hive.roleHolders = lib.genAttrs roles (r: map (a: a.owner) (holders r));

    assertions = [
      {
        # sudo, the checkout and the PIN identity for eval-time secrets all
        # hang off one users.users entry (role-admin.nix).
        assertion = lib.length (holders "admin") == 1 && (lib.head (holders "admin")).auth == "local";
        message = "accounts: exactly one account must hold admin, and it must be local (auth = \"local\").";
      }
    ];
  };
}
