# `agenix` CLI backend: `nix run .#agenix-rekey.<system>.<app>`, exposed by
# the root flake. Only this cell's hosts: agenix-rekey walks
# `config.age.secrets` of every node it is given, and server hosts have no
# `age`.
{
  inputs,
  cell,
  system,
  ...
}:
inputs.agenix-rekey.configure {
  userFlake = inputs.self;
  nixosConfigurations = cell.nixosConfigurations;
  systems = [system];
}
