# Backend of the `agenix` CLI (`nix run .#agenix-rekey.<system>.<app>`). Every
# node passed here must define `age`; btrfs servers do not.
{
  inputs,
  system,
  ...
}:
inputs.agenix-rekey.configure {
  userFlake = inputs.self;
  nixosConfigurations =
    inputs.cells.workstation.nixosConfigurations
    // {inherit (inputs.cells.server.nixosConfigurations) minas-tirith;};
  systems = [system];
}
