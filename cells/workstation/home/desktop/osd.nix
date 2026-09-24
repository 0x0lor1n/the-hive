# Starts via its own HM-managed user systemd unit — do not also start
# from the DWL startup script, that would race. XF86 volume/brightness
# keys are wired in layer-compositor.nix's dwl-custom postPatch but are
# inert in the VM (no real keyboard to send them).
{
  lib,
  theme,
  ...
}: let
  r = theme.roles;
  # avizo's ini is parsed per call by Gdk.RGBA; an unparsable value error()s
  # and the OSD never shows.
  rgba = c: a: let
    ch = i: toString (lib.fromHexString (builtins.substring i 2 c));
  in "rgba(${ch 0}, ${ch 2}, ${ch 4}, ${a})";
in {
  services.avizo = {
    enable = true;
    # Icons are fixed PNGs (black, or grey with volumectl/lightctl -d), so
    # the callers pass -d: the black set is invisible on this bg.
    settings.default = {
      background = rgba r.bg "0.95";
      border-color = rgba r.focus "1.0";
      bar-fg-color = rgba r.fg "1.0";
      bar-bg-color = rgba r.bgAlt "1.0";
    };
  };
}
