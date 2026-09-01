{
  # SPIKE C: this input is deliberately UNFETCHABLE (the rev does not exist).
  # It stands in for cells/workstation's lanzaboote / nix-cachyos-kernel /
  # himmelblau -- inputs that osgiliath must never pay for.
  #
  # If evaluating the `probe` cell succeeds while this exists, cell-flake
  # laziness is real. If it fails, kill criterion 2 fires.
  inputs.unfetchable.url = "github:nix-community/impermanence/0000000000000000000000000000000000000000";

  outputs = i: i // { heavyThing = i.unfetchable.outPath; };
}
