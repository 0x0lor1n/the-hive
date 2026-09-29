# NAS — оборудование

## Сборка

| # | Компонент | Модель | Цена | Где куплено |
|---|-----------|--------|------|-------------|
| 1 | Материнская плата | MSI B250M PRO-VD (mATX; 1x PCIe 3.0 x16, 2x PCIe x1, 1x M.2, 6x SATA, 2x DDR4) | CHF 57.19 | AliExpress |
| 2 | Процессор | Intel Core i5-6600T (35 W) | CHF 32.59 | AliExpress |
| 3 | Кулер CPU | Xilence I250PWM (70 mm) | CHF 12.70 | Galaxus.ch |
| 4 | Память | Corsair Vengeance 2x16 GB DDR4-2666 CL16 | CHF 30 | Ricardo.ch (~год назад) |
| 5 | NVMe boot #1 | Samsung 256 GB 2230 (с адаптером) | $66.80 | AliExpress |
| 6 | NVMe boot #2 | 256 GB | — | уже есть, из ноутбука 2017 г. (penrose) |
| 7 | Адаптер boot | PCIe x1 → 2x M.2 (ASM1182e, LT0534) | CHF 10.09 | AliExpress |
| 8 | NVMe data | 2x 1 TB | — | уже есть |
| 9 | Свитч NVMe | PCIe x16 → 4x M.2 (ASM2824 «Split-Free», Gen3 x8) | ~CHF 73 | AliExpress |
| 10 | HDD `tank` | 3x Seagate IronWolf 6 TB (CMR) | 3x ~CHF 201 | AliExpress |
| 11 | HDD `backup` #1 | Seagate Barracuda 6 TB (ST6000DM003, SMR) | — | уже есть, из внешнего Porsche Design |
| 12 | HDD `backup` #2 | Seagate Barracuda 6 TB (ST6000DM003, SMR) | CHF 139.12 | Amazon (~год назад) |
| 13 | Сеть 10G | M.2 → SFP+ (Intel JL82599EN, «X520-DA1»), требует SATA-питание | CHF 31.39 | AliExpress |
| 14 | Кабель SFP+ | 3 м | $13.52 | AliExpress |
| 15 | Блок питания | be quiet! Pure Power 12 M 550 W (80+ Gold, ATX 3.0, 5x SATA + 2x Molex, 160 мм) | CHF 68.45 | Galaxus.ch (б/у) |
| 16 | Переходник питания | Molex → SATA (для M.2 → SFP+; 6-го SATA у БП нет) | — | уже есть |
| 17 | Кабели SATA data | 5 шт (3 IronWolf + 2 Barracuda) | CHF 6.80 | AliExpress |
| 18 | Рамка 3x 3.5" | Железная рамка на 3 этажа, ставится на дно основной камеры; под 2x Barracuda `backup` (через этаж) | CHF 10.59 | AliExpress |
| 19 | Сплиттер вентиляторов | 4-pin 1→2 на SYS_FAN (передний 200 мм + задний 120 мм) | ~CHF 2 | AliExpress |
| 20 | Корпус | Thermaltake Divider 200 TG (mATX, 3x 3.5" + 3x 2.5") | CHF 75 | Ricardo.ch |
| 21 | Переходник видео | VGA → HDMI | CHF 7.60 | Amazon |

**Итого:** ≈ CHF 1 223 + $80 ≈ **CHF 1 290** (без «уже есть»; цены с ~ — оценка).

## Раскладка

| Пул | Диски | Роль |
|-----|-------|------|
| `rpool` | 2x NVMe 256 GB, mirror (PCIe x1 → ASM1182e) | ОС |
| `fast` | 2x NVMe 1 TB, mirror (ASM2824, слоты 1–2) | горячие данные, attic, docker, VM |
| `tank` | 3x IronWolf 6 TB, RAIDZ1, ~11 TiB usable | основное хранилище |
| `backup` | 2x Barracuda SMR 6 TB, два отдельных пула по 6 TB | warm-бэкап `tank` |

SMR в RAID не участвуют: backup-таргет — подходящая для них роль, `zfs send | recv` пишет последовательно, resilver'а нет. Два отдельных пула вместо stripe — смерть старой Barracuda не тянет вторую. На бэкапе `recordsize=1M`, `compression=zstd`, заполнение ≤ 80 %. По таймеру ночью: `zpool import` → `zfs send -I` → `zpool export`; между сеансами диски спят, пул не виден хосту. Retention на бэкапе не длиннее, чем на `tank`; медиа, которое можно скачать заново, не бэкапить. Детали ZFS: `nas-zfs.md`.

Занятость: PCIe x16 1/1, PCIe x1 1/2, M.2 1/1, SATA 5/6, DIMM 2/2, отсеки 3.5" 5/6, NVMe на ASM2824 2/4.

## Возможности расширения

- **1x SATA** на плате — 4-й IronWolf в `tank` через raidz expansion (ZFS ≥ 2.3, ~16 TiB; старые данные остаются со старой parity, пока не перепишутся) или ещё один бэкапный диск.
- **2x M.2** на ASM2824 — расширение `fast`, когда заполнится.
- **1x PCIe x1** — ASM1166 (6x SATA) для дисков сверх портов платы, либо внешняя коробка под cold-бэкап (18 TB, своё питание, подключается изредка).
