{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;
in {
  # Anthropic loopback proxy that images the bulky, hash-free parts of each
  # request (system prompt, tool docs, cold history). Lossy: hashes read back
  # from imaged history are a confabulation risk; fresh tool output stays text.
  pxpipe = pkgs.buildGoModule {
    pname = "pxpipe";
    version = "0.4.19";
    src = ./pxpipe;
    vendorHash = "sha256-c+gc91FSkIegK3G+rZPjhV69vmvhZ6uLju4mO9h9IRQ=";
    meta.mainProgram = "pxpipe";
  };

  # PATH shim named "nix" for agent shells: collapses copying/building progress
  # on stderr to one summary line. From the first "error" line onward
  # everything is verbatim; warnings/traces always pass. TTY or NIXQ=off →
  # exec the real nix untouched. See cells/repo/nixq/main_test.go.
  nixq = pkgs.buildGoModule {
    pname = "nixq";
    version = "0.1.0";
    src = ./nixq;
    vendorHash = null;
    # Shipped as `nix` so it shadows the client without touching call sites.
    postInstall = "mv $out/bin/nixq $out/bin/nix";
    meta.mainProgram = "nix";
  };

  # Rust Token Killer: rewrites git/cargo/ls/... to compact output before it
  # reaches the model. Drops noise, keeps signal; pinned tag, CLI filters only —
  # telemetry is disabled in the devshell via RTK_TELEMETRY_DISABLED=1.
  rtk = pkgs.rustPlatform.buildRustPackage rec {
    pname = "rtk";
    version = "0.47.0";
    src = pkgs.fetchFromGitHub {
      owner = "rtk-ai";
      repo = "rtk";
      tag = "v${version}";
      hash = "sha256-qYVkFLS6G4Tf1NmD9B3kJkyb47XREoVE65EqBtbzzjs=";
    };
    cargoHash = "sha256-2lwLPia3v7xagKsrCpayixZMmOqX15qrjsVP8/RQCXE=";
    # Upstream tests touch $HOME / network; smoke-checked in the devshell instead.
    doCheck = false;
    meta.mainProgram = "rtk";
  };
}
