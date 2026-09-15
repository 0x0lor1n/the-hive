# Sourced by both devshells (repo + workstation). Pin agenix-rekey to the TPM
# identity of the host we are running on: rage aborts on the first TPM
# identity it cannot open ("unable to acquire SRK"), so with two TPM master
# identities `agenix rekey/generate` must never be handed the foreign one.
# The recipient is read from the `# Recipient:` header age-plugin-tpm writes
# into secrets/<host>-nix-rage.pub (same value as masterIdentities[*].pubkey
# in cells/workstation/profiles/secrets.nix) — one source of truth, and no
# high-entropy literal for gitleaks to trip on.
_ap_pub="${BASH_SOURCE[0]%/*}/../secrets/$(uname -n)-nix-rage.pub"
if [ -r "$_ap_pub" ]; then
  _ap_rcpt=$(sed -n 's/^# Recipient: \(age1tag1[a-z0-9]*\)$/\1/p' "$_ap_pub" | head -n1)
  if [ -n "$_ap_rcpt" ]; then
    export AGENIX_REKEY_PRIMARY_IDENTITY="$_ap_rcpt"
    export AGENIX_REKEY_PRIMARY_IDENTITY_ONLY=true
  fi
fi
unset _ap_pub _ap_rcpt
