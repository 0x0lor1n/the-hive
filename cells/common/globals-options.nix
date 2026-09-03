# Schema for `globals`. Public; values come from globals.nix (public half) and
# secrets/globals.nix.age (encrypted half), merged by globals.nix.
{lib, ...}: {
  options.globals = lib.mkOption {
    description = "Repo-wide parameters, merged from public and encrypted halves.";
    type = lib.types.submodule {
      options = {
        # Encrypted half (name/homeDir/hashedPassword). Read by cells/workstation:
        # disks pre-create the home inside the @blank snapshot.
        user = {
          name = lib.mkOption {type = lib.types.str;};
          homeDir = lib.mkOption {type = lib.types.str;};
          hashedPassword = lib.mkOption {type = lib.types.str;};
          uid = lib.mkOption {
            type = lib.types.int;
            default = 1000;
          };
        };
        entra = {
          domains = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
          };
          # Entra account whose home gets impermanence carve-outs
          # (auth-entra.nix). uid = himmelblau idmap value, stable per
          # tenant+object, so hardcoded.
          user.upn = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          user.uid = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
          };
        };

        # Encrypted half. Fleet default; hosts.<h>.rootHashedPassword overrides.
        # A plain string rather than a file so console login survives an agenix
        # outage.
        root.hashedPassword = lib.mkOption {type = lib.types.str;};

        # nullOr, not str: nixpkgs' acme module passes --email only when
        # non-null; an empty string reaches lego and is rejected.
        acme.email = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        hosts = lib.mkOption {
          default = {};
          type = lib.types.attrsOf (
            lib.types.submodule (
              {name, ...}: {
                options = {
                  hostName = lib.mkOption {
                    type = lib.types.str;
                    default = name;
                  };

                  # Encrypted half. Read by net-osgiliath.nix and
                  # deploy-osgiliath.nix so the address lives in one place.
                  ipv4 = lib.mkOption {
                    default = null;
                    type = lib.types.nullOr (
                      lib.types.submodule {
                        options = {
                          address = lib.mkOption {
                            type = lib.types.str;
                            description = "With prefix length, e.g. 10.0.0.2/24.";
                          };
                          gateway = lib.mkOption {type = lib.types.str;};
                        };
                      }
                    );
                  };

                  # nixos-anywhere has no --disk override for --store-paths, so
                  # this is the real device. Never /dev/sda on osgiliath: that is
                  # the provider's config drive.
                  diskDevice = lib.mkOption {type = lib.types.str;};

                  # Workstation axes (cells/workstation). Server hosts keep the
                  # defaults.
                  isVm = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "QEMU guest: forces the ZFS import, no autoScrub.";
                  };
                  hasTpm = lib.mkOption {
                    type = lib.types.nullOr lib.types.bool;
                    default = null;
                    description = "TPM 2.0 present (swtpm counts). null = unknown.";
                  };

                  # Per-host local user. null falls back to the encrypted
                  # globals.user.*; the playground VMs carry a public throwaway
                  # identity so nothing secret is needed to boot them.
                  userName = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                  };
                  homeDir = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                  };
                  hashedPassword = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                  };

                  # Encrypted half. layer-server-hardening.nix asserts this is
                  # set: an internet-facing host must not inherit the fleet
                  # default.
                  rootHashedPassword = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                  };

                  # agenix-rekey recipient (cells/workstation/profiles/secrets.nix).
                  # null = not captured yet: the host boots on the pool's disko
                  # key and decrypts nothing. Capture with
                  # `ssh-keyscan -t ed25519 <host>`, set, `agenix rekey`.
                  sshHostPubkey = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                  };
                };
              }
            )
          );
        };

        persistence = {
          statePath = lib.mkOption {type = lib.types.str;};
          dataPath = lib.mkOption {type = lib.types.str;};
        };
      };
    };
  };
}
