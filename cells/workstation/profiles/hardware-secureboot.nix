# Secure Boot via Lanzaboote: replaces systemd-boot with a NixOS-aware
# stub loader that bundles + signs each generation as a UKI via sbctl.
# Keys live in /var/lib/sbctl (persisted by impermanence).
#
# Firmware enrollment needs two boots and Setup Mode: boot 1 writes
# PK/KEK/db *.auth files to /boot/loader/keys/auto/; boot 2's
# systemd-boot enrolls them into firmware variables, but only if
# firmware is in Setup Mode. We get Setup Mode by booting with a fresh
# `OVMFFull.fd.variables` template (not `.variablesMs`, which has MS
# keys pre-enrolled) — see the `vm-run-secureboot` justfile recipe for
# the matching QEMU SMM flags. On bare metal this is the physical UEFI
# Setup Mode menu instead; this is Lanzaboote's own canonical workflow.
#
# `lib` isn't injected by the profiles/default.nix loader (only inputs+cell), hence
# inputs.nixpkgs.lib below. Reference: patrick/nix-config's secureboot.nix.
{
  inputs,
  cell,
}: let
  lib = inputs.nixpkgs.lib;
in {
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
    # `sbctl status` / `sbctl verify` on the running host.
    ({pkgs, ...}: {environment.systemPackages = [pkgs.sbctl];})
  ];

  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";

    # Runs `sbctl create-keys` automatically on first boot if
    # /var/lib/sbctl/keys is empty, and allows unsigned boot until it does.
    autoGenerateKeys.enable = true;

    autoEnrollKeys = {
      enable = true;

      # Required on real hardware — some signed option ROMs depend on
      # Microsoft's trust anchors. No harm on the VM either way.
      includeMicrosoftKeys = true;

      # Manual reboot so the operator can verify the enrollment
      # transition between boot 1 and boot 2 (see header).
      autoReboot = false;
    };
  };

  # mkDefault, not a plain value: whether firmware can take NVRAM writes is
  # a HARDWARE fact, so the hardware profile owns it (hardware-laptop.nix
  # sets true). false is the safe default -- image builds must never touch
  # the build host's NVRAM.
  #
  # This was a plain `false` and collided with hardware-laptop's `true`.
  # The collision did not fail the build, because lanzaboote replaces
  # systemd-boot and nothing in the closure reads the option -- it would
  # have sat latent until something did.
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault false;

  # The private signing keys must outlive the @blank rollback, or every
  # rebuild generates a new key that no longer matches the PK/KEK/db the
  # firmware enrolled.
  #
  # Declared HERE rather than in storage-impermanence.nix (iter 11): the
  # profile that owns the state owns its persistence. This module is applied
  # via flake.nix's soil, and only to targets that also get
  # storage-impermanence, so the option it merges into is always declared.
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/sbctl";
      mode = "0700";
    }
  ];

  # Upstream's generate-sb-keys unit skips key generation once
  # pkiBundle *exists* — but impermanence creates /var/lib/sbctl as a
  # bind-mount target before keys are ever generated, so that's always
  # true. Check for a file Lanzaboote actually produces instead, so the
  # unit still runs exactly once.
  systemd.services.generate-sb-keys.unitConfig.ConditionPathExists =
    lib.mkForce "!/var/lib/sbctl/keys/db/db.pem";
}
