# Initrd service that rolls rpool/local/root back to its @blank
# snapshot before /sysroot mounts — this is what makes root ephemeral.
# Boot-time (not shutdown-time) so the system reaches a known state
# regardless of how the previous run ended; environment.persistence
# layers the carve-outs (.ssh, host keys, etc.) back in afterward.
{
  config,
  lib,
  ...
}: {
  boot.initrd.systemd.services.impermanence-root = {
    description = "Rollback rpool/local/root to @blank";
    wantedBy = ["initrd.target"];
    after = ["zfs-import-rpool.service"];
    before = ["sysroot.mount"];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe config.boot.zfs.package} rollback -r rpool/local/root@blank";
    };
  };
}
