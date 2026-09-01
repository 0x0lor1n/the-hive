# Type schema for `globals`. Public and committed on purpose: this file
# declares the SHAPE, `secrets/globals.nix.age` supplies the sensitive
# VALUES, and globals.nix merges the two. Adapted from oddlama's
# modules/globals.nix (mkOption + submodule, attrsOf submodule for
# repeated entities, readOnly for derived values).
#
# NOT WIRED YET — nothing imports this. See .sisyphus/plans/iteration-10.md.
{lib, ...}: {
  options.globals = lib.mkOption {
    description = "Repo-wide parameters, merged from public and encrypted halves.";
    type = lib.types.submodule {
      options = {
        # ---------------------------------------------------------------
        # FIRST user: the local unix account. `name` and `homeDir` come
        # from the ENCRYPTED half (homeDir embeds the name, so it cannot
        # stay public without leaking it). `uid`/`shell` are not
        # identifying and stay public.
        #
        # NOTE: this block cannot be keyed by username the way oddlama does
        # it (`malte.hashedPassword`) — an attribute name lives in the
        # public schema, which would defeat the point. Generic `user.*` is
        # now forced, which happens to match ~/nixos-config's `myuser`.
        # ---------------------------------------------------------------
        user = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Unix username of the local user. From the encrypted half.";
          };
          homeDir = lib.mkOption {
            type = lib.types.str;
            description = "Local user's home directory. From the encrypted half.";
          };
          uid = lib.mkOption {
            type = lib.types.int;
            description = "Local user's uid. Baked into the disko home snapshot.";
          };
          shell = lib.mkOption {
            type = lib.types.str;
            description = "Local user's login shell.";
          };

          # ENCRYPTED. Default hash for every host that does not override
          # it below. Playground hosts override in the public half so the
          # VM keeps a known, documented password.
          hashedPassword = lib.mkOption {
            type = lib.types.str;
            description = "yescrypt hash for the local user. From the encrypted half.";
          };
        };

        # ENCRYPTED. Kept a plain string, not a file: layer-users-root.nix sets
        # `hashedPassword` (not `...File`) for root deliberately, so a
        # console login stays available if agenix or the pool misbehaves.
        root.hashedPassword = lib.mkOption {
          type = lib.types.str;
          description = "yescrypt hash for root. From the encrypted half.";
        };

        # ---------------------------------------------------------------
        # Entra / Intune, and the SECOND user: the tenant identity that
        # himmelblau authenticates. It is NOT a `users.users` entry —
        # himmelblau creates it at login, so nothing here declares an
        # account, only the facts about it.
        #
        # auth-entra.nix reads `domain = globals.entra.domains` as of iter
        # 11.6, so the tenant domain now lives in the encrypted half.
        # ---------------------------------------------------------------
        entra = {
          domains = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Entra domains permitted to log in (himmelblau `domain`).";
          };
          tenantId = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Entra tenant GUID, if a consumer ever needs it at eval time.";
          };

          user = {
            # NO eval-time consumer, deliberately. himmelblaud_tasks skips
            # chown on an already-existing home (tasks_daemon.rs guards the
            # whole umask/create_dir_all/chown/skel block behind
            # `if !hd_path.exists()`), so the persistence design mounts a
            # dataset at the home PARENT and lets himmelblau create the leaf
            # itself with correct ownership. Nothing needs the upn at eval
            # time as a result — see iteration-10 §4.
            #
            # Kept here anyway as the recorded second identity, for future
            # consumers (group filters, Intune scripts, git identity). It is
            # documentation, not a build input: if that stays true, KeePass
            # is an equally good home for it.
            upn = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Entra UPN, e.g. user@example.com. From the encrypted half.";
            };
            displayName = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Human-readable name, if a consumer needs it.";
            };
          };
        };

        # PUBLIC, deliberately. The ACME contact is transmitted to Let's
        # Encrypt at registration, which normally makes it encrypted-half
        # material -- but the address used here is the SAME pseudonymous
        # GitHub noreply address that appears in the author field of every
        # commit in this repo. Encrypting a value that is already in 182
        # commit objects would be theatre, the same argument that decided the
        # IP could not be half-encrypted (iteration 11.6).
        #
        # nullOr, not str: nixpkgs' acme module treats null as "register with
        # no contact" and only passes --email when non-null
        # (nixos/modules/security/acme/default.nix:289). An EMPTY STRING is
        # worse than null -- it is non-null, so lego receives `--email ""` and
        # rejects it.
        acme.email = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "ACME contact address, or null to register without one.";
        };

        # ---------------------------------------------------------------
        # Per-host facts. Hardware traits stay public; only the by-id disk
        # path is sensitive (it carries the drive serial).
        # ---------------------------------------------------------------
        hosts = lib.mkOption {
          description = "Per-host parameters, keyed by nixosConfigurations target name.";
          default = {};
          type = lib.types.attrsOf (
            lib.types.submodule (
              {
                name,
                config,
                ...
              }: {
                options = {
                  hostName = lib.mkOption {
                    type = lib.types.str;
                    default = name;
                    description = "networking.hostName. Defaults to the attribute name.";
                  };
                  isVm = lib.mkOption {
                    type = lib.types.bool;
                    description = ''
                      True for KVM/QEMU guests. Consumed by storage-zfs.nix to decide
                      forceImportRoot/zfs_force, which is about the disko image builder.
                      This is NOT a statement about disposability -- see isPlayground.
                    '';
                  };

                  isPlayground = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = ''
                      True for DISPOSABLE hosts, which take secrets.nix's fixed,
                      known, plaintext-in-the-repo generator values instead of
                      generated entropy.

                      Defaults to false so a new host is production unless it says
                      otherwise: the opposite default would hand a real machine the
                      repo's published dev credentials, which is exactly what the
                      old `isPlayground = host.isVm` rule did to osgiliath (a VM
                      with a public IP). Fail closed.
                    '';
                  };

                  headless = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = ''
                      No display and no local unix user; takes suites.server rather
                      than suites.workstation. Recorded so the host table is
                      self-describing -- the suite choice itself is made in
                      nixosConfigurations.nix.
                    '';
                  };

                  # ENCRYPTED. IP addresses are treated as sensitive in this
                  # repo (operator instruction, iter 11), so the values live in
                  # secrets/globals.nix.age and only the SHAPE is public here.
                  #
                  # Read by profiles/net-osgiliath.nix and by
                  # colmenaConfigurations.nix, so an address exists in exactly
                  # one place. nullOr because only routed hosts have one;
                  # the playground VMs are NAT'd by QEMU and need nothing.
                  ipv4 = lib.mkOption {
                    default = null;
                    description = "Static IPv4 configuration, or null for DHCP/NAT.";
                    type = lib.types.nullOr (
                      lib.types.submodule {
                        options = {
                          address = lib.mkOption {
                            type = lib.types.str;
                            description = "Address WITH prefix length, e.g. 10.0.0.2/24.";
                          };
                          gateway = lib.mkOption {
                            type = lib.types.str;
                            description = "Default gateway.";
                          };
                        };
                      }
                    );
                  };
                  gpu = lib.mkOption {
                    type = lib.types.enum [
                      "virtio"
                      "intel"
                      # Headless. osgiliath is a KVM VPS with no display
                      # device at all, so it selects no gpu-* device file.
                      "none"
                    ];
                    description = "GPU family, selecting a devices/ profile.";
                  };
                  hasTpm = lib.mkOption {
                    type = lib.types.nullOr lib.types.bool;
                    default = null;
                    description = "null means UNVERIFIED on real hardware — check /dev/tpmrm0.";
                  };
                  isLaptop = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Enables lid/battery handling.";
                  };

                  # Derived, so a host cannot silently disagree with
                  # storage-zfs.nix:18. readOnly documents that this is
                  # computed, not configured.
                  hostId = lib.mkOption {
                    type = lib.types.str;
                    readOnly = true;
                    default = lib.substring 0 8 (builtins.hashString "sha256" config.hostName);
                    description = "ZFS hostId, derived from hostName. Do not set.";
                  };

                  # PUBLIC, and for real hardware it stays REPLACE-ME
                  # forever. disko-install/nixos-anywhere REQUIRE the device
                  # on the command line (`--disk <name> <dev>`) and replace
                  # this value by attrset override in install-cli.nix, so
                  # the real serial never has to enter the repo in any form.
                  #
                  # Leaving the sentinel in place keeps
                  # diskoConfigurations.nix's checkedDevice permanently
                  # armed against a plain `disko --mode destroy --flake`,
                  # which has no --disk flag and would read this value.
                  #
                  # VMs are the exception: `just image` builds a loop-backed
                  # image, so they carry a real /dev/vda here.
                  diskDevice = lib.mkOption {
                    type = lib.types.str;
                    default = "/dev/disk/by-id/REPLACE-ME-BEFORE-INSTALL";
                    description = "Install target. Real hardware keeps the sentinel; pass --disk instead.";
                  };

                  # ENCRYPTED. Per-host root password, overriding the
                  # fleet-wide mkDefault in layer-users-root.nix.
                  #
                  # osgiliath needs this because the fleet default is
                  # published in git with its plaintext beside it, which must
                  # not sit on a machine with a public IP. It is the console
                  # recovery path (root SSH is key-only), so it cannot simply
                  # be omitted.
                  rootHashedPassword = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Overrides root.hashedPassword for this host. null = inherit the fleet default.";
                  };

                  # Optional per-host password override. Lets the VM keep
                  # its documented throwaway in the public half while real
                  # hardware inherits the encrypted user.hashedPassword.
                  hashedPassword = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Overrides user.hashedPassword for this host. null = inherit.";
                  };

                  # Same idea for the username itself. The justfile SSHes as
                  # the local user and cannot read encrypted globals, so the
                  # playground hosts carry a PUBLIC username here while real
                  # hardware inherits the encrypted user.name.
                  #
                  # globals.nix resolves this: after evaluation every host
                  # gets a non-null userName and a matching homeDir, so
                  # consumers read host.userName / host.homeDir and never
                  # have to re-implement the fallback.
                  userName = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Overrides user.name for this host. null = inherit.";
                  };

                  # Derived by globals.nix from userName (or inherited whole
                  # from user.homeDir). Never set this directly -- a home
                  # path that disagrees with the username silently produces a
                  # user whose home was never created in the @blank snapshot.
                  homeDir = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Resolved by globals.nix. Do not set.";
                  };
                };
              }
            )
          );
        };

        persistence = {
          statePath = lib.mkOption {
            type = lib.types.str;
            description = "Ephemeral-but-surviving state root.";
          };
          dataPath = lib.mkOption {
            type = lib.types.str;
            description = "Kept-forever data root.";
          };
        };

        # Declared now, empty until a network profile exists. oddlama keeps
        # MACs encrypted because they identify hardware on a LAN.
        macs = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Hardware MAC addresses, keyed by interface label.";
        };
      };
    };
  };
}
