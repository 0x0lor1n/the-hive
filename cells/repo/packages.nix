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
}
