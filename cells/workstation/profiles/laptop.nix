# Laptop shape: radios, lid, and the things a VM or a VPS never has.
# No battery tuning: penrose has no battery installed (dmidecode type 22
# empty, no BAT0).
#
# NetworkManager rather than iwd; wpa_supplicant is NM's default backend.
{
  inputs,
  cell,
}: {
  lib,
  pkgs,
  host,
  globals,
  ...
}: {
  # The machine lives in Geneva; base.nix's UTC is a mkDefault for servers.
  time.timeZone = "Europe/Zurich";

  networking.networkmanager.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  # Lid: with no battery the machine lives on AC; closing the lid should not
  # suspend a box that may be running builds over ssh.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };

  # Printing: CUPS, driverless (IPP Everywhere). avahi + nssmdns4 lets
  # printers that announce over mDNS show up in CUPS without knowing an IP.
  services.printing = {
    enable = true;
    drivers = [pkgs.cups-filters];
  };
  # The office HP (static IP set on the device; mDNS is filtered on the office
  # Wi-Fi) so declare it by IP. Address lives in the encrypted globals half,
  # not this public file. Driverless via IPP Everywhere.
  hardware.printers = lib.mkIf (globals.office.printer.address != null) {
    ensureDefaultPrinter = "work-hp";
    ensurePrinters = [
      {
        name = "work-hp";
        description = "Office HP LaserJet MFP";
        location = "Office";
        deviceUri = "ipp://${globals.office.printer.address}/ipp/print";
        model = "everywhere";
        ppdOptions = {
          PageSize = "A4";
          Duplex = "DuplexNoTumble";
        };
      }
    ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  # `lp` group: add/remove printers and use the CUPS web UI without root.
  users.users.${host.userName}.extraGroups = ["networkmanager" "lp"];

  # Fingerprint (Synaptics 06cb:00f0, libfprint's open `synaptics` driver).
  # Wired into sudo and su only: pam_fprintd goes first and blocks the
  # password prompt until the reader times out, which is fine at a `sudo`/`su`
  # line but painful on greetd/swaylock. su is setuid root, so fprintd lets it
  # verify the *target* account's prints -- that is what makes `su - <admin>`
  # from the Entra session work. NixOS defaults fprintAuth to fprintd.enable
  # for every PAM service, so every other service on this host is opted back
  # out explicitly (sshd included: keyboard-interactive would otherwise wait
  # on the reader). Enrol once per finger: `fprintd-enroll`.
  services.fprintd.enable = true;
  security.pam.services =
    lib.genAttrs [
      "login"
      "greetd"
      "swaylock"
      "polkit-1"
      "sshd"
      "systemd-user"
      "systemd-run0"
      "runuser"
      "runuser-l"
      "passwd"
      "chpasswd"
      "chsh"
      "chfn"
      "cups"
      "other"
    ]
    (_: {fprintAuth = false;})
    // {
      sudo.fprintAuth = true;
      su.fprintAuth = true;
    };
  # The admin account has no logind session of its own (it runs inside the
  # Entra user's seat), so fprintd's default policy (active session only)
  # refuses enroll/verify. Let wheel manage its own prints from anywhere.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id.indexOf("net.reactivated.fprint.device.") == 0 &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  # NM state, pairing, printers, and enrolled fingerprints survive the @blank
  # rollback.
  environment.persistence."/persist".directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/bluetooth"
    "/var/lib/cups"
    "/var/lib/fprint"
  ];
}
