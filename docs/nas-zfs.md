# NAS: раскладка ZFS и attic

## Пулы

| Пул | vdev | Где физически | Роль |
|-----|------|---------------|------|
| `rpool` | mirror 2x 256 GB NVMe | ASM1182e, PCIe x1 | ОСь (есть). Остаток места не трогать |
| `fast` | mirror 2x 1 TB NVMe (уже есть) | ASM2824, слоты 1–2 | ВМ, docker, проекты, attic целиком |
| `tank` | raidz2 6x 6 TB | SATA платы | медиа, фото, PII, бэкапы |
| `warm` → `cold` | 1x 18 TB (этап 1) → mirror 2x 18 TB во внешней коробке (этап 3) | SATA → ASM1166 | бэкап |

Слоты 3–4 ASM2824 — пусто. Не SLOG (нет sync-нагрузки, нет PLP), не L2ARC (32 GB RAM хватает). Пригодятся, когда `fast` заполнится: `zpool add fast mirror C D` (stripe of mirrors) или `zpool replace` на 2 TB по одному.

Отказ ASM1182e не ломает данные: rpool импортируется с дисков в любом другом слоте.

## Создание

```bash
zpool create -o ashift=12 \
  -O compression=zstd -O atime=off -O xattr=sa -O acltype=posixacl \
  -O normalization=formD -O mountpoint=none \
  fast mirror /dev/disk/by-id/nvme-1T-A /dev/disk/by-id/nvme-1T-B

zpool create -o ashift=12 \
  -O compression=zstd -O atime=off -O xattr=sa -O acltype=posixacl \
  -O normalization=formD -O mountpoint=none \
  tank raidz2 /dev/disk/by-id/ata-{1..6}
```

Диски — только по `/dev/disk/by-id/`. NixOS: `boot.zfs.extraPools = [ "fast" "tank" ];`

## Датасеты

```bash
zfs create -o mountpoint=/var/lib/atticd -o quota=300G -o compression=off fast/attic
zfs create -o mountpoint=/var/lib/docker fast/docker
zfs create -o mountpoint=/srv/vm         fast/vm
zfs create -o mountpoint=/srv/projects   fast/projects

zfs create -o mountpoint=/tank/media  -o recordsize=1M                      tank/media
zfs create -o mountpoint=/tank/photos                                       tank/photos
zfs create -o mountpoint=/tank/pii -o encryption=on -o keyformat=passphrase tank/pii
zfs create -o mountpoint=none                                               tank/backup
```

| Датасет | Почему так |
|---------|-----------|
| `fast/attic` | БД + chunks вместе, на NVMe: нет spin-up HDD при первом запросе. Chunks уже сжаты → `compression=off`. Квота, чтобы не съел пул |
| `tank/media` | `recordsize=1M` — большие файлы |
| `tank/pii` | нативное шифрование, ключ вводится руками после загрузки |
| `tank/backup` | приёмник `syncoid` для `fast/*` |

Снапшоты: sanoid на `fast/*` (hourly=24, daily=14), syncoid раз в час `fast → tank/backup`. Не бэкапить: `fast/docker` (образы). `fast/attic` бэкапить — БД без chunks и chunks без БД бесполезны.

## attic

```nix
services.atticd = {
  enable = true;
  environmentFile = "/etc/attic.env";   # ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(openssl genrsa 4096 | base64 -w0)
  settings = {
    listen = "[::]:8080";
    database.url = "sqlite:///var/lib/atticd/server.db";
    storage = { type = "local"; path = "/var/lib/atticd/chunks"; };
    chunking = {
      nar-size-threshold = 64 * 1024;
      min-size = 16 * 1024; avg-size = 64 * 1024; max-size = 256 * 1024;
    };
    garbage-collection = {
      interval = "12 hours";
      default-retention-period = "2 months";
    };
  };
};
```

Первичная настройка:

```bash
# на NAS
atticd-atticadm make-token --sub admin --validity 10y \
  --pull '*' --push '*' --create-cache '*' --configure-cache '*'
# на любом клиенте
attic login nas http://nas:8080 <token>
attic cache create main
attic cache info main            # public key → trusted-public-keys
# рабочие токены — ограниченные:
atticd-atticadm make-token --sub m90q --validity 1y --pull main --push main
```

## Клиенты

Топология: десктоп → m90q (remote builder) → attic на NAS. Десктоп тоже с attic в substituters — забирает closure по 10 GbE, а не через ssh с m90q.

```nix
nix.settings = {
  substituters        = [ "http://nas:8080/main" "https://cache.nixos.org" ];
  trusted-public-keys = [ "main:<ключ из attic cache info>" "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
};
```

m90q дополнительно:

```nix
nix.settings = { keep-outputs = true; keep-derivations = true; };
# post-build-hook → attic push main $OUT_PATHS
```

Офлайн-сборка работает только для того, чей build-time closure лежит в кэше. Раз в неделю кроном на m90q:

```bash
drv=$(nix path-info --derivation .#nixosConfigurations.<host>.config.system.build.toplevel)
nix-store -qR --include-outputs "$drv" | attic push main --stdin
```

## Известные компромиссы

- `fast` 1 TB делится между attic (≤300 GB), docker, ВМ и проектами. Следить за `zfs list -o space fast`; при 80% — вторая пара NVMe в слоты 3–4.
- `tank` со spin-down: первое обращение после простоя ~10 с. Всё, что дёргают часто, живёт на `fast`.
