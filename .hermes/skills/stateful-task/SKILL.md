---
name: stateful-task
description: Multi-session task — state file in the repo, not in chat.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [workflow, state, long-horizon, resume]
    related_skills: [terse-comments, rensa-nix]
---

# stateful-task

For work that outlives one session (a multi-phase port, a migration, an
incident), the chat is not the source of truth. A state file in the repo is.
Pattern from arXiv:2608.26263 (SKILL.state): the skill is the immutable
procedure `P`, the file is the mutable state `Σ`, tool output is the
observation `O`. Chat history is discarded by compaction; the file is not.

## When to Use

The user says "продолжай <task>", "continue the port", or names a task that
has a file under `<repo>/.hermes/state/`. Also when starting a task you can
tell will span sessions: create the file first.

## The file

`<repo>/.hermes/state/<task>.md`, committed with the code it describes. One
fixed schema per task type, written once; slots are filled, never
re-invented. Template for a NixOS/rensa port:

```markdown
# <task>

phase: <one of the fixed phase list>
phases: 1 storage+boot | 2 secrets | 3 auth | 4 desktop

## ported
<source file> -> <dest file> @ <commit>

## invariants
<name>: `<command>` == <expected>   last: <value> @ <date>

## blocked_on
- <thing only the user can supply, or nothing>

## verified
<phase>: `<command>` -> <one-line result> @ <date>

## notes
<facts learned that fit no slot; keep short>
```

## Procedure, every step

1. Read the file first. Do not reconstruct state from chat or `session_search`
   when the file exists.
2. If the user reports an out-of-band change ("я задеплоил", "I moved X"),
   update the file before planning anything. Old plan text must never
   outrank a fresh observation.
3. Do one step of the current phase.
4. Run the invariant commands. Record command + result in `verified`, not
   "it built".
5. Update the file as a diff: change the slots that changed, leave the rest
   byte-identical. Never rewrite from memory.
6. Commit code and state together.

## Rules

- Progress lives in the file, never in a skill and never in MEMORY.
- `invariants` hold a command and an expected value. A prose invariant
  ("osgiliath must not change") is not checkable; `nix eval --raw
  .#colmenaHive.toplevel.osgiliath.drvPath` is.
- `notes` is the escape hatch for what the schema did not foresee; if it
  grows past a screen, promote a slot.
- Fresh session > long session for the next phase. Say so if the user is
  about to continue a spent context.
