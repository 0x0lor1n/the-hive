# Key-only ssh; the password is for sudo and the console.
{
  inputs,
  cell,
}: {
  lib,
  config,
  globals,
  host,
  ...
}: {
  options.router.adminKeyFiles = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    # The local user's key on each workstation.
    default = map (h: inputs.self.outPath + "/secrets/generated/${h}/user-ssh-key.pub") ["elster" "penrose"];
  };

  config = {
    users.users.${host.userName} = {
      isNormalUser = true;
      uid = globals.user.uid;
      extraGroups = ["wheel"];
      inherit (globals.user) hashedPassword;
      home = host.homeDir;
      openssh.authorizedKeys.keyFiles = config.router.adminKeyFiles;
    };

    security.sudo.wheelNeedsPassword = true;
  };
}
