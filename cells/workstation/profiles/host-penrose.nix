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
  boot.kernelParams = ["intel_iommu=on" "i915.enable_dp_mst=0"];

  # libgfxinit lights the dock's DP at the sink's 10 bpc; an 8-bpc compositor
  # would full-modeset it (dark gap) at greeter start and again at login.
  session.render10bpc = true;

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
