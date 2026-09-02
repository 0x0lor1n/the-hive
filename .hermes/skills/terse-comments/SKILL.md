---
name: terse-comments
description: Comments for senior readers — say only what code cannot.
version: 1.0.0
author: hermes
license: MIT
metadata:
  hermes:
    tags: [style, comments, code-review, refactor]
    related_skills: [simplify-code, requesting-code-review]
---

# terse-comments

The reader is a senior engineer who knows the language, the framework and the
tools. A comment exists to say the one thing the code cannot. Everything else
is noise that hides the comments that matter.

## When to Use

Every time you write or edit code for this user, and whenever asked to
"reevaluate", "clean up", "sanitize" or "remove AI slop" from a codebase.
Also load before writing commit messages and READMEs — same rules apply.

## What a comment may say

Exactly one of:

1. **A non-obvious constraint** the code satisfies. "nginx `add_header` in a
   location discards the inherited set" — you cannot see that from the code.
2. **A measured failure** the code prevents. "Setting both yields duplicate
   mirroredBoots — measured." State the failure mode, not the story.
3. **A deliberate non-default** and its reason, in one clause. "Reload, not
   restart: listeners hold the stream open for hours."
4. **A pointer** to the thing that pins this: an issue URL, a line in upstream
   source, a spec section.

If the comment does not fall in one of those four, delete it.

## What a comment must never say

- What the code does. `# loop over hosts` above a loop over hosts.
- Restated option docs. `description = "The hostname."` on `hostName`.
- Porting/migration narrative. "Under hive this was X; rensa does Y." The
  reader is not migrating; they are reading the result.
- Iteration/plan references. `(iter 11 §2.2)`, `see .sisyphus/plans/…`.
- Section banners. `# ---- nginx ----`. Structure is the code's job.
- Praise, hedging, or reassurance. "Deliberately", "clever trick",
  "this is important", "note that", "should be safe".
- Emphasis capitals. `NOT`, `MUST`, `EXACTLY`. If it matters, the sentence
  already carries it.
- Anything a `git blame` on the line would show. That is what commit bodies
  are for.

## Length

- One or two lines is the norm. Four is the ceiling. Past that, either the
  code is wrong or the explanation belongs in the commit message.
- A header comment on a file, if any: one sentence saying what the file is
  for, not how it got there.
- No blank `#` lines inside a comment block unless separating two distinct
  points.

## Procedure for a cleanup pass

1. Read every file whole. Do not skim.
2. For each comment ask: does it fit one of the four permitted kinds? If not,
   delete it. If yes, cut it to the minimum that still carries the fact.
3. While reading, list dead code: options nothing reads, inputs nothing
   uses, files nothing imports, `mkForce`/`mkDefault` pairs that exist only to
   cancel each other. Grep for every consumer before deciding.
4. Remove dead code, then rebuild/evaluate. For NixOS: `nix store
   diff-closures old new` must show exactly the intended delta.
5. Commit with a body that lists what was removed and why, plus the
   verification. The narrative goes in the commit, never back into the code.

## Commit messages and READMEs

Same four kinds, same length discipline. A README says what the thing is,
how to run it, and the traps that were measured. It does not tell the story
of how it was built; that is what `git log` is for.

## Behaviour, same discipline

Fable 5.1 defaults the user has corrected, repeatedly:

- Once the user has said "go", "давай", "yes" — do the work. Do not ask
  "Делать?" again at each sub-step. Ask only before destructive or
  out-of-scope actions.
- Batch independent tool calls in one turn: three `patch`es and the
  `alejandra` run go together, not in four turns.
- `patch` when less than half the file changes; `write_file` only for
  rewrites. A whole-file rewrite for a two-line edit costs tokens and hides
  the diff.
- Scope is the request. A nearby improvement (an extra header, a stray
  `.gitignore`) is a one-line suggestion at the end, not a change.
- Answer in the user's language and register. Short paragraphs; no
  mannered prose.

## Self-check before finishing

Grep your own diff for: `deliberately`, `note that`, `important`, `NOT `,
`MUST `, `iter `, `§`, `----`. Each hit is a candidate for deletion.
