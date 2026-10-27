# dev: the account that writes code and runs the agents. Dev tooling and
# agent CLIs (../dev), osint and tor (../security), personal chat apps.
{
  lib,
  accountRoles,
  roleInputs,
  ...
}: {
  imports = [../dev ../security ../security/tor.nix];

  # Sandboxed (packages.nix). Grayjay: one account per host, fixed /tmp
  # launch symlinks (nixpkgs#415842).
  home.packages = [
    roleInputs.packages.telegram-desktop
    roleInputs.packages.grayjay
  ];

  # The account's own daemon (profiles/role-dev.nix, rootless): the socket
  # lives in the runtime dir, not /var/run. Set here, not through the
  # module's setSocketVariable, so admin's shells keep the rootful socket.
  home.sessionVariables.DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/docker.sock";

  # Global author only on an account with no work role. Where freelance or
  # employer keys live, every identity comes from an includeIf (secrets), so
  # a commit to a remote nobody listed fails loudly instead of leaking the
  # wrong author.
  programs.git = lib.mkIf (!lib.elem "freelance" accountRoles && !lib.elem "employer" accountRoles) {
    userName = roleInputs.git.name;
    userEmail = roleInputs.git.email;
  };
}
