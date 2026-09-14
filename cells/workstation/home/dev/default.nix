# Developer tooling shared by both accounts (phase 2): languages, editors,
# agent CLIs (claude-code, opencode — SHARED packages by decision 2026-09-14,
# per-home state stays under $HOME). Unconditional. Git identities are NOT
# here: they come from the encrypted per-role attrset (home/secrets.nix) and
# are wired in ../default.nix (programs.git.includes).
{...}: {
  imports = [];
}
