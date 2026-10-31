# wintermute shell: the LA-E152P port, dump to build to flash. Everything
# from recon to flash-bios lives here. Dumps never enter git: recon/ is
# gitignored except the text reports.
# Programmer: ESP-Prog (FT2232H). Port A = JTAG header, MPSSE mode.
#   TCK->CLK  TDI->MOSI  TDO->MISO  TMS->CS#  GND  3.3V->VCC+WP#+HOLD#
# Generic rig wiring and safety: https://github.com/0x0lor1n/spi-clip-rig
# Board fully unpowered: no AC, no battery, no CMOS cell.
{
  inputs,
  cell,
  ...
}: let
  inherit (inputs) pkgs;

  programmer = "ft2232_spi:type=2232H,port=A,divisor=8";

  # Same switcher as the repo/workstation shells: `cd "$(dev)"` gets back out.
  dev = pkgs.writeShellApplication {
    name = "dev";
    runtimeInputs = with pkgs; [git direnv coreutils];
    text = builtins.readFile "${inputs.self.outPath}/nix/dev.sh";
  };

  # Default board is xeon (LA-E152P, the port target). i7u = the spare board,
  # only for optional recon of the old board; pass BOARD=i7u explicitly for it.
  prologue = ''
    # shellcheck disable=SC2034
    root=$(git rev-parse --show-toplevel)
    recon="$root/cells/wintermute/recon/''${BOARD:-xeon}"
    mkdir -p "$recon"
  '';

  # Phase 0.1: everything readable from the running stock system. Run as root
  # on the target BEFORE teardown. Free, ~15 min. Boot Guard here no longer
  # decides go/no-go: fused + ME v11 (Kaby Lake) => deguard bypasses it.
  recon = pkgs.writeShellApplication {
    name = "recon";
    runtimeInputs = with pkgs; [git coreutils gnused util-linux cell.packages.inteltool coreboot-utils msr-tools dmidecode pciutils usbutils acpica-tools kmod];
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
        # intelmetool -m needs iomem=relaxed for the version; MEI sysfs does not
        cat /sys/class/mei/mei0/fw_ver > me-fw-ver.txt 2>&1 || true
        rdmsr -0 0x13A 2>&1 | tee msr-0x13A-boot-guard-sacm.txt || true
        echo "== chipset / GPIO =="
        inteltool -a > inteltool.txt 2>&1 || true
        superiotool -dV > superiotool.txt 2>&1 || true
        echo "== ACPI =="
        acpidump -o acpi.dat >/dev/null && (cd . && acpixtract -a acpi.dat >/dev/null 2>&1 || true)
        for t in dsdt*.dat ssdt*.dat; do [ -e "$t" ] && iasl -d "$t" >/dev/null 2>&1 || true; done
        echo "== PCI / USB / DMI / mem =="
        # recon/ is committed to a public repo: serials and UUIDs are redacted
        lspci -nnvvvxxxx 2>&1 | sed -E 's/(Device Serial Number) .*/\1 <redacted>/' > lspci.txt
        lsusb -v > lsusb.txt 2>&1 || true
        dmidecode | sed -E 's/^(\s*(Serial Number|UUID|Asset Tag):).*/\1 <redacted>/' > dmi.txt
        cat /proc/iomem > iomem.txt
        cat /proc/cpuinfo > cpuinfo.txt
        cat /sys/class/dmi/id/bios_version > bios_version.txt
        echo "== EC map from DSDT =="
        grep -n -i -E 'OperationRegion.*(EC|ERAM)|Device \(EC' dsdt.dsl > ec-map.txt 2>&1 || true
        rm -f acpi.dat
        chown -R "''${SUDO_UID:-0}:''${SUDO_GID:-0}" "$recon"
        echo "recon: written to $recon"
        echo "recon: Boot Guard fused/verified is NOT a stop — if ME is v11 (Kaby Lake), deguard bypasses it."
      '';
  };

  # Phase 1: two reads + cmp, or nothing. Chip autodetect first; if flashrom
  # sees several candidates, pass CHIP=W25Q128.V etc.
  # POWER: board fully unpowered (no AC/battery/CMOS/USB-C). Clip VCC must come
  # from an EXTERNAL current-limited 3.3 V, NOT from ESP-Prog — it back-powers
  # +3.3V_ALW_PCH through UZ3 and the PCH fights the bus (garbage reads =>
  # that is why; lower divisor / reseat / check idle current, sch/spi-ec.md 50).
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
        echo "dump: $out — copy to KeePass attachment + own hardware (never a VPS) NOW, before anything else."
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
        # -p sklkbl: without it ifdtool drops the EC region (FLREG8) and emits a bogus "pd" layout line.
        ifdtool -p sklkbl -d "$img" | tee ifd.txt
        ifdtool -p sklkbl -f layout.txt "$img"
        ifdtool -p sklkbl -x "$img"
        # nixpkgs ships the script as me_cleaner.py
        me_cleaner.py -c "$img" | tee me_cleaner-c.txt || true
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
        echo "flash-bios: writing BIOS region only from $img (board=''${BOARD:-xeon}). Ctrl-C within 5s to abort."
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
        # Stock and coreboot runs must share a governor; the previous one comes back on exit.
        gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true)
        set_gov() { for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do printf '%s' "$1" > "$f"; done; }
        if [ -n "$gov" ]; then
          set_gov performance
          trap 'set_gov "$gov"' EXIT
        fi
        n=$(nproc)
        out="$recon/bench-$tag-$(date +%Y%m%d).txt"
        ts="turbostat --quiet --Summary --show Busy%,Bzy_MHz,CoreTmp,PkgTmp,PkgWatt"
        {
          echo "== bench tag=$tag board=''${BOARD:-xeon} $(date -Is)"
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
          # The average hides the turbo burst and the fan catching up; the trace keeps them.
          trace=$(mktemp)
          # shellcheck disable=SC2086
          $ts --interval 10 --num_iterations 60 --header_iterations 60 --out "$trace" &
          tracer=$!
          # shellcheck disable=SC2086
          $ts stress-ng --cpu "$n" --timeout 600 --metrics-brief
          wait "$tracer" || true
          echo "== sustained trace, 10 s samples"
          cat "$trace"
          rm -f "$trace"
          echo "== sensors after"
          sensors
        } 2>&1 | tee "$out"
        chown "''${SUDO_UID:-0}:''${SUDO_GID:-0}" "$out"
        echo "bench: written to $out — commit it (text, small)."
      '';
  };

  # Phase 4.7(b): the M620 has no VBIOS chip; stock keeps the image in an option-ROM FFS
  # beside the other 3520 dGPU SKUs. Picked by PCIR device id, checked against the hash
  # the build pins (packages.nix m620Vbios), then added to the store for requireFile.
  extract-vbios = pkgs.writeShellApplication {
    name = "extract-vbios";
    runtimeInputs = with pkgs; [coreutils uefitool python3 nix];
    text = ''
      img=$(realpath "''${1:?usage: extract-vbios <stock.bin>}")
      want=d44ce6880a32085f3b3ce4adfccd228ad469e22798a9d2ca047c0751255acaaf
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      cp "$img" "$work/bios.bin"
      (cd "$work" && uefiextract bios.bin all >/dev/null) || true
      out="$work/m620-vbios.rom"
      python3 - "$work/bios.bin.dump" "$out" <<'EOF'
      import os, struct, sys
      for root, _, files in os.walk(sys.argv[1]):
          if "body.bin" not in files:
              continue
          d = open(os.path.join(root, "body.bin"), "rb").read()
          i = d.find(b"PCIR\xde\x10\xb4\x13")
          if i < 0:
              continue
          # ROM header 55 AA whose PCIR pointer (+0x18) lands on this PCIR
          for s in range(i - 2, max(-1, i - 0x10000), -1):
              if d[s:s + 2] == b"\x55\xaa" and s + struct.unpack_from("<H", d, s + 0x18)[0] == i:
                  n = struct.unpack_from("<H", d, i + 0x10)[0] * 512
                  open(sys.argv[2], "wb").write(d[s:s + n])
                  sys.exit(0)
      sys.exit("extract-vbios: no PCI image for 10de:13b4 in this dump")
      EOF
      got=$(sha256sum "$out" | cut -d' ' -f1)
      if [ "$got" != "$want" ]; then
        echo "extract-vbios: sha256 $got, build pins $want (different BIOS version?)" >&2
        exit 1
      fi
      nix-store --add-fixed sha256 "$out"
    '';
  };
