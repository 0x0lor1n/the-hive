#!/usr/bin/env bash
# One PIN session: decrypt jarvis's vpn-{owt,tiko,wrs}.nix.age + user.nix.age
# (all encrypted to dellvis-nix-rage, the penrose PIN identity), split them
# into the five runtime files profiles/vpn.nix expects, encrypt each to the
# master identities + recovery key (secrets/vpn/<name>.age) and write the
# rekeyed copy for penrose (secrets/rekeyed/penrose/<identHash>-vpn-<n>.age),
# same identHash rule agenix-rekey uses:
#   substring 0 32 (sha256 (sha256 hostPubkey ++ sha256 file))
# Plaintext lives only in a 0700 tmpfs dir for the duration of the run.
set -euo pipefail
root=$(git -C /srv/the-hive rev-parse --show-toplevel)
jarvis=/srv/workspace/projects/nixos-config/users/jarvis/secrets
ident="$root/secrets/dellvis-nix-rage.pub"
recips=(
  -r age1tag1q2vgn00whx3eukfv6n97udenlcl2nqx39ykq40z5gccc3exugtdq6kedkgm # jarvis-nopin (master)
  -r age1tag1q2ggf943ppzwpqwcf39m0r3ztj3vzg6yap2e3tewda7m7k6k0cxdv9dramt # dellvis/penrose PIN (master)
  -r age12tng070ds3cr6xfhlyqqqc5mnavgxuen865uynr8vja2krt8cy2qz0p80l      # offline recovery
)
hostpub=$(nix eval --raw "$root#nixosConfigurations.penrose.config.age.rekey.hostPubkey")

# tmpfs only: $XDG_RUNTIME_DIR when the session has one, /dev/shm otherwise
# (a plain ssh/sudo shell on penrose may have no /run/user/$UID).
tmpbase=${XDG_RUNTIME_DIR:-/dev/shm}
[ -d "$tmpbase" ] || tmpbase=/dev/shm
tmp=$(mktemp -d -p "$tmpbase" vpn-transplant.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
umask 077

echo ">> decrypting 4 files with $(basename "$ident") (TPM PIN once)" >&2
for f in vpn-owt vpn-tiko vpn-wrs user; do
  rage -d -i "$ident" -o "$tmp/$f.nix" "$jarvis/$f.nix.age"
done

# nix does the splitting: attr paths as on jarvis (security/vpn.nix).
nix-instantiate --eval --strict --raw -E "
  let o = (import $tmp/vpn-owt.nix).vpn.bdl; in ''
    [Interface]
    PrivateKey = \${o.privateKey}
    Address = \${o.address}
    DNS = \${o.dns}

    [Peer]
    PublicKey = \${o.peer.publicKey}
    AllowedIPs = \${o.peer.allowedIPs}
    Endpoint = \${o.peer.endpoint}
  ''" >"$tmp/owt.conf"
nix-instantiate --eval --strict --raw -E "(import $tmp/vpn-tiko.nix).vpn.owt-ovpn" >"$tmp/tiko.ovpn"
nix-instantiate --eval --strict --raw -E "(import $tmp/vpn-wrs.nix).vpn.wrs-ovpn" >"$tmp/wrs.ovpn"
for n in tiko wrs; do
  nix-instantiate --eval --strict --raw -E "let c = (import $tmp/user.nix).vpn.$n; in c.username + \"\n\" + c.password + \"\n\"" >"$tmp/$n-auth"
done

# Sanity before encrypting anything.
grep -q '^PrivateKey = .\+' "$tmp/owt.conf"
for n in tiko wrs; do
  grep -q -E '^(remote|client)' "$tmp/$n.ovpn"
  [ "$(wc -l <"$tmp/$n-auth")" = 2 ]
done
echo ">> split OK: $(wc -c <"$tmp/owt.conf")B owt.conf, $(wc -c <"$tmp/tiko.ovpn")B tiko.ovpn, $(wc -c <"$tmp/wrs.ovpn")B wrs.ovpn, 2 auth files" >&2

mkdir -p "$root/secrets/vpn" "$root/secrets/rekeyed/penrose"
pubhash=$(printf '%s' "$hostpub" | sha256sum | cut -d' ' -f1)
for name in owt.conf tiko.ovpn tiko-auth wrs.ovpn wrs-auth; do
  src="$root/secrets/vpn/$name.age"
  rage -e "${recips[@]}" -o "$src" "$tmp/$name"
  filehash=$(sha256sum "$src" | cut -d' ' -f1)
  ident_hash=$(printf '%s%s' "$pubhash" "$filehash" | sha256sum | cut -c1-32)
  # age.secrets name = vpn-<file with . -> -> (owt.conf -> vpn-owt-conf), as in profiles/vpn.nix
  secret="vpn-${name//./-}"
  rage -e -r "$hostpub" -o "$root/secrets/rekeyed/penrose/$ident_hash-$secret.age" "$tmp/$name"
  echo "   $src -> rekeyed/penrose/$ident_hash-$secret.age" >&2
done
chmod 644 "$root"/secrets/vpn/*.age "$root"/secrets/rekeyed/penrose/*-vpn-*.age
echo ">> done; plaintext dir removed on exit" >&2
