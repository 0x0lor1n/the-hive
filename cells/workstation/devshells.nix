# Workstation shell: build the playground VM image and boot it under
# QEMU + OVMF (Secure Boot, Setup Mode) + swtpm. Replaces test-vm's justfile
# recipes image / secureboot-reset / vm-run-secureboot-tpm.
#
# Everything here evaluates `globals`, so NIX_CONFIG must carry the same
# nix-plugins extra-builtin the deploy shell loads.
#
# Runtime state lives in .ren/vm/ (gitignored): the raw image, the OVMF
# varstore and the swtpm state. Delete the varstore to re-enroll Secure Boot
# keys; delete swtpm-state after a new image (new pool -> new fingerprint ->
# old sealed credential is meaningless anyway).
{
  inputs,
  cell,
  ...
}: let
  pkgs = inputs.pkgs;
  l = pkgs.lib;

  # Same pin as cells/repo/devshells.nix, same reason (nix-plugins vs nix 2.34).
  nixPlugins = pkgs.nix-plugins.override {
    nixComponents = pkgs.nixVersions.nixComponents_2_31;
  };

  dev = pkgs.writeShellApplication {
    name = "dev";
    runtimeInputs = with pkgs; [git direnv coreutils];
    text = builtins.readFile "${inputs.self.outPath}/nix/dev.sh";
  };

  # Shared prologue: repo root + state dir + host name. Not every script uses
  # every variable, hence the shellcheck exemption.
  prologue = ''
    # shellcheck disable=SC2034
    root=$(git rev-parse --show-toplevel)
    state="$root/.ren/vm"
    mkdir -p "$state"
    host="''${WS_HOST:-vm-zfs}"
    # shellcheck disable=SC2034
    image="$state/$host.raw"
    # shellcheck disable=SC2034
    vars="$state/OVMF_VARS.secureboot.fd"
  '';

  ws-image = pkgs.writeShellApplication {
    name = "ws-image";
    # No `nix` here on purpose: the shell's nix_2_31 must stay first on PATH,
    # or the 2.34 client fails to dlopen the 2.31 nix-plugins.
    runtimeInputs = with pkgs; [git coreutils];
    text =
      prologue
      + ''
        echo "ws-image: a new image is a new pool with a new crypto fingerprint;"
        echo "any previously sealed TPM credential is void. Re-seal inside the VM"
        echo "after the boot dance (see ws-vm-run)."
        out=$(nix build --no-link --print-out-paths "$root#nixosConfigurations.$host.config.system.build.diskoImages")
        rm -f "$image"
        cp -L "$out/main.raw" "$image"
        chmod +w "$image"
        echo "ws-image: $image"
      '';
  };

  ws-secureboot-reset = pkgs.writeShellApplication {
    name = "ws-secureboot-reset";
    runtimeInputs = with pkgs; [git coreutils];
    text =
      prologue
      + ''
        rm -f "$vars"
        rm -rf "$state/swtpm-state"
        echo "ws-secureboot-reset: OVMF varstore and swtpm state removed; next boot starts in Setup Mode."
      '';
  };

  # Lanzaboote enrollment is a 3-boot dance: boot 1 generates keys and writes
  # PK/KEK/db .auth files to the ESP, boot 2's systemd-boot enrolls them (only
  # in Setup Mode -> fresh OVMFFull.fd.variables, NOT .variablesMs), boot 3 is
  # Secure Boot on with signed UKIs. Then, as root inside the VM:
  #   mkzfscreds --devices rpool --print-pcr15         # sanity check
  #   mkdir -p /boot/zfs-unlock
  #   mkzfscreds --devices rpool > /boot/zfs-unlock/rpool.cred
  #   reboot                                            # unlocks silently
  ws-vm-run = pkgs.writeShellApplication {
    name = "ws-vm-run";
    runtimeInputs = with pkgs; [git coreutils procps qemu swtpm];
    text =
      prologue
      + ''
        [ -f "$image" ] || { echo "ws-vm-run: no image at $image; run ws-image first" >&2; exit 1; }

        if [ ! -f "$vars" ]; then
          cp ${pkgs.OVMFFull.fd.variables} "$vars"
          chmod +w "$vars"
        fi

        sock="$state/swtpm-socket"
        tpmstate="$state/swtpm-state"
        mkdir -p "$tpmstate"
        pkill -f "swtpm.*$sock" 2>/dev/null || true
        rm -f "$sock"
        # startup-clear zeroes the PCRs at process start; the firmware then
        # extends them as it boots.
        swtpm socket --tpm2 --tpmstate "dir=$tpmstate" \
          --ctrl "type=unixio,path=$sock" --flags startup-clear --daemon
        trap 'pkill -f "swtpm.*$sock" 2>/dev/null || true' EXIT INT TERM
        for _ in $(seq 1 20); do [ -S "$sock" ] && break; sleep 0.2; done
        [ -S "$sock" ] || { echo "swtpm: control socket did not appear" >&2; exit 1; }

        # q35 + SMM + secure pflash is what makes OVMF honour Secure Boot;
        # SSH is forwarded to :2222, the repo is shared over 9p as `share`.
        exec qemu-system-x86_64 \
          -enable-kvm \
          -machine q35,smm=on \
          -global driver=cfi.pflash01,property=secure,value=on \
          -global ICH9-LPC.disable_s3=1 \
          -cpu host -smp 4 -m 4096 \
          -drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMFFull.fd.firmware} \
          -drive if=pflash,format=raw,unit=1,file="$vars" \
          -drive if=virtio,format=raw,file="$image" \
          -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net0 \
          -chardev "socket,id=chrtpm,path=$sock" \
          -tpmdev emulator,id=tpm0,chardev=chrtpm \
          -device tpm-tis,tpmdev=tpm0 \
          -virtfs "local,path=$root,mount_tag=share,security_model=none,id=share" \
          -nographic -serial mon:stdio
      '';
  };
in {
  workstation = pkgs.mkShellNoCC {
    name = "workstation";
    packages = [
      pkgs.nixVersions.nix_2_31
      pkgs.rage
      pkgs.age-plugin-tpm
      pkgs.sbctl
      ws-image
      ws-secureboot-reset
      ws-vm-run
      dev
      pkgs.alejandra
    ];

    shellHook = ''
      export NIX_CONFIG="
        plugin-files = ${nixPlugins}/lib/nix/plugins
        extra-builtins-file = ${inputs.self.outPath}/nix/extra-builtins.nix
      "
      echo "workstation: WS_HOST=''${WS_HOST:-vm-zfs}; state in .ren/vm/"
      echo "  ws-image             build the disko image"
      echo "  ws-secureboot-reset  fresh OVMF varstore (Setup Mode) + wipe swtpm"
      echo "  ws-vm-run            boot it: OVMF Secure Boot + swtpm, ssh -p 2222"
      echo "  dev                  back to the deploy shell"
    '';
  };
}
