{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;
  lib = pkgs.lib;
  theme = inputs.cells.theme.palettes.kanagawa;

  # dwl and somebar are C/C++ and cannot import Nix, so their config files
  # carry @theme_<role>@ placeholders that replaceVars fills from the palette.
  # `f` adapts the hex to the language: dwl wants a bare rrggbb inside
  # COLOR(0x...ff), somebar wants "0xrr, 0xgg, 0xbb" for Color(r, g, b).
  # replaceVars fails on an unused variable, so each file names the roles it
  # actually reads.
  themeVars = f: roles: lib.genAttrs (map (r: "theme_${r}") roles) (n: f theme.roles.${lib.removePrefix "theme_" n});
  cxxRgb = hex: lib.concatMapStringsSep ", " (b: "0x${b}") [(builtins.substring 0 2 hex) (builtins.substring 2 2 hex) (builtins.substring 4 2 hex)];

  dwlConfig = pkgs.replaceVars ./packages/dwl/config.h (themeVars lib.id ["bg" "border" "focus" "urgent"]);
  somebarConfig = pkgs.replaceVars ./packages/somebar/config.hpp (themeVars cxxRgb ["bg" "fg" "focus"]);
in {
  # dwl with our config.h. dwl's Makefile copies config.def.h to config.h only
  # when the latter is absent, so dropping the file in is the whole override --
  # no sed patching of upstream. Keybinds and rationale live in packages/dwl/config.h.
  # movestack from codeberg.org/dwl/dwl-patches, config.def.h hunks stripped
  # (our config.h carries the keybinds). Re-fetch on a dwl version bump.
  dwl = pkgs.dwl.overrideAttrs (old: {
    patches =
      (old.patches or [])
      ++ [
        ./packages/dwl/patches/movestack-0.8.patch
        # Keybindings are latin; without this none of them fire while the
        # ru group is active (xkb_state_key_get_syms follows the group).
        ./packages/dwl/patches/latin-keybindings.patch
      ];
    postPatch =
      (old.postPatch or "")
      + ''
        cp ${dwlConfig} config.h
      '';
  });

  # Colors/font in packages/somebar/config.hpp; nixpkgs copies `conf` over
  # src/config.hpp in prePatch.
  # DWL 0.8 advertises zwlr_layer_shell_v1 version 3; somebar hardcodes 4 and
  # exits at once without this.
  somebar = (pkgs.somebar.override {conf = somebarConfig;}).overrideAttrs (old: {
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
