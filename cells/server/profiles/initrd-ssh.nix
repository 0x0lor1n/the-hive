# TPM-unseal fallback, LAN bridge only: initrd has no firewall. Own key on 2222
# (ssh alias minas-tirith-initrd); unlock with systemd-tty-ask-password-agent.
{
  inputs,
  cell,
}: {
  config,
  site,
  ...
}: let
  br = config.router.lanBridge;
in {
  boot.initrd.availableKernelModules = ["igc" "bridge"];

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      # Copied in clear to the ESP at install, so it must exist before (--extra-files).
      hostKeys = ["/persist/etc/ssh/initrd_ssh_host_ed25519_key"];
      authorizedKeyFiles = config.router.adminKeyFiles;
    };
  };

  boot.initrd.systemd.network = {
    netdevs."15-br-lan" = config.systemd.network.netdevs."15-br-lan";
    networks."20-lan-ports" = {
      matchConfig.Name = config.router.ports.lan;
      networkConfig.Bridge = br;
    };
    networks."30-lan" = {
      matchConfig.Name = br;
      address = ["192.168.10.1/24"];
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };
}
