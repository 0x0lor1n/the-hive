"""Battery charge hold on the Precision 3520, through coreboot's SMM.

Dell's custom start/stop (EC PIDs 0x710..0x712) is synced to the pack, which
ignores it. The hold uses the EC's Peak Shift instead: enable 0x4EA plus one
slot per weekday 0x4EE..0x4F4 set to "on AC, no charging" all day.

The EC mailbox (0x910/0x911) has one owner, the firmware's SMI handler: it
fetches the EC's events from there and would race any OS writer. So the hold
is a SW SMI service (mainboard smihandler.c): request byte to port 0xB3, 0x5A
to 0xB2, result read from 0xB3. A request that reads back unchanged is
firmware without the service; this script then refuses, it never touches the
mailbox itself.

    ec-charge status            mode, hold, BAT0 (no root needed)
    ec-charge limit | full      daemon mode, until reboot (boot = limit)
    ec-charge tick              limit: hold on at >= STOP %, off at <= START %
    ec-charge hold on|off       raw hold
"""
import fcntl
import os
import sys

APM_CNT, APM_STS = 0xB2, 0xB3
APM_CNT_EC_HOLD = 0x5A
HOLD_GET, HOLD_ON, HOLD_OFF, HOLD_DAY = 0xC0, 0xC1, 0xC2, 0xC8
HOLD_RESULT = {0x00: "off", 0x01: "on", 0xE0: "EC timeout", 0xE1: "EC error"}
RUN = "/run/charge-mode"
BAT = "/sys/class/power_supply/BAT0"


def smm(port, request):
    """One APM_CNT_EC_HOLD request on an open /dev/port; returns 0 (off) or 1 (on / done)."""
    port.seek(APM_STS)
    port.write(bytes([request]))
    port.seek(APM_CNT)
    port.write(bytes([APM_CNT_EC_HOLD]))
    port.seek(APM_STS)
    result = port.read(1)[0]
    if result == request:
        sys.exit("firmware has no hold service")
    if result not in (0x00, 0x01):
        sys.exit(f"hold {request:#x}: {HOLD_RESULT.get(result, hex(result))}")
    return result


def hold_get():
    with open("/dev/port", "r+b", buffering=0) as port:
        return smm(port, HOLD_GET) == 1


def hold_set(on):
    with open("/dev/port", "r+b", buffering=0) as port:
        if on:
            for day in range(7):
                smm(port, HOLD_DAY + day)
        smm(port, HOLD_ON if on else HOLD_OFF)
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
    elif on and read(f"{BAT}/status") == "Charging":
        # AC detect re-enables the charger under a standing hold; only an enable edge re-applies it.
        hold_set(False)
        hold_set(True)
        print(f"{cap} %: charging under hold, re-armed")


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
        else:
            sys.exit(__doc__)
    status()


if __name__ == "__main__":
    main()
