{
  # No inputs, deliberately.
  #
  # This cell needs `colmena` for the CLI, but it takes it from the ROOT flake's
  # input rather than declaring its own. The root's colmena is the one whose
  # `__schema` the `colmenaHive` output reads, and the CLI asserts that schema
  # equals its own constant -- so sourcing both halves from ONE pin makes a
  # mismatch impossible rather than merely unlikely.
  #
  # A second declaration here would also need its own committed flake.lock; the
  # earlier version had none, so the input resolved to an empty lockfile and
  # fell through to the root's colmena silently. It worked only by coincidence.
  outputs = i: i;
}
