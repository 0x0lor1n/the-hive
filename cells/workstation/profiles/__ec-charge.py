"""Battery charge hold over the Precision 3520 EC mailbox (0x910/0x911).

Mailbox cmd 0x1C is the EC's property interface (Wilco protocol, same PIDs
as Linux wilco-charger.c): index 0x12 op (0 get, 1 set), 0x13..0x16 PID LE,
0x17 length, 0x18.. data, 0x11 status.

Dell's custom start/stop (PIDs 0x710..0x712) is synced to the pack, which
ignores it. The hold uses Peak Shift instead: enable 0x4EA plus one slot per
weekday 0x4EE..0x4F4 [start, end, charge-start, ?] (hour << 2 | quarter).
00:00 / 00:00 / 23:45 keeps the EC in "on AC, no charging" all day.

    ec-charge status            mode, hold, BAT0 (no root needed)
    ec-charge limit | full      daemon mode, until reboot (boot = limit)
    ec-charge tick              limit: hold on at >= STOP %, off at <= START %
    ec-charge hold on|off       raw hold
    ec-charge peak              read Peak Shift PIDs
    ec-charge dell-mode [1..5]  Dell charge mode (4 adaptive = stock)
"""
import fcntl
import os
import sys

IDX, DATA = 0x910, 0x911
CMD_PROP = 0x1C
PID_DELL_MODE = 0x710
PID_PS_EN, PID_PS_FLOOR = 0x4EA, 0x4EB
PID_PS_DAYS = range(0x4EE, 0x4F5)
RUN = "/run/charge-mode"
BAT = "/sys/class/power_supply/BAT0"


def port_wr(p, v):
    with open("/dev/port", "r+b", buffering=0) as f:
        f.seek(p)
        f.write(bytes([v]))


def port_rd(p):
    with open("/dev/port", "rb", buffering=0) as f:
        f.seek(p)
        return f.read(1)[0]


def mb_wr(i, v):
    port_wr(IDX, i)
    port_wr(DATA, v)


def mb_rd(i):
    port_wr(IDX, i)
    return port_rd(DATA)


def prop(op, pid, data):
    mb_wr(0x12, op)
    for n in range(4):
        mb_wr(0x13 + n, (pid >> (8 * n)) & 0xFF)
    mb_wr(0x17, len(data))
    for n, b in enumerate(data):
        mb_wr(0x18 + n, b)
    port_wr(IDX, 0)
    port_wr(DATA, CMD_PROP)
    for _ in range(100000):
        port_wr(IDX, 0)
        if port_rd(DATA) == 0:
            break
    else:
        sys.exit(f"cmd 0x1C timeout (pid {pid:#x})")
    status = mb_rd(0x11)
    if status:
        sys.exit(f"pid {pid:#x}: EC status {status:#x}")
    return bytes(mb_rd(0x18 + i) for i in range(min(mb_rd(0x17), 4)))


def get1(pid):
    return prop(0, pid, [0])[0]


def hold_get():
    return get1(PID_PS_EN) == 1


def hold_set(on):
    if on:
        for pid in PID_PS_DAYS:
            slot = prop(0, pid, [0, 0, 0, 0])
            prop(1, pid, [0x00, 0x00, 0x5F, slot[3]])
    prop(1, PID_PS_EN, [1 if on else 0])
    record("hold", "on" if on else "off")


def record(name, value):
    os.makedirs(RUN, exist_ok=True)
    with open(f"{RUN}/{name}", "w") as f:
        f.write(value + "\n")


def read(path, default="?"):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def mode():
    return read(f"{RUN}/mode", "limit")


def tick():
    if mode() != "limit" or not os.path.exists(BAT):
        return
    start, stop = int(os.environ["CHARGE_START"]), int(os.environ["CHARGE_STOP"])
    cap, on = int(read(f"{BAT}/capacity")), hold_get()
    record("hold", "on" if on else "off")
    if cap >= stop and not on:
        hold_set(True)
        print(f"{cap} % >= {stop} %: hold on")
    elif cap <= start and on:
        hold_set(False)
        print(f"{cap} % <= {start} %: hold off")


def hhmm(t):
    return f"{t >> 2:02d}:{(t & 3) * 15:02d}"


def peak():
    for pid in (PID_PS_EN, PID_PS_FLOOR, *PID_PS_DAYS):
        data = prop(0, pid, [0, 0, 0, 0])
        times = " / ".join(hhmm(t) for t in data[:3]) if len(data) == 4 else ""
        print(f"pid {pid:#06x}  {data.hex(' ')}  {times}")


def status():
    print(f"mode {mode()}  hold {read(f'{RUN}/hold')}  "
          f"BAT0 {read(f'{BAT}/capacity')} % {read(f'{BAT}/status')}")


def main():
    args = sys.argv[1:] or ["status"]
    if args == ["status"]:
        status()
        return
    os.makedirs(RUN, exist_ok=True)
    with open(f"{RUN}/lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args in (["limit"], ["full"]):
            record("mode", args[0])
            if args[0] == "full":
                hold_set(False)
            else:
                tick()
        elif args == ["tick"]:
            tick()
            return
        elif args[0] == "hold" and args[1:] in (["on"], ["off"]):
            hold_set(args[1] == "on")
        elif args == ["peak"]:
            peak()
        elif args == ["dell-mode"]:
            print(get1(PID_DELL_MODE))
        elif args[0] == "dell-mode" and args[1:] in [[str(n)] for n in range(1, 6)]:
            prop(1, PID_DELL_MODE, [int(args[1])])
            print(get1(PID_DELL_MODE))
        else:
            sys.exit(__doc__)
    status()


if __name__ == "__main__":
    main()
