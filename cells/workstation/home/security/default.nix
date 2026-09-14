# Per-account key/VPN material (phase 2). This is the only module that
# differs between the two homes: it consumes the role's `secrets` attrset
# (home/secrets.nix, decrypted from secrets/user-<role>.nix.age) via
# _module.args.secrets and never hard-codes a key or a host. ssh matchBlocks
# and the ssh-agent are already wired in ../default.nix; VPN profiles land
# here as NetworkManager connections keyed by age.secrets (see plan:
# "host-global VPN routing is ACCEPTABLE").
{...}: {
  imports = [];
}