in {
  wintermute = pkgs.mkShellNoCC {
    name = "wintermute";
    packages = with pkgs; [
      # dump / flash
      flashrom
      flashprog
      cell.packages.inteltool
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
      i2c-tools
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
      extract-vbios
      flash-bios
      bench
      dev
      alejandra
    ];
    shellHook = ''
      export COREBOOT_SRC=${inputs.coreboot}
      export DEGUARD_SRC=${inputs.deguard}
      export FLASHROM_PROGRAMMER="${programmer}"
      echo "wintermute: LA-E152P firmware shell (BOARD=''${BOARD:-xeon}; set BOARD=i7u for the old spare board)"
      echo "  sudo --preserve-env=BOARD recon   phase A: live-system recon -> cells/wintermute/recon/\$BOARD/"
      echo "  dump                              phase 1: 2x SPI read + cmp via ESP-Prog (EXTERNAL 3.3 V to clip!)"
      echo "  inspect <stock.bin>               phase 1.5: ifdtool layout/regions, me_cleaner -c"
      echo "  extract-vbios <stock.bin>         phase 4.7: M620 VBIOS from the dump into the store (build needs it)"
      echo "  flash-bios <coreboot.rom>         phase 3: write BIOS region only (after deguard, phase D)"
      echo "  coreboot src: \$COREBOOT_SRC (read-only; cp -r to work on it)"
      echo "  deguard src:  \$DEGUARD_SRC (read-only; generatedelta.py / finalimage.py for phase D)"
    '';
  };
}
