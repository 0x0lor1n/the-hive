{
  inputs,
  cell,
  ...
}:
import ../../common/load-profiles.nix {
  inherit inputs cell;
  dir = ./.;
}
