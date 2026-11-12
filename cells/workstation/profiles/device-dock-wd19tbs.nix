# Dell WD19TBS: one dock that moves between both laptops. The TB domain runs
# at security=user (penrose's coreboot leaves TB3 at SL1, elster's firmware
# too): the dock's USB/Ethernet sit behind a PCIe tunnel that stays down
# until authorised; PD charging and DP alt mode work without it.
#
# Authorise this one dock by unique_id instead of boltd's mutable enrollment
# store, so the trust lives in the repo. The rule fires on `add`: after a
# switch, replug the dock. An authorised device DMAs wherever the IOMMU lets
# it, so each host keeps VT-d on (check domain0/iommu_dma_protection).
#
# The same dock shows a different unique_id per host. elster's USB4 router
# reads the dock's real UUID; penrose's TB3 (Alpine Ridge) host gets none, so
# the kernel builds one from the 64-bit DROM uid padded with ffff. Both are
# stable for this dock.
{
  inputs,
  cell,
}: {lib, ...}: let
  ids = [
    "c6030000-0042-441e-8364-f08548031a02" # elster (USB4)
    "00a4014d-065f-d400-ffff-ffffffffffff" # penrose (TB3)
  ];
  rule = id: ''ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{unique_id}=="${id}", ATTR{authorized}=="0", ATTR{authorized}="1"'';
in {
  services.udev.extraRules = lib.concatMapStringsSep "\n" rule ids + "\n";
}
