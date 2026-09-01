# SPIKE A: is `rageImportEncrypted` (a nix-plugins extra-builtin) reachable
# from inside a cell block, given that rensa evaluates cell flakes through its
# own call-flake rather than Nix's flake machinery?
#
# If this fails, the encrypted-globals design must move to the root flake,
# which removes the per-cell isolation that motivates the whole spike.
# See iteration-14 plan, spike A and kill criterion 1.
{
  inputs,
  cell,
  system,
  ...
}: let
  root = /. + builtins.unsafeDiscardStringContext inputs.self.outPath;

  hasNamespace = builtins ? extraBuiltins;
  hasFunction = hasNamespace && (builtins.extraBuiltins ? rageImportEncrypted);

  decrypted =
    if !hasFunction
    then null
    else
      builtins.extraBuiltins.rageImportEncrypted
      [(root + "/secrets/jarvis-nopin-rage.pub")]
      (root + "/secrets/probe.nix.age");
in {
  inherit hasNamespace hasFunction system;

  # what the block signature actually provides
  signatureKeys = builtins.attrNames { inherit inputs cell system; };
  selfIsSourceInfoOnly = !(inputs.self ? outputs);
  cellFlakeInputResolved = inputs.impermanenceOk or "cell-flake-outputs-not-visible";
  pkgsInjected = inputs ? pkgs;

  # the actual question
  decryptedKeys =
    if decrypted == null
    then "N/A - builtin missing"
    else builtins.attrNames decrypted;
  decryptedValue =
    if decrypted == null
    then "N/A"
    else decrypted.probe;
}
