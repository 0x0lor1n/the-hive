# Master identities and per-host SSH recipients.
#
# In test-vm this lived on `inputs.self.secretsConfig` -- a flake-output
# attribute -- which forced the secrets profile into the soil, because during
# `grow` the soil does not exist yet (test-vm flake.nix:146-149).
#
# rensa makes that impossible rather than merely awkward: `inputs.self` is
# reduced to sourceInfo inside a cell block (verified by spike A), so a
# flake-level attribute is unreachable by construction.
#
# A block is the better home anyway: any cell can read
# `inputs.cells.common.secretsConfig` without a soil round-trip.
{...}: {
  # Explicit pubkeys are REQUIRED for TPM-sealed identities: agenix-rekey's
  # auto-extraction only handles yubikey/fido2-hmac, so without them rage is
  # invoked with `-i <identity-file>` and fails with "identity encodings not
  # supported".
  #
  # Order matters. The PIN-less workstation identity stays FIRST so decryption
  # remains non-interactive -- that is what `agenix view/generate/rekey`
  # depends on.
  masterIdentities = [
    {
      identity = "/secrets/jarvis-nopin-rage.pub";
      pubkey = "age1tag1q2vgn00whx3eukfv6n97udenlcl2nqx39ykq40z5gccc3exugtdq6kedkgm";
    }
    {
      identity = "/secrets/dellvis-nix-rage.pub";
      pubkey = "age1tpm1q2ggf943ppzwpqwcf39m0r3ztj3vzg6yap2e3tewda7m7k6k0cxdv70jqfk";
    }
  ];

  # A host pubkey is PUBLIC and belongs in git: it is the recipient, not a
  # secret. Only the matching PRIVATE host key -- which lives in /etc/ssh on
  # the machine -- can decrypt what is encrypted to it.
  #
  # osgiliath carries no agenix secrets today (it uses colmena's
  # deployment.keys instead), so it has no entry yet.
  hostPubkeys = {};
}
