# wintermute shell: the LA-E152P port, dump to build to flash. Everything
# from recon to flash-bios lives here. Dumps never enter git: recon/ is
# gitignored except the text reports.
# Programmer: ESP-Prog (FT2232H). Port A = JTAG header, MPSSE mode.
#   TCK->CLK  TDI->MOSI  TDO->MISO  TMS->CS#  GND  3.3V->VCC+WP#+HOLD#
# Board fully unpowered: no AC, no battery, no CMOS cell.
{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;

  programmer = "ft2232_spi:type=2232H,port=A,divisor=8";

  prologue = ''
    # shellcheck disable=SC2034
    root=$(git rev-parse --show-toplevel)
    recon="$root/cells/wintermute/recon/''${BOARD:-i7u}"
    mkdir -p "$recon"
  '';

  # Phase 0.1: everything readable from the running stock system. Run as root
  # on the target BEFORE teardown. Free, ~15 min, and the Boot Guard answer
  # here decides whether the project continues.
  recon = pkgs.writeShellApplication {
    name = "recon";
    runtimeInputs = with pkgs; [git coreutils util-linux coreboot-utils msr-tools dmidecode pciutils usbutils acpica-tools kmod];
    text =
      prologue
      + ''
        if [ "$(id -u)" -ne 0 ]; then
          echo "recon: run as root (sudo --preserve-env=BOARD recon)" >&2
          exit 1
        fi
        cd "$recon"
        modprobe msr || true
        echo "== Boot Guard / ME (kill-switch) =="
        intelmetool -b 2>&1 | tee intelmetool-b.txt || true
        intelmetool -m 2>&1 | tee intelmetool-m.txt || true
        rdmsr -0 0x13A 2>&1 | tee msr-0x13A-boot-guard-sacm.txt || true
        echo "== chipset / GPIO =="
        inteltool -a > inteltool.txt 2>&1 || true
        superiotool -dV > superiotool.txt 2>&1 || true
        echo "== ACPI =="
        acpidump -o acpi.dat >/dev/null && (cd . && acpixtract -a acpi.dat >/dev/null 2>&1 || true)
        for t in dsdt*.dat ssdt*.dat; do [ -e "$t" ] && iasl -d "$t" >/dev/null 2>&1 || true; done
        echo "== PCI / USB / DMI / mem =="
        lspci -nnvvvxxxx > lspci.txt 2>&1
        lsusb -v > lsusb.txt 2>&1 || true
        dmidecode > dmi.txt
        cat /proc/iomem > iomem.txt
        cat /proc/cpuinfo > cpuinfo.txt
        cat /sys/class/dmi/id/bios_version > bios_version.txt
        echo "== EC map from DSDT =="
        grep -n -i -E 'OperationRegion.*(EC|ERAM)|Device \(EC' dsdt.dsl > ec-map.txt 2>&1 || true
        rm -f acpi.dat
        chown -R "''${SUDO_UID:-0}:''${SUDO_GID:-0}" "$recon"
        echo "recon: written to $recon"
        echo "recon: now READ intelmetool-b.txt — Boot Guard fused/verified => stop."
      '';
  };

  # Phase 0.4: two reads + cmp, or nothing. Chip autodetect first; if flashrom
  # sees several candidates, pass CHIP=W25Q128.V etc.
  dump = pkgs.writeShellApplication {
    name = "dump";
    runtimeInputs = with pkgs; [git coreutils flashrom diffutils];
    text =
      prologue
      + ''
        out="$recon/stock-$(date +%Y%m%d).bin"
        chip=""
        [ -n "''${CHIP:-}" ] && chip="-c $CHIP"
        # shellcheck disable=SC2086
        flashrom -p ${programmer} $chip -r "$out.1"
        # shellcheck disable=SC2086
        flashrom -p ${programmer} $chip -r "$out.2"
        cmp "$out.1" "$out.2" && mv "$out.1" "$out" && rm "$out.2"
        sha256sum "$out" | tee "$out.sha256"
        echo "dump: $out — copy to KeePass attachment + osgiliath NOW, before anything else."
      '';
  };

  # Phase 0.5: layout + ME state from a dump.
  inspect = pkgs.writeShellApplication {
    name = "inspect";
    runtimeInputs = with pkgs; [git coreutils coreboot-utils me_cleaner uefitool];
    text =
      prologue
      + ''
        img="''${1:?usage: inspect <stock.bin>}"
        cd "$recon"
        ifdtool -d "$img" | tee ifd.txt
        ifdtool -f layout.txt "$img"
        ifdtool -x "$img"
        me_cleaner -c "$img" | tee me_cleaner-c.txt || true
        echo "inspect: regions in $recon (flashregion_*.bin), layout.txt, ifd.txt, me_cleaner-c.txt"
      '';
  };

  # Phase 1.5+: BIOS region only. Descriptor/ME/GbE stay stock until Phase 3.4.
  flash-bios = pkgs.writeShellApplication {
    name = "flash-bios";
    runtimeInputs = with pkgs; [git coreutils flashrom];
    text =
      prologue
      + ''
        img="''${1:?usage: flash-bios <coreboot.rom>}"
        [ -e "$recon/layout.txt" ] || { echo "flash-bios: no $recon/layout.txt — run inspect first" >&2; exit 1; }
        echo "flash-bios: writing BIOS region only from $img (board=''${BOARD:-i7u}). Ctrl-C within 5s to abort."
        sleep 5
        flashrom -p ${programmer} -l "$recon/layout.txt" -i bios -w "$img"
      '';
  };

  # Before/after numbers. Same kernel + same charger + lid open + on AC, or
  # the comparison is noise. Run: stock (Phase 0.6 / A.7), coreboot (4.8 / 5.7),
  # coreboot+undervolt (5.8). ~13 min. Output is one text file per run.
  bench = pkgs.writeShellApplication {
    name = "bench";
    runtimeInputs = with pkgs; [git coreutils util-linux kmod sysbench stress-ng lm_sensors linuxPackages.turbostat];
    text =
      prologue
      + ''
        tag="''${1:?usage: bench <tag>   e.g. stock | coreboot | coreboot-uv}"
        if [ "$(id -u)" -ne 0 ]; then
          echo "bench: run as root (sudo --preserve-env=BOARD bench $tag)" >&2
          exit 1
        fi
        if ! grep -qs 1 /sys/class/power_supply/AC*/online; then
          echo "bench: plug in the 130 W charger first — battery numbers are not comparable" >&2
          exit 1
        fi
        modprobe msr || true
        n=$(nproc)
        out="$recon/bench-$tag-$(date +%Y%m%d).txt"
        ts="turbostat --quiet --Summary --show Busy%,Bzy_MHz,CoreTmp,PkgTmp,PkgWatt"
        {
          echo "== bench tag=$tag board=''${BOARD:-i7u} $(date -Is)"
          echo "bios: $(cat /sys/class/dmi/id/bios_version) kernel: $(uname -r) nproc: $n"
          echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo n/a)"
          echo "== boot"
          command -v systemd-analyze >/dev/null && systemd-analyze || echo "n/a"
          echo "== idle 60 s (Busy% / MHz / temp / W)"
          # shellcheck disable=SC2086
          $ts sleep 60
          echo "== sysbench cpu 30 s"
          sysbench cpu --threads="$n" --time=30 run | grep -E 'events per second|total time'
          echo "== sysbench memory"
          sysbench memory --threads="$n" --memory-block-size=1M --memory-total-size=32G run | grep -E 'MiB/sec|total time'
          echo "== sustained 10 min: stress-ng all cores (bogo ops) + turbostat average over the run"
          # shellcheck disable=SC2086
          $ts stress-ng --cpu "$n" --timeout 600 --metrics-brief
          echo "== sensors after"
          sensors
        } 2>&1 | tee "$out"
        chown "''${SUDO_UID:-0}:''${SUDO_GID:-0}" "$out"
        echo "bench: written to $out — commit it (text, small)."
      '';
  };
