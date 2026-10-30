{
  inputs,
  cell,
  ...
}: let
  inherit (inputs) pkgs;
  l = pkgs.lib;

  # Upstream tree with ./coreboot overlaid in the same layout (src/mainboard/..., 3rdparty/blobs/...).
  src = pkgs.runCommand "coreboot-src" {} ''
    cp -r ${inputs.coreboot} $out
    chmod -R u+w $out
    ${l.optionalString (builtins.pathExists ./coreboot) "cp -r ${./coreboot}/. $out/"}
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

  # Radial fade to black hides the square on the black GOP screen; BootLogoLib skips a logo taller than the mode.
  bootsplash = pkgs.runCommand "bootsplash.bmp" {nativeBuildInputs = [pkgs.imagemagick];} ''
    magick ${./assets/bootsplash.png} -alpha off \
      \( -size 820x820 radial-gradient:white-black -gravity center -crop 640x640+0+0 +repage -level 30%,85% \) \
      -compose multiply -composite -resize 400x400 BMP3:$out
  '';

  # Built outside coreboot's make: its edk2 Makefile git-clones into the tree, which the sandbox forbids.
  # Its `logo` target never runs either, so the splash is swapped in here.
  mkPayload = name: config:
    pkgs.stdenv.mkDerivation {
      name = "${name}-edk2";
      src = inputs.edk2;
      nativeBuildInputs = with pkgs; [python3 nasm acpica-tools bc];
      buildInputs = [pkgs.libuuid];
      hardeningDisable = ["all"];
      dontConfigure = true;
      postPatch = ''
        patchShebangs BaseTools
        install -m644 ${bootsplash} MdeModulePkg/Logo/Logo.bmp
      '';
      buildPhase = ''
        runHook preBuild
        export WORKSPACE=$PWD PACKAGES_PATH=$PWD PYTHON_COMMAND=python3
        make -C BaseTools -j$NIX_BUILD_CORES
        source edksetup.sh BaseTools
        build -a IA32 -a X64 -n $NIX_BUILD_CORES -b $(cat ${config}/edk2-target) \
          $(cat ${config}/edk2-flags) -D BUILD_ARCH=X64
        runHook postBuild
      '';
      installPhase = ''
        mkdir -p $out
        cp Build/UefiPayloadPkgX64/$(cat ${config}/edk2-target)_GCC/FV/UEFIPAYLOAD.fd $out/
      '';
    };

  mkRom = name: defconfig: let
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

  coreboot-5580 = mkRom "coreboot-5580" ./configs/precision_3520.defconfig;
  # Same pipeline on an in-tree board, to tell toolchain/edk2 failures from port failures.
  coreboot-qemu = mkRom "coreboot-qemu" ./configs/qemu_q35.defconfig;
}
