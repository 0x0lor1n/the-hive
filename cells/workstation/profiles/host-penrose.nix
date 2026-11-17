# penrose-only. The machine is on or off, never asleep (coreboot advertises
# only S0/S5). elster keeps the default sleep: its Intune compliance wants it.
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  ...
}: {
  # The firmware leaves TB3 at SL1; the dock is authorised by device-dock-wd19tbs.nix.
  # Authorisation only gates the tunnel; an authorised device still DMAs
  # anywhere without VT-d. The coreboot DMAR has no opt-in flag, so it stays
  # off by default.
  # i915 MST on KBL blanks the WD19TBS's 4K60 output every 15-30 s; SST is clean
  # (same on stock BIOS). Costs the dock's second display output.
  # A cold boot with the LG lit on the dock stops the kernel in a pipe B
  # underrun flood (3 of 3). Trial: DP-1 is forced off on the cmdline and
  # re-probed once the greeter is up; a hot-plug there lights it cleanly.
  boot.kernelParams = ["intel_iommu=on" "i915.enable_dp_mst=0" "video=DP-1:d"];

  # By PCI address: the iGPU's card number follows probe order with nvidia.
  # No match leaves the glob literal and the unit fails.
  systemd.services.dock-dp-detect = {
    description = "Re-probe the dock's DP output forced off at boot";
    wantedBy = ["graphical.target"];
    after = ["graphical.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      for s in /sys/bus/pci/devices/0000:00:02.0/drm/card*/card*-DP-1/status; do
        echo detect > "$s"
      done
    '';
  };

  # Boot default only; the powermenu still flips it (cpu-governor.nix).
  powerManagement.cpuFreqGovernor = "performance";

  services.logind.settings.Login = {
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
  };

  # No Intune here, so no idle lock either; swayidle only blanks the screen.
  session.idleLock = false;

  # Own PK/KEK/db only. Nothing here runs an option ROM: libgfxinit drives the
  # iGPU, the M620 has no ROM chip, the I219 has no oprom.
  boot.lanzaboote.autoEnrollKeys = {
    includeMicrosoftKeys = false;
    allowBrickingMyMachine = true;
  };
  # edk2 measures SB state and these keys into PCR 7; SB off or a foreign key
  # then asks for the passphrase.
  zfsUnlock.pcrIds = "7,15";
  # sbctl create-keys takes the cert CN from keys.*.description.
  environment.etc."sbctl/sbctl.conf".source = let
    dir = config.boot.lanzaboote.pkiBundle;
    key = name: description: {
      privkey = "${dir}/keys/${name}/${name}.key";
      pubkey = "${dir}/keys/${name}/${name}.pem";
      type = "file";
      inherit description;
    };
  in
    lib.mkForce ((pkgs.formats.yaml {}).generate "sbctl.conf" {
      keydir = "${dir}/keys";
      guid = "${dir}/GUID";
      keys = {
        pk = key "PK" "penrose.the-hive Platform Key";
        kek = key "KEK" "penrose.the-hive Key Exchange Key";
        db = key "db" "penrose.the-hive Signature Database Key";
      };
    });

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
}
