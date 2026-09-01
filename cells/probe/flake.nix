{
  # A cell flake WITH an input, so this also exercises call-flake's own
  # evaluation path rather than the trivial no-flake case.
  inputs.impermanence.url = "github:nix-community/impermanence";

  outputs = i:
    i
    // {
      # proves the cell flake's own inputs resolved
      impermanenceOk = i.impermanence ? nixosModules;
    };
}
