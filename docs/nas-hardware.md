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
| `rpool` | 1x NVMe 256 GB (ASM2824) | ОС |
| `fast` | 3x NVMe 1 TB, RAIDZ1, ~1.8 TB usable (ASM2824) | состояние сервисов, attic, docker, VM |
| `tank` | 3x IronWolf 6 TB, RAIDZ1, ~11 TiB usable | основное хранилище |
| `backup` | 2x Barracuda SMR 6 TB, два отдельных пула по 6 TB | warm-бэкап `tank` |

SMR в RAID не участвуют: backup-таргет — подходящая для них роль, `zfs send | recv` пишет последовательно, resilver'а нет. Два отдельных пула вместо stripe — смерть старой Barracuda не тянет вторую. На бэкапе `recordsize=1M`, `compression=zstd`, заполнение ≤ 80 %. По таймеру ночью: `zpool import` → `zfs send -I` → `zpool export`; между сеансами диски спят, пул не виден хосту. Retention на бэкапе не длиннее, чем на `tank`; медиа, которое можно скачать заново, не бэкапить. Детали ZFS: `nas-zfs.md`.

Занятость: PCIe x16 1/1, PCIe x1 1/2, M.2 1/1, SATA 5/6, DIMM 2/2, отсеки 3.5" 5/6, NVMe на ASM2824 4/4.

## Модель отказов и уровни резерва

RAIDZ1 переживает один диск. Второй диск во время resilver'а — главный аргумент против RAIDZ1 на 6 дисках; warm-бэкап здесь компенсирующий контроль, а не «на всякий случай».

| Событие | Что спасает | Что теряешь |
|---|---|---|
| 1 диск в `tank` | resilver | ничего, пул degraded, но живой |
| 2-й диск во время resilver | warm backup | данные после последнего `zfs send` |
| Диск в warm backup | `tank` | ничего, пересылаешь заново |
| Умерло всё разом (БП, молния, ransomware, пожар) | cold backup | по RPO cold |

**Warm** — копия, а не источник, поэтому без parity: смерть диска резерва = повторный `zfs send` (~30 TB при 10 Gbit ≈ 8 ч), не потеря. Stripe из неравных дисков допустим — при смерти любого умирает весь резерв, для warm это приемлемый сценарий.

Процедуры:
- `zfs send -I` по таймеру ежесуточно → RPO warm = сутки.
- Вылетел диск в `tank` → сначала последний `zfs send` на warm (пул degraded, но читаемый), потом `zpool replace`. В окно resilver'а входим с RPO = 0. Во время resilver'а репликацию не гонять.
- `zpool scrub` warm-пулов раз в месяц: у stripe избыточности нет, scrub ничего не чинит, но показывает битые блоки, пока `tank` жив и датасет можно переслать.
- Один раз прогнать restore хотя бы одного датасета обратно, чтобы путь был проверен. Полный restore 30 TB со stripe SMR ≈ 20–30 ч, NAS в это время не рабочий.

**Cold** сейчас частичный: документы, базы KeePass и экспорт 2FA — на Kingston IronKey; фотоархив — на внешнем HDD. Cold-копия всего массива и ECC-память — задачи следующей NAS-сборки, не этой. Cold закрывает электрику, ransomware и ошибку оператора только если лежит вне NAS; пожар и кражу — только если в другом здании.

**Вектор:** `tank` → 6x 6 TB CMR RAIDZ1 (30 TB), warm → 18 TB CMR + 2x 6 TB SMR (30 TB) во внешней коробке через PCIe x1. Раскладка: на 18 TB CMR — attic, VM, документы, фото (много мелких инкрементов); на SMR — медиатека (большие последовательные файлы). Резерв без запаса, поэтому `tank` не выше 80 % (~22 TiB), ~5 TiB под историю снапшотов. Дальше SMR меняются на второй 18 TB → 36 TB.

## Возможности расширения

- **1x SATA** на плате — 4-й IronWolf в `tank` через raidz expansion (ZFS ≥ 2.3, ~16 TiB; старые данные остаются со старой parity, пока не перепишутся) или ещё один бэкапный диск.
- M.2 на ASM2824 заняты все 4; `fast` растёт только заменой дисков на большие.
- **1x PCIe x1** — ASM1166 (6x SATA, поддерживает порт-мультипликатор) + планка eSATA → внешняя коробка под warm-бэкап (18 TB + 2x 6 TB SMR, своё питание). Коробка выключена → cold, включена и `zpool import` → warm.

## Приложение: время восстановления массива после замены диска

Диапазоны из отчётов на форумах Synology и TrueNAS плюс расчёт по средней скорости HDD (~140 MB/s для 6 TB CMR). Условия: массив в простое, диски CMR, RAIDZ1 заполнен на ~70 %.

| Массив | RAID5 (mdadm, Synology) | SHR-1 | RAIDZ1 (ZFS) |
|---|---|---|---|
| 6x 6 TB | 10–16 ч | 10–18 ч | 5–9 ч |
| 6x 10 TB | 16–28 ч | 18–30 ч | 9–15 ч |
| 6x 16 TB | 24–40 ч | 26–45 ч | 14–24 ч |

**Легенда:**
- SMR-диски → ×3–5.
- Массив под нагрузкой во время ребилда → ×1.5.
- RAID5/SHR читают диск целиком, время не зависит от заполнения. RAIDZ1 ресильверит только занятые блоки: пустой пул — минуты, полный — как RAID5.
- DSM по умолчанию ограничивает скорость ребилда («Balanced»/«Low impact»); в режиме «Low impact» 6 TB растягивается до 2–3 суток.
- Ошибка чтения на живом диске во время ребилда: mdadm выбрасывает диск, массив падает; ZFS помечает один файл повреждённым и продолжает.

**Наш `tank`** (3x 6 TB, ~70 %): ~4 TB данных на диск, ресильвер 6–8 ч.

Источники:
- https://sraidcalculator.com/blog/synology-nas-rebuild-time
- https://community.synology.com/enu/forum/1/post/140325
- https://forums.truenas.com/t/long-resilver-time-tl-dr/29218
- https://www.truenas.com/community/threads/drive-size-and-resilvering-times.95917
- https://louwrentius.com/zfs-resilver-performance-of-various-raid-schemas.html
