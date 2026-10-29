{
  inputs,
  cell,
  ...
}: let
  inherit (inputs) pkgs;
in {
  # Stock inteltool refuses `-G` on the 200-series mobile PCHs (CM238 here).
  inteltool = pkgs.inteltool.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./patches/inteltool-cm238-gpio.patch];
  });
}
