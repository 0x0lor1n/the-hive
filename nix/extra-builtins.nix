# Forked from:
# https://github.com/oddlama/nix-config/blob/main/flake/extra-builtins.nix

{ exec, ... }:
let
  assertMsg = pred: msg: pred || builtins.throw msg;
in
{
  rageImportEncrypted =
    identities: nixFile:
    let
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
