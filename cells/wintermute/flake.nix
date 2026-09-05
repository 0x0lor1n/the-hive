{
  # wintermute: firmware work for the Dell Latitude 5580 / Precision 3520
  # (LA-E152P). The AI that removes the restraints its makers fused in; here:
  # stock BIOS -> coreboot, ME neutered, own Secure Boot keys.
  # Tooling only: nothing here is read by cells/server or cells/workstation,
  # so a cell input cannot leak into a host's evaluation.
  # Plan: .hermes/state/coreboot-5580.md
  inputs = {
    # Pinned upstream coreboot; the board port lives in-tree under
    # mainboard/dell/latitude_5580 once Phase 1 starts.
    coreboot = {
      url = "git+https://review.coreboot.org/coreboot.git?submodules=1";
      flake = false;
    };
  };
  outputs = i: i;
}
