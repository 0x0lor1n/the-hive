# dev: the account that writes code and runs the agents. Dev tooling and
# agent CLIs (../dev), osint and tor (../security), personal chat apps.
{roleInputs, ...}: {
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

  # t.me "Open in app" and tg:// links from the browser, through the portal.
  xdg.mimeApps.defaultApplications."x-scheme-handler/tg" = "org.telegram.desktop.desktop";

  # Default author; the includeIf blocks (secrets, per remote glob) come
  # later in the file and override it on work remotes.
  programs.git = {
    userName = roleInputs.git.name;
    userEmail = roleInputs.git.email;
  };
}