in {
  wintermute = pkgs.mkShellNoCC {
    name = "wintermute";
    packages = with pkgs; [
      # dump / flash
      flashrom
      flashprog
      # coreboot utils: ifdtool, cbfstool, cbmem, nvramtool, inteltool, intelmetool, superiotool, ectool
      coreboot-utils
      intelp2m
      me_cleaner
      # stock BIOS surgery: FSP, VBT, microcode extraction
      uefitool
      uefi-firmware-parser
      binwalk
      # live-system recon
      msr-tools
      dmidecode
      pciutils
      usbutils
      acpica-tools
      # build
      coreboot-toolchain.i386 # coreboot proper (romstage/ramstage are 32-bit)
      coreboot-toolchain.x64 # 64-bit payloads (edk2)
      gnumake
      python3
      pkg-config
      ncurses # menuconfig
      flex
      bison
      openssl
      zlib
      # serial (payload console via USB-UART if we get one)
      picocom
      # helpers
      recon
      dump
      inspect
      flash-bios
      bench
      alejandra
    ];
    shellHook = ''
      export COREBOOT_SRC=${inputs.coreboot}
      export FLASHROM_PROGRAMMER="${programmer}"
      echo "wintermute: LA-E152P firmware shell (BOARD=''${BOARD:-i7u}; set BOARD=xeon for the new board)"
      echo "  sudo --preserve-env=BOARD recon   phase 0.1: live-system recon -> cells/wintermute/recon/\$BOARD/"
      echo "  dump                              phase 0.4: 2x SPI read + cmp via ESP-Prog"
      echo "  inspect <stock.bin>               phase 0.5: ifdtool layout/regions, me_cleaner -c"
      echo "  flash-bios <coreboot.rom>         phase 1.5: write BIOS region only"
      echo "  coreboot src: \$COREBOOT_SRC (read-only; cp -r to work on it)"
    '';
  };
}
