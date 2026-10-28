# Eval-time per-account secrets: secrets/roles/<role>.nix.age merged over the
# account's roles. Named by role: usernames stay encrypted.
{
  # `/. + unsafeDiscardStringContext inputs.self.outPath`, as globals.nix does:
  # extra-builtins.nix asserts isPath, outPath carries store context.
  flakeRoot,
  # The account's roles (hive.accounts).
  roles,
}: let
  identities = [
    (flakeRoot + "/secrets/penrose-nix-rage.pub")
    (flakeRoot + "/secrets/elster-nix-rage.pub")
  ];
  assertMsg = pred: msg: pred || builtins.throw msg;
  known = ["admin" "dev" "employer" "freelance"];

  load = role: let
    file = flakeRoot + "/secrets/roles/${role}.nix.age";
  in
    assert assertMsg (builtins.elem role known)
    "user secrets: unknown role `${role}` (expected ${toString known})";
      if builtins.pathExists file
      then
        assert assertMsg (builtins ? extraBuiltins) ''
          user secrets: `builtins.extraBuiltins` is missing. Run from the repo devshell,
          which sets NIX_CONFIG's plugin-files and extra-builtins-file.
        ''; let
          v = builtins.extraBuiltins.rageImportEncrypted identities file;
        in
          assert assertMsg (builtins.isAttrs v)
          "user secrets: secrets/roles/${role}.nix.age must decrypt to an attrset"; v
      else {};

  # Sorted, not in account order: the includeIf list ends up in ~/.gitconfig
  # and should not depend on how a host happens to list the roles.
  sets = map load (builtins.sort builtins.lessThan roles);
  cat = f: builtins.concatLists (map f sets);
  # One alias from two roles would silently pick one role's key.
  matchBlocks =
    builtins.foldl' (
      acc: s: let
        mb = s.ssh.matchBlocks or {};
        dup = builtins.filter (n: acc ? ${n}) (builtins.attrNames mb);
      in
        assert assertMsg (dup == [])
        "user secrets: ssh matchBlocks ${toString dup} defined by more than one role";
          acc // mb
    ) {}
    sets;
in {
  git.includes = cat (s: s.git.includes or []);
  ssh.includes = cat (s: s.ssh.includes or []);
  ssh.matchBlocks = matchBlocks;
}
