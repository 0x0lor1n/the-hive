{
  # Developer tooling only. Nothing here reaches a host: `cells/server` never
  # reads `inputs.cells.repo`, so an input added here cannot enter osgiliath's
  # evaluation. That is the whole reason it goes in this cell rather than the
  # root -- a root input is visible to EVERY cell, and would put an LLM agent
  # into the fetch set of a headless VPS.
  inputs = {
    # Coding agents, packaged. Supplies `hermes-agent`; the same input backs
    # test-vm's claude/opencode home modules, so the two repos agree on a
    # source.
    #
    # Deliberately does NOT follow our nixpkgs, unlike every other input in
    # this repo. Forcing the follow aborts evaluation -- llm-agents' package
    # set references nodejs_26, which our pin lacks, and touching any single
    # package forces the whole set (the abort surfaces from the unrelated
    # hermes-desktop). Keeping its own nixpkgs also lets numtide's cache serve
    # these prebuilt; building an agent toolchain locally is not the point of
    # this devshell.
    llm-agents.url = "github:numtide/llm-agents.nix/304ada966596829e870cacc580e6b8bf27186744";
  };

  # `colmena` is deliberately NOT declared here despite the devshell shipping
  # the CLI. It comes from the ROOT flake's input, because the root's colmena
  # is the one whose `__schema` the `colmenaHive` output reads, and the CLI
  # asserts that schema equals its own constant -- so sourcing both halves from
  # ONE pin makes a mismatch impossible rather than merely unlikely.
  #
  # That distinction is the reason this cell has a committed flake.lock now.
  # An earlier version declared colmena here with no lock, so the input
  # resolved to an EMPTY lockfile and fell through to the root's colmena
  # silently; it worked only because both pinned the same revision. A declared
  # input without a committed lock is the trap, not the declaration itself.
  outputs = i: i;
}
