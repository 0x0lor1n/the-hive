# Tools for the LA-E152P port

What runs on an EC image, on a live board, or on a bench log. Nothing here is
called by the build; the devshell wraps the commands, the rest is run by path.

## Layout

    ec/          EC image tools: the two digests, the power-limit and fan
                 tables, the region slice build
    lib/         the board file reader and the EC header gate, shared
    boards/      one data file per board, `boards/$BOARD.toml`

A board is selected by `BOARD` the way `recon/$BOARD/` already is (default
`xeon`). A `BOARD` with no data file is a refusal. Only `xeon` has one.

The live-board probes (EC mailbox, dock, charge hold), the thermal log
readers and their harnesses still live outside the checkout; they move here
under the same contract, one at a time, with a harness each.

## Two classes

command
: On the devshell `PATH` as a `writeShellApplication`; its dependencies are
  its `runtimeInputs`, never looked up on the host. It has a harness, and
  its argv and output are kept stable: another tool may parse them.

probe
: A file run by path (`python3 scripts/<dir>/x.py`). Same contract, no
  harness, no stability promise; a probe that writes to the board says so in
  its first line.

## Contract

Every command and probe:

- No arguments, or arguments it cannot parse: usage on stderr, exit 2.
- A refusal comes before anything is touched, as one line
  `<tool>: not started, <why>` on stderr, exit 1. "Touched" includes a copy
  into an archive and a temp dir; the usual order is check every input, then
  write.
- Once it has written or run something, a failure is `<tool>: STOPPED: <why>`
  as the last line, exit 1, and the line says what was left behind.
- Success ends in `<tool>: OK <summary>` (a write or a run) or
  `<tool>: done, <summary>` (a read with side effects, such as a log). A
  query whose stdout is its result (`ec-tables pl-get`, `ec-tables fan`)
  prints the result and nothing else; its exit code is the verdict.
- Result lines carry the conditions they were measured under: AC or
  battery, the firmware build, the flash number.
- The header (docstring or usage) says what the tool reads and what it
  writes, one line each.
- Root only where a device needs it (`/dev/port`, MSRs, flashrom); a tool
  that needs it refuses without it, with the `sudo --preserve-env=...` line
  to run.
- Machine-specific values are arguments with no default: undervolt mV, the
  charge-hold lock and timer, the log directory. Nothing in a tool body
  names a host, an account, a LAN address, a store path or `/tmp`.
- A Python tool sets `sys.dont_write_bytecode`: the devshell copies
  `scripts/` into the store, and a `__pycache__` in the checkout would go
  with it.

## Board gate

A tool trusts nothing about the board it is given; it checks, and an unknown
board is a refusal, not a guess.

An image tool checks the EC header digest (SHA-256 of the `PHCM` header,
`0x1000..0x1040` of the region) against the board file. The payload digest
(`0x1080..0x27240`) is matched against the board file's known list: stock,
the fan patches, the 45 W patch, each with the flash it went on. `ec-tables`
edits an image whose payload is mid-change and gates on the header only;
`ec-digest check` names the payload it recognises.

A live tool (none in the checkout yet) checks `/sys/class/dmi/id/product_name`
and then the EC canary: a mailbox peek of one address whose value the board
file holds. A wrong canary means the peek command is not the one this EC
answers, and nothing more is sent.

The gate and the file reader live in `lib/board.py`; a tool body holds no
address, port or digest. A shell command gets its values the same way:
`python3 lib/board.py <tool> <key>..` prints one per line, a list
comma-joined, `ec.body.1` one element.

## The board file

`boards/<name>.toml`, everything the tools know about one board:

    name, dmi_product
    [ec]   header_sha256, region, size, banks, header, body, load_va,
           pl_ptrs, fan_ptrs, ac_tables, k1_130w, rows_130w, quiet_cpu,
           canary = {va, value}, mailbox = {idx, data}
    [ec.payloads]   sha256 = "what, flashed when"

## Harnesses

A command's harness runs it against copies of real dumps and slices in a
temp dir, drives every refusal, and checks that a refusal left no file
behind and that the archive it reads is unchanged. The `ec-pl-build` harness
(42 cases, covers the two tools under it) is still in the owner's state dir;
it lands under `tests/` with the next command.

## Tools

| tool | class | reads | writes | root |
| --- | --- | --- | --- | --- |
| `ec-digest` | command | an EC region slice or full dump | the payload digest in place (`fix`) | no |
| `ec-tables` | command | an EC region slice or full dump | table rows / fan steps in place (`pl-set`, `fan-set`, `patch`) | no |
| `ec-pl-build` | command | the clip session's dump, the last slice written | `recon/$BOARD/ec-pre<n>.bin`, `ec-<n>-pl<W>.bin`, copies in the archive | no |
