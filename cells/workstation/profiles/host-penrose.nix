# penrose-only. The machine is on or off, never asleep (coreboot advertises
# only S0/S5). elster keeps the default sleep: its Intune compliance wants it.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  # Run one program on the M620 (nouveau, Mesa PRIME). Same name as nixpkgs'
  # prime.offload.enableOffloadCmd, which replaces it with the nvidia driver.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "nvidia-offload" ''
      export DRI_PRIME=pci-0000_01_00_0
      exec "$@"
    '')
  ];

  services.logind.settings.Login = {
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
  };

  # Also refuses the shared swayidle `systemctl suspend` (home/desktop/idle.nix).
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
}
