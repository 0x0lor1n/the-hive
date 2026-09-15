# Eval-time user secrets: the per-account counterpart of cells/common/globals.nix.
#
# secrets/user-<role>.nix.age is a plain Nix attrset (git identities, ssh
# matchBlocks, vpn credentials) decrypted through the same
# rageImportEncrypted channel as globals: encrypted to the PIN-protected TPM
# identities of both workstations (penrose-nix, elster-nix) plus the offline
# recovery key. A home may only be evaluated by someone who can answer a TPM
# PIN, and unlock-secrets primes the cache for the no-tty cases. Anything with
# a RUNTIME consumer (key files, tokens that would otherwise land in
# /nix/store) stays agenix, not here.
#
# Named by ROLE, never by the account: both usernames live in the encrypted
# half of globals and a public path must not carry them. A missing file yields
# {} so a host or account without secrets still evaluates (same contract as
# jarvis's importEncrypted).
{
  # `/. + unsafeDiscardStringContext inputs.self.outPath`, as globals.nix does:
  # extra-builtins.nix asserts isPath, outPath carries store context.
  flakeRoot,
  # "local" | "entra"
  role,
}: let
  file = flakeRoot + "/secrets/user-${role}.nix.age";
  identities = [
    (flakeRoot + "/secrets/penrose-nix-rage.pub")
    (flakeRoot + "/secrets/elster-nix-rage.pub")
  ];
  assertMsg = pred: msg: pred || builtins.throw msg;
in
  assert assertMsg (builtins.elem role ["local" "entra"])
  "user secrets: unknown role `${role}` (expected local|entra)";
    if builtins.pathExists file
    then
      assert assertMsg (builtins ? extraBuiltins) ''
        user secrets: `builtins.extraBuiltins` is missing. Run from the repo devshell,
        which sets NIX_CONFIG's plugin-files and extra-builtins-file.
      ''; let
        v = builtins.extraBuiltins.rageImportEncrypted identities file;
      in
        assert assertMsg (builtins.isAttrs v)
        "user secrets: secrets/user-${role}.nix.age must decrypt to an attrset"; v
    else {}
