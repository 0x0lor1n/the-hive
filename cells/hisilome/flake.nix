{
  # Nothing beyond what the parent already provides. zola, liquidsoap, icecast,
  # nginx and process-compose all come from nixpkgs via `inputs.parent.pkgs`.
  #
  # Kept as an explicit empty cell flake rather than omitted, so the isolation
  # boundary is visible: adding a dependency here affects the site and station
  # only, never the hosts.
  outputs = i: i;
}
