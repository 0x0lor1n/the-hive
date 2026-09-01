# Two-root impermanence configuration: /state (ephemeral runtime state
# — logs, machine-id, nixos db; not backed up) and /persist (kept-forever
# identity — ssh host keys, secrets; backed up later).
#
# UNIVERSAL ONLY. Everything here is true of any installed host regardless
# of filesystem, desktop or auth stack, which is what lets `suites.foundation`
# include it for both the workstations and the headless server (iter 11).
#
# Per-service state lives with the service that owns it, NOT here:
#   /var/lib/sbctl                    -> hardware-secureboot.nix
#   /var/lib,cache/himmelblaud        -> auth-entra.nix
#   the local user's home carve-outs  -> layer-users-local.nix
#
# That split is not tidiness. The himmelblau entries name
# `user = "himmelblaud"`, which does not exist on a host without
# auth-entra; a headless server importing this file would have failed on
# an account it never creates.
#
# Filesystem-agnostic: /state and /persist are mountpoints, whether they
# come from ZFS datasets (rpool/local/state, rpool/safe/persist) or btrfs
# subvolumes (@state, @persist). This file does not care which.
{
  inputs,
  cell,
}: {...}: {
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  # Required by impermanence (asserted at eval time) — neither disko's
  # fileSystems.* entries nor a hand-written btrfs mount set this itself.
  fileSystems."/state".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;

  # Runtime state that should survive reboots but isn't worth backing
  # up; recreatable on reinstall.
  environment.persistence."/state" = {
    hideMounts = true;

    files = [
      "/etc/machine-id"
    ];

    directories = [
      "/var/log"
      "/var/lib/nixos" # UID/GID allocations
      "/var/lib/systemd" # systemd state (random-seed, timers, etc.)
      "/var/spool"
    ];
  };

  # Identity that must outlive reinstalls. The SSH host keys in particular
  # are load-bearing twice over: they are the agenix-rekey recipient
  # (secrets.nix), and losing them makes every client warn on reconnect.
  environment.persistence."/persist" = {
    hideMounts = true;

    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
