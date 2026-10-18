{
  inputs,
  cell,
  ...
}: {
  environment.etc."nixos/configuration.nix".text = ''
    throw '''
      This machine is not managed by nixos-rebuild, but by colmena.
    '''
  '';

  deployment = {
    # Static lease on minas-tirith (lan.staticLeases).
    targetHost = "192.168.10.154";
    targetUser = "root";
    buildOnTarget = false;
    tags = ["nas"];
  };
}
