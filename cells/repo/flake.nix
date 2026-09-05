{
  # Developer tooling only. cells/server never reads inputs.cells.repo, so an
  # input here cannot enter a host's evaluation -- unlike a root input.
  inputs = {
    # Does NOT follow our nixpkgs: its package set references nodejs_26, which
    # our pin lacks, and forcing the follow aborts eval. Its own nixpkgs also
    # lets numtide's cache serve these prebuilt.
    llm-agents.url = "github:numtide/llm-agents.nix/304ada966596829e870cacc580e6b8bf27186744";

    # Devshell as a module system (env, enterShellCommands) and the lefthook
    # module on top of it. Same pair rensa/core uses for its own repo shell.
    devshell.url = "gitlab:rensa-nix/devshell?dir=lib";
    devtools-lib.url = "gitlab:rensa-nix/devtools?dir=lib";
  };

  # colmena deliberately not declared (see root flake.nix). A cell input with
  # no committed flake.lock resolves to an EMPTY lockfile and silently falls
  # through to the root input of the same name -- hence the lock here.
  outputs = i:
    i
    // {
      dslib = i.devshell.lib {inherit (i.parent) pkgs;};
    };
}
