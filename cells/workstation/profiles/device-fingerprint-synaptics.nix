# Fingerprint (Synaptics 06cb:00f0, libfprint's open `synaptics` driver).
# Wired into sudo and su only: pam_fprintd goes first and blocks the
# password prompt until the reader times out, which is fine at a `sudo`/`su`
# line but painful on greetd/swaylock. su is setuid root, so fprintd lets it
# verify the *target* account's prints -- that is what makes `su - <admin>`
# from the Entra session work. NixOS defaults fprintAuth to fprintd.enable
# for every PAM service, so every other service on this host is opted back
# out explicitly (sshd included: keyboard-interactive would otherwise wait
# on the reader). Enrol once per finger: `fprintd-enroll`.
{
  inputs,
  cell,
}: {lib, ...}: {
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

  environment.persistence."/persist".directories = ["/var/lib/fprint"];
}
