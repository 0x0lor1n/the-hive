# NAS — сравнение с Synology

Самосбор (см. `nas-hardware.md`, `nas-zfs.md`) против ближайшего аналога — **Synology DS1525+**
(5 bay, Ryzen V1500B 4C/8T, 8 GB ECC, 2× M.2 NVMe, PCIe-слот под 10GbE).
Выбран потому, что у нас 5 HDD + NVMe-пул + 10 GbE SFP+.

Цены — digitec / toppreise, сентябрь 2026.

## Цена

| | Самосбор | Synology DS1525+ |
|---|---|---|
| Корпус / плата / CPU / RAM | MSI B250M PRO-VD + i5-6600T + 32 GB DDR4 + Divider 200 — ~CHF 130 (б/у + Ali) | DS1525+ (8 GB ECC) — CHF 703–729 |
| 10 GbE SFP+ | M.2 → SFP+ (Intel 82599) — ~CHF 35 | E10G21-F2 (dual SFP+, PCIe x8) — ~CHF 250; RJ45-вариант E10G22-T1-Mini — CHF 115 |
| HDD 5× 6 TB | 3× IronWolf + 2× Barracuda — ~CHF 550 | HAT3300-6T — CHF 115–127 × 5 ≈ CHF 600, либо свои диски |
| NVMe 2× 1 TB (пул) | Samsung PM9A1 — есть | SNV3410-800G — CHF 349 × 2 ≈ CHF 700 (в пул идёт только Synology NVMe) |
| NVMe 2× 256 GB (ОС) | ~CHF 66 + б/у | не нужно, DSM живёт на всех дисках |
| RAM до 32 GB | входит | D4ES02-16G × 2 — ~CHF 300 (сторонняя ~100, «unsupported») |
| БП / PCIe-свитч / кабели | Pure Power 12 M 550 + ASM2824 + кабели — ~CHF 150 | входит |
| **Итого** | **~CHF 1 300** | **~CHF 2 500–2 900** новый; ~CHF 1 900 при переиспользовании своих HDD |

Разница ~2×. Synology-цена — без отдельного резервного пула: 5 bay, либо SHR на всех, либо 3+2 как у нас.

## Функционал

| Критерий | Самосбор (NixOS + ZFS) | DS1525+ (DSM 7.3, btrfs + mdadm) |
|---|---|---|
| Основной пул | RAIDZ1 3× 6 TB CMR = 12 TB; чексуммы на данных и parity, scrub, zstd | SHR/RAID5 = 12 TB; btrfs-чексуммы поверх mdadm — bit-rot видит, самолечение ограничено (raid-слой не знает о чексуммах) |
| Резерв 12 TB | Отдельный пул 2× SMR, `zfs send/recv` инкрементально, spin-down | Второй volume + Hyper Backup / Snapshot Replication (btrfs send), либо USB/eSATA-коробка |
| NVMe 2× 1 TB | Свой пул (fast / attic / docker), любые диски | В пул — только Synology SNV. Сторонние NVMe — только кэш |
| 10 GbE SFP+ | Есть, ~CHF 35 | Есть, +CHF 250, карта Synology-only |
| ОС | Mirror 2× NVMe, декларативно, откат через `nixos-rebuild`. Не зависит от USB | DSM-раздел зеркалится на все диски — по отказоустойчивости ОСи лучше. Откат — только бэкап конфига |
| Nix-cache (attic) | Нативно, systemd-сервис, tiering SSD → HDD | Container Manager (Docker) — поднимется, tiering руками |
| CPU / медиа | i5-6600T 4C/4T, QuickSync → аппаратный 4K-транскод | V1500B 4C/8T без iGPU — транскод только софтом, 4K не потянет |
| RAM | 32 GB non-ECC | 8 GB ECC (до 32 ECC) |
| Расширение | +1 SATA, 2× M.2 на свитче, PCIe x1, до 8 SATA через ASM1166 | DX525 expansion unit — ~CHF 500 за 5 bay |
| Потребление | ~50–55 W idle (оценка) | ~40 W в работе / ~17 W HDD hibernation |
| Шум / размер | mATX-корпус, кулеры настраиваются | Компактный, тихий из коробки |
| Софт | Всё руками, ровно то, что нужно | DSM: Photos, Drive, Surveillance, Hyper Backup, Snapshot Replication — за 10 минут |
| Поддержка | Сам + NixOS-комьюнити | 3 года гарантии + вендор |
| Vendor lock | Нет, диски читаются на любом Linux с ZFS | SHR читается на Linux (mdadm + lvm + btrfs), остальное — DSM-only |

## Итог

- **Деньги**: самосбор ~2× дешевле при большем RAM, лучшем CPU для медиа и более гибком расширении.
- **Целостность данных**: ZFS сильнее btrfs + mdadm, особенно scrub на RAIDZ1.
- **Где Synology лучше**: ECC, DSM на всех дисках (отказоустойчивость ОСи), энергопотребление, готовый софт, гарантия.
- **Наш риск**: спалённые USB на матери, б/у железо, PCIe x1 через адаптер ASM1182e. Закрыт NVMe-зеркалом ОСи и ZFS.

Под наши требования (SFP+, NVMe-пул на своих дисках, nix-cache, 4K) Synology даже за 2× цену даёт компромиссы —
NVMe-пул только на их SSD и без QuickSync. Самосбор оправдан.
