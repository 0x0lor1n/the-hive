# Eval-time user secrets: the per-account counterpart of cells/common/globals.nix.
#
# secrets/user-<role>.nix.age is a plain Nix attrset (git identities, ssh
# matchBlocks, vpn credentials) decrypted through the same
# rageImportEncrypted channel as globals. Unlike globals it is encrypted to the
# PIN-protected penrose identity (dellvis-nix-rage.pub) plus the offline
# recovery key, never to the PIN-less one: a home may only be evaluated by
# someone who can answer the TPM PIN, and unlock-secrets primes the cache for
# the no-tty cases. Anything with a RUNTIME consumer (key files, tokens that
# would otherwise land in /nix/store) stays agenix, not here.
#
# Named by ROLE, never by the account: both usernames live in the encrypted
# half of globals and a public path must not carry them. A missing file yields
# {} so a host or account without secrets still evaluates (same contract as
# nixos-config's importEncrypted).
{
  # `/. + unsafeDiscardStringContext inputs.self.outPath`, as globals.nix does:
  # extra-builtins.nix asserts isPath, outPath carries store context.
  flakeRoot,
  # "local" | "entra"
  role,
}: let
  file = flakeRoot + "/secrets/user-${role}.nix.age";
  identities = [(flakeRoot + "/secrets/dellvis-nix-rage.pub")];
  assertMsg = pred: msg: pred || builtins.throw msg;
in
  assert assertMsg (builtins.elem role ["local" "entra"])
  "user secrets: unknown role `${role}` (expected local|entra)";
    if builtins.pathExists file
    then assert assertMsg (builtins ? extraBuiltins) ''
      user secrets: `builtins.extraBuiltins` is missing. Run from the repo devshell,
      which sets NIX_CONFIG's plugin-files and extra-builtins-file.
    ''; let
      v = builtins.extraBuiltins.rageImportEncrypted identities file;
    in
      assert assertMsg (builtins.isAttrs v)
      "user secrets: secrets/user-${role}.nix.age must decrypt to an attrset"; v
    else {}
