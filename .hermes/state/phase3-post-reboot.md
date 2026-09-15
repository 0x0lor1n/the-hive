# phase 3 — post-reboot checklist (penrose)

Plan: `.hermes/state/port-jarvis-home.md` → «phase 3 — deploy to penrose».
Applied before the reboot: toplevel with 3c61b9c (direnv whitelist in /etc/direnv,
Entra in `networkmanager`). Run as-is, paste the full output back into the hermes session.

Legend: `# HANDS:` = a manual action, everything else is copy-paste.

## A. as the Entra user, in foot

```bash
# ===== 0. who / where
id -nG | tr ' ' '\n' | grep -E '^(hive|networkmanager|video|audio|input)$'
echo "HOME=$HOME SHELL=$SHELL TERM=$TERM"; [ -n "$TMUX" ] && echo IN_TMUX=yes || echo IN_TMUX=NO

# ===== 1. zsh: cold start, instant prompt, gitstatus, histdb, zoxide (persisted)
systemctl --user is-active home-manager-entra.service
systemctl --user status home-manager-entra.service --no-pager | sed -n '1,8p'
time zsh -ic exit
ls -la ~/.cache/p10k-instant-prompt-*.zsh
zsh -ic 'sleep 1; typeset -p GITSTATUS_DAEMON_PID_POWERLEVEL9K; pgrep -u $UID -l gitstatusd' 2>&1 | grep -v '^$'
readlink ~/.config/zsh/config.zsh ~/.config/zsh/.p10k.zsh
cd /srv/the-hive; cd ~
ls -la ~/.local/share/zsh/ ~/.local/share/zoxide/
findmnt -T ~/.local/share/zoxide -o TARGET,SOURCE
zoxide query -l | head -3
sqlite3 ~/.local/share/zsh/history.db 'select count(*) from history' 2>&1
# (zoxide "remembers after reboot" is confirmed on the NEXT reboot: `zoxide query -l` must list /srv/the-hive)

# ===== 2. foot + tmux
systemctl --user is-active tmux-server.service ssh-agent.service
tmux display -p '#{session_name} #{window_panes} #{pane_current_path}'
tmux list-keys | grep -E 'C-S-Enter|S-Enter|C-Enter'
grep -E '^shell=|spawn-terminal|13;2u|13;6u' ~/.config/foot/foot.ini
# HANDS: press Ctrl+Shift+Enter -> a new pane in THIS tmux session, no new foot window. Then:
tmux display -p 'panes=#{window_panes}'
# HANDS: run `hermes`, press Shift+Enter -> newline, not send. Quit.
# HANDS (only if it did not): `cat -v`, press Shift+Enter, expect ^[[13;2u, Ctrl+C

# ===== 3. direnv (expect prefix = /srv/workspace + /srv/the-hive, "RC allowed 0" is fine with a whitelist hit)
echo DIRENV_CONFIG=$DIRENV_CONFIG; cat /etc/direnv/direnv.toml
ls -la ~/.config/direnv/ 2>&1
cd /srv/the-hive && direnv status | grep -E 'whitelist|RC allowed'; cd ~
# HANDS: `cd /srv/the-hive` in the interactive shell must NOT print "direnv: error ... is blocked"

# ===== 4. firefox: Phoenix wrapper + policies + SSO
readlink -f "$(command -v firefox)"
grep -c 'phoenix' "$(dirname "$(readlink -f "$(command -v firefox)")")/../lib/firefox/mozilla.cfg"
grep -o '"SearchEngines"\|"ExtensionSettings"\|"Nix Packages"' /etc/firefox/policies/policies.json | sort -u
systemctl --user is-active himmelblau-broker.service
# HANDS: firefox -> about:policies : SearchEngines / ExtensionSettings listed, no errors tab
# HANDS: about:config -> browser.startup.page = 3 ; privacy.sanitize.sanitizeOnShutdown = false
# HANDS: https://myapps.microsoft.com -> signs in without a password (broker PRT) = SSO OK

# ===== 5. git identities (expect 3 includeIf, NO default user.email)
git config --global --list --show-origin | grep -E 'includeif|user\.'
git config --global user.email || echo "OK: no default identity"
mkdir -p /tmp/gt && cd /tmp/gt && git init -q \
  && git remote add origin git@gh-work:x/y.git && echo "gh-work    -> $(git config user.email)" \
  && git remote set-url origin git@azure-owt:v3/a/b/c && echo "azure-owt  -> $(git config user.email)" \
  && git remote set-url origin git@gitlab.client-t.tld:a/b.git && echo "t       -> $(git config user.email)"
cd ~ && rm -rf /tmp/gt

# ===== 6. ssh matchBlocks + keys (expect /run/agenix/ssh-* owned by this uid, mode 0400)
grep -E '^Host |IdentityFile' ~/.ssh/config | paste - -
for f in $(grep IdentityFile ~/.ssh/config | awk '{print $2}'); do ls -la "$f"; done
ssh -G gh-work | grep -E '^(hostname|identityfile|user) '
ssh -T gh-work 2>&1 | head -1

# ===== 7. vpn (expect: no password / polkit dialog)
vpn status
vpn up owt && sleep 3 && vpn status && ip -br a show dev owt; resolvectl status owt 2>/dev/null | head -5
vpn down owt; vpn status
```

## B. as crookedmirror (second foot or tty2)

```bash
id -nG | tr ' ' '\n' | grep -E '^(wheel|hive|networkmanager)$'
systemctl --user is-active tmux-server.service ssh-agent.service
git config --global --list --show-origin | grep -E 'includeif|user\.'
grep -E '^Host |IdentityFile' ~/.ssh/config | paste - -
cd /srv/the-hive && direnv status | grep -E 'whitelist'; cd ~
vpn up w && sleep 5 && vpn status && ip -br a | grep -E 'tun'
vpn down w; vpn status
```

## C. reading the output

- `time zsh -ic exit` → real < 1 s.
- `[ERROR]: gitstatus failed to initialize` + `setopt: can't change option: monitor` appear
  ONLY when zsh runs without a tty (agent shell). In foot: `pgrep gitstatusd` must list a pid.
- §3: `whitelist.prefix [/srv/workspace /srv/the-hive]`. If `[]` → the switch did not land.
- §7 under Entra: if a password prompt appears → `id -nG | grep networkmanager` first;
  missing group = himmelblau has not reconciled yet (`local_groups_reconcile_interval=300`),
  relogin and retry before reporting as a failure.
- Anything that fails: paste it, it gets fixed declaratively in cells/ (no edits in either home).

## phase 4 tails — run as ENTRA (foot), 2026-09-15
# devshell smoke as Entra (direnv whitelist + srv-the-hive read access):
cd /srv/the-hive && nix develop .#default -c sh -c 'command -v go treefmt colmena deploy-key'
cd /srv/the-hive && nix develop -c go-test-all
# one work repo readable/writable once Clients/ is rsynced (after the disk/route step):
#   git -C /srv/workspace/work/<repo> status
# claude/hermes as Entra: first launch creates ~/.claude ~/.hermes on persist (auth-entra.nix:234-235),
# nothing to copy from the local account unless you want the session history too.
