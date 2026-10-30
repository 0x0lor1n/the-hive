{
  inputs,
  cell,
  ...
}: let
  inherit (inputs) pkgs;
  l = pkgs.lib;

  # Upstream tree with ./coreboot overlaid in the same layout (src/mainboard/..., 3rdparty/blobs/...).
  # Timeless builds stamp 1970 into SMBIOS, and Linux refuses runtime D3 to root ports of
  # pre-2015 firmware; the coreboot pin's commit date keeps the build reproducible.
  src = pkgs.runCommand "coreboot-src" {} ''
    cp -r ${inputs.coreboot} $out
    chmod -R u+w $out
    ${l.optionalString (builtins.pathExists ./coreboot) "cp -r ${./coreboot}/. $out/"}
    substituteInPlace $out/util/genbuild_h/genbuild_h.sh \
      --replace-fail 'DATE=0' 'DATE=${toString inputs.coreboot.lastModified}'
  '';

  makeFlags = ["XGCCPATH=${pkgs.coreboot-toolchain.i386}/bin/" "BUILD_TIMELESS=1"];
  nativeBuildInputs = with pkgs; [gnumake python3 perl flex bison pkg-config coreboot-utils];

  # Prints the edk2 `build` flags coreboot derives from .config.
  edk2FlagsMk = pkgs.writeText "edk2-flags.mk" ''
    include Makefile
    edk2-flags:
    	@echo $(BUILD_STR) > edk2-flags
    	@echo $(RELEASE_STR) > edk2-target
  '';

  mkConfig = name: defconfig:
    pkgs.stdenv.mkDerivation {
      name = "${name}-config";
      inherit src nativeBuildInputs makeFlags;
      dontConfigure = true;
      postPatch = "patchShebangs util";
      buildPhase = ''
        runHook preBuild
        make $makeFlags defconfig KBUILD_DEFCONFIG=${defconfig}
        # Kconfig silently drops unknown symbols and unmet selects.
        fail=0
        while IFS= read -r line; do
          grep -qxF "$line" .config || { echo "defconfig: dropped by Kconfig: $line" >&2; fail=1; }
        done < <(grep -E '^CONFIG_[A-Z0-9_]+=' ${defconfig})
        [ "$fail" = 0 ]
        make $makeFlags -s --no-print-directory \
          --eval 'edk2-flags: ; @$(MAKE) -C payloads/external/edk2 -f ${edk2FlagsMk} edk2-flags $(EDK2_PAYLOAD_ARGS)' \
          edk2-flags
        runHook postBuild
      '';
      installPhase = ''
        mkdir -p $out
        cp .config $out/config
        cp payloads/external/edk2/edk2-flags payloads/external/edk2/edk2-target $out/
      '';
    };

  # EFI console colours in EFI order (BLACK BLUE GREEN CYAN RED MAGENTA BROWN LIGHTGRAY, then bright) from the ANSI slots.
  # Imported by path: `inputs.cells.common` loads every block of that cell, encrypted globals included.
  efiColors = map (builtins.elemAt (import ../common/theme.nix {}).ansi) [0 4 2 6 1 5 3 7 8 12 10 14 9 13 11 15];
  efiPixel = hex: let
    byte = o: "0x${builtins.substring o 2 hex}";
  in "{ ${byte 4}, ${byte 2}, ${byte 0}, 0x00 }";
  efiColorTable = l.concatMapStringsSep "\n" (hex: "  ${efiPixel hex},") efiColors;

  # The setup browser assumes a light-grey body; with the dark palette the body goes black, and the
  # setup-form title/footer become outlines, as on the front page.
  browserColors = {
    TITLE_TEXT = "EFI_BLUE";
    TITLE_BACKGROUND = "EFI_BACKGROUND_BLACK";
    PICKLIST_HIGHLIGHT_TEXT = "EFI_BLACK";
    POPUP_TEXT = "EFI_BLACK";
    SUBTITLE_BACKGROUND = "EFI_BACKGROUND_BLACK";
    BANNER_BACKGROUND = "EFI_BACKGROUND_BLACK";
    FIELD_BACKGROUND = "EFI_BACKGROUND_BLACK";
    ARROW_BACKGROUND = "EFI_BACKGROUND_BLACK";
  };
  # Field text oldWhite; highlight = black on crystalBlue.
  browserPcds = l.concatStringsSep " " (l.mapAttrsToList (n: v: "--pcd gEfiMdeModulePkgTokenSpaceGuid.${n}=${v}") {
    PcdBrowserFieldTextColor = "0x07";
    PcdBrowserFieldTextHighlightColor = "0x00";
    PcdBrowserFieldBackgroundHighlightColor = "0x10";
  });

  # Radial fade into colour 0 (what ClearScreen paints) hides the square; BootLogoLib skips a logo taller than the mode.
  bootsplash = pkgs.runCommand "bootsplash.bmp" {nativeBuildInputs = [pkgs.imagemagick];} ''
    magick -size 640x640 xc:'#${builtins.head efiColors}' \( ${./assets/bootsplash.png} -alpha off \) \
      \( -size 820x820 radial-gradient:white-black -gravity center -crop 640x640+0+0 +repage -level 30%,85% \) \
      -composite -resize 400x400 BMP3:$out
  '';

  # Built outside coreboot's make: its edk2 Makefile git-clones into the tree, which the sandbox forbids.
  # Its `logo` target never runs either, so the splash is swapped in here.
  mkPayload = name: config:
    pkgs.stdenv.mkDerivation {
      name = "${name}-edk2";
      src = inputs.edk2;
      nativeBuildInputs = with pkgs; [python3 nasm acpica-tools bc perl];
      buildInputs = [pkgs.libuuid];
      hardeningDisable = ["all"];
      dontConfigure = true;
      postPatch = ''
        patchShebangs BaseTools
        install -m644 ${bootsplash} MdeModulePkg/Logo/Logo.bmp
        TABLE='${efiColorTable}' perl -0777 -pi -e \
          's/(mGraphicsEfiColors\[16\] = \{).*?\r?\n\};/$1\n$ENV{TABLE}\n};/s or die "mGraphicsEfiColors not found\n"' \
          MdeModulePkg/Universal/Console/GraphicsConsoleDxe/GraphicsConsole.c
        ${l.concatStrings (l.mapAttrsToList (n: v: ''
            perl -pi -e 's/^(#define ${n}\s+)\S+/''${1}${v}/ and $n++; END { $n or die "${n} not found\n" }' \
              MdeModulePkg/Library/CustomizedDisplayLib/Colors.h
          '')
          browserColors)}
        # GOP fills outside the console: the boot prompt strip, whose rows past the last text row the setup browser never repaints.
        subst() { perl -0777 -pi -e "\$n = s/$2/$3/g; \$n == $4 or die \"$1: $2 matched \$n, want $4\n\"" "$1"; }
        subst MdeModulePkg/Library/BootLogoLib/BootLogoLib.c \
          'SetMem \(&Color, sizeof \(EFI_GRAPHICS_OUTPUT_BLT_PIXEL\), 0x0\);' \
          'Color = (EFI_GRAPHICS_OUTPUT_BLT_PIXEL)${efiPixel (builtins.elemAt efiColors 0)};' 2
        subst UefiPayloadPkg/Library/PlatformBootManagerLib/PlatformBootManager.c \
          'Black.Blue = Black.Green = Black.Red = Black.Reserved = 0;' \
          'Black = (EFI_GRAPHICS_OUTPUT_BLT_PIXEL)${efiPixel (builtins.elemAt efiColors 0)};' 2
        subst UefiPayloadPkg/Library/PlatformBootManagerLib/PlatformBootManager.c \
          'White.Blue = White.Green = White.Red = White.Reserved = 0xFF;' \
          'White = (EFI_GRAPHICS_OUTPUT_BLT_PIXEL)${efiPixel (builtins.elemAt efiColors 15)};' 2
      '';
      buildPhase = ''
        runHook preBuild
        export WORKSPACE=$PWD PACKAGES_PATH=$PWD PYTHON_COMMAND=python3
        make -C BaseTools -j$NIX_BUILD_CORES
        source edksetup.sh BaseTools
        build -a IA32 -a X64 -n $NIX_BUILD_CORES -b $(cat ${config}/edk2-target) \
          $(cat ${config}/edk2-flags) ${browserPcds} -D BUILD_ARCH=X64
        runHook postBuild
      '';
      installPhase = ''
        mkdir -p $out
        cp Build/UefiPayloadPkgX64/$(cat ${config}/edk2-target)_GCC/FV/UEFIPAYLOAD.fd $out/
      '';
    };

  # M620 VBIOS from the stock BIOS region, never in git: `extract-vbios <stock.bin>` adds it to the store.
  m620Vbios = pkgs.requireFile {
    name = "m620-vbios.rom";
    sha256 = "d44ce6880a32085f3b3ce4adfccd228ad469e22798a9d2ca047c0751255acaaf";
    message = ''
      M620 VBIOS (GM107 E2704 SKU 0010, v82.07.BB.00.11) is not in the store.
      In `dev wintermute`: extract-vbios <stock dump of your own board>
    '';
  };

  mkRom = name: defconfig: {extraConfig ? ""}: let
    config = mkConfig name defconfig;
    payload = mkPayload name config;
  in
    pkgs.stdenv.mkDerivation {
      inherit name src nativeBuildInputs makeFlags;
      dontConfigure = true;
      postPatch = "patchShebangs util";
      buildPhase = ''
        runHook preBuild
        install -m644 ${config}/config .config
        echo 'CONFIG_PAYLOAD_FILE="${payload}/UEFIPAYLOAD.fd"' >> .config
        ${l.optionalString (extraConfig != "") "echo ${l.escapeShellArg extraConfig} >> .config"}
        make $makeFlags olddefconfig
        make $makeFlags -j$NIX_BUILD_CORES
        runHook postBuild
      '';
      installPhase = ''
        mkdir -p $out
        cp build/coreboot.rom .config $out/
        cbfstool build/coreboot.rom print > $out/cbfs.txt
      '';
      passthru = {inherit config payload;};
    };
in {
  # Stock inteltool refuses `-G` on the 200-series mobile PCHs (CM238 here).
  inteltool = pkgs.inteltool.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./patches/inteltool-cm238-gpio.patch];
  });

  coreboot-5580 = mkRom "coreboot-5580" ./configs/precision_3520.defconfig {
    extraConfig = ''CONFIG_VGA_BIOS_FILE="${m620Vbios}"'';
  };
  # Same pipeline on an in-tree board, to tell toolchain/edk2 failures from port failures.
  coreboot-qemu = mkRom "coreboot-qemu" ./configs/qemu_q35.defconfig {};
}
