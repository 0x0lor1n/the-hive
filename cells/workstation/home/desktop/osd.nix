# Starts via its own HM-managed user systemd unit — do not also start
# from the DWL startup script, that would race. XF86 volume/brightness
# keys are wired in layer-compositor.nix's dwl-custom postPatch but are
# inert in the VM (no real keyboard to send them).
{pkgs, ...}: {
  services.avizo = {
    enable = true;
  };
}
