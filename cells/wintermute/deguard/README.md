# deguard delta for precision_3520

BootGuard-bypass ME reconfiguration via `$DEGUARD_SRC` (CVE-2017-5705, ME v11).

`precision_3520/` is the delta between the default and our board's vendor ME
config, produced from our own stock dump:

    python3 "$DEGUARD_SRC/generatedelta.py" \
      --input recon/xeon/stock-xeon-20261029.bin --output <tmp>

`home/secureboot` (zero-FPF prereq) and the optional `home/{amt,fwupdate,pavp}`
are discarded; this tree is the remainder. It carries no serial, UUID or key —
only ME clocking/GPIO/ICC defaults, same class as the deltas already public in
the deguard tree. Board ME: 11.8.65.3590, 5M SKU (ME region ~7 MiB), PCH-H.

The patched ME is built off-tree; donor and output are Intel firmware and stay
out of git:

    python3 "$DEGUARD_SRC/finalimage.py" --delta precision_3520 \
      --version <donor> --pch H --sku 2M --fake-fpfs "$DEGUARD_SRC/data/fpfs/zero" \
      --input <donor> --output me_deguarded.bin
