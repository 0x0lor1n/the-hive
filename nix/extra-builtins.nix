# nix-plugins extra-builtins: makes `rageImportEncrypted` available during
# EVALUATION, so an age-encrypted .nix file can be merged into `globals`.
#
# Ported from ~/nixos-config/flake/extra-builtins.nix (itself forked from
# oddlama/nix-config). Loaded via NIX_CONFIG's `extra-builtins-file` in
# cells/repo/devshells.nix -- which is why every nix command touching
# `globals` must run inside the devshell.
{ exec, ... }:
let
  assertMsg = pred: msg: pred || builtins.throw msg;
in
{
  # Calls a caching wrapper rather than rage directly, so a TPM-backed
  # identity is only exercised once per file rather than once per eval.
  rageImportEncrypted =
    identities: nixFile:
    let
      # Accepts both plain paths and agenix-rekey's { identity, pubkey }
      # attrset form, so the same list can be shared with masterIdentities.
      identityPaths = map (
        identity: if builtins.isAttrs identity then identity.identity else identity
      ) identities;
    in
    assert assertMsg (builtins.isPath nixFile)
      "The file to decrypt must be given as a path to prevent impurity.";
    exec (
      [
        "sh"
        ./rageImportEncrypted.sh
        nixFile
      ]
      ++ identityPaths
    );
}
