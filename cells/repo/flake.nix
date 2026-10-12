{
  # Developer tooling only. cells/server never reads inputs.cells.repo, so an
  # input here cannot enter a host's evaluation -- unlike a root input.
  inputs = {
    # Does NOT follow our nixpkgs: its package set references nodejs_26, which
    # our pin lacks, and forcing the follow aborts eval. Its own nixpkgs also
    # lets numtide's cache serve these prebuilt.
    llm-agents.url = "github:numtide/llm-agents.nix/c9ef0fb47c91abf5c637218b69a018d3b37bb8d9";

    # Devshell as a module system (env, enterShellCommands) and the lefthook
    # module on top of it. Same pair rensa/core uses for its own repo shell.
    devshell.url = "gitlab:rensa-nix/devshell?dir=lib";
    devtools-lib.url = "gitlab:rensa-nix/devtools?dir=lib";

    # One `treefmt` for every formatter; lefthook calls it, not each tool.
    # Its nixpkgs is only used for `lib` -- the wrapper is built with ours.
    treefmt-nix.url = "github:numtide/treefmt-nix";

    # agenix CLI for every agenix host. Pins match the host cells' (the modules
    # come from there); nixpkgs is only the follows target.
    nixpkgs.url = "github:NixOS/nixpkgs/34ab99075ac4f7e40cf037eef32cb1c360bb85e9";
    agenix-rekey.url = "github:oddlama/agenix-rekey/8b9c179bc1300ab130c90f2d25426bf0e7a2b58d";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
  };

  # colmena deliberately not declared (see root flake.nix). A cell input with
  # no committed flake.lock resolves to an EMPTY lockfile and silently falls
  # through to the root input of the same name -- hence the lock here.
  outputs = i:
    i
    // {
      dslib = i.devshell.lib {inherit (i.parent) pkgs;};
      treefmt = import i.treefmt-nix;
    };
}
