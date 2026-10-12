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
    # LAN address; the ygg0 address is the out-of-band path.
    targetHost = "192.168.10.1";
    targetUser = "root";
    buildOnTarget = false;
    tags = ["router"];
  };
}
