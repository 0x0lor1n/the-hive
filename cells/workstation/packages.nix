{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;
in {
  # dwl with our config.h. dwl's Makefile copies config.def.h to config.h only
  # when the latter is absent, so dropping the file in is the whole override --
  # no sed patching of upstream. Keybinds and rationale live in packages/dwl/config.h.
  dwl = pkgs.dwl.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        cp ${./packages/dwl/config.h} config.h
      '';
  });

  # Colors/font in packages/somebar/config.hpp; nixpkgs copies `conf` over
  # src/config.hpp in prePatch.
  # DWL 0.8 advertises zwlr_layer_shell_v1 version 3; somebar hardcodes 4 and
  # exits at once without this.
  somebar = (pkgs.somebar.override {conf = ./packages/somebar/config.hpp;}).overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace src/main.cpp \
          --replace-fail \
            'reg.handle(wlrLayerShell, zwlr_layer_shell_v1_interface, 4)' \
            'reg.handle(wlrLayerShell, zwlr_layer_shell_v1_interface, 3)'
      '';
  });
}
