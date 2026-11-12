# elster-only: docker. Split out when a second host
# wants any of it.
{
  inputs,
  cell,
}: {
  config,
  lib,
  ...
}: {
  virtualisation.docker = {
    enable = true;
    # /var/lib/docker is a legacy-mounted ZFS dataset; overlay2 on top of it
    # works. The `zfs` storage driver would want to manage datasets itself.
    storageDriver = "overlay2";
    # Nothing runs at boot on a laptop; the socket starts the daemon on demand.
    enableOnBoot = false;
    autoPrune.enable = true;
  };
  # dialout: flash and talk to the bench MCUs (/dev/ttyACM*, root:dialout)
  # without sudo; under sudo nix runs as root, which lacks safe.directory.
  # docker: the rootful socket, i.e. root without sudo -- admin only.
  users.users = lib.mkMerge [
    (lib.genAttrs config.hive.localUsers (_: {extraGroups = ["dialout"];}))
    (lib.genAttrs config.hive.roleHolders.admin (_: {extraGroups = ["docker"];}))
  ];
  # The Entra account: himmelblau reconciles group membership on login
  # (local_groups_reconcile_interval), same path as `hive`/`networkmanager`
  # in auth-entra.nix.
  services.himmelblau.settings.local_groups = ["dialout"];
}
