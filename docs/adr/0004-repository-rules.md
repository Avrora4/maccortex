# ADR-0004: Repository rules

- Status: accepted
- Date: 2026-09-27
- Phase: 0

## Context

Some repository rules are one-way doors. Violating them means either rewriting
history — which changes every commit hash and breaks every permalink in
published articles — or losing comparability of past measurements, which can
never be re-run because the compiler, OS and code of that moment are gone.

These rules are fixed before the first commit, and each is paired with a
mechanism that enforces it. Rules that can be changed cheaply at any time
(labels, README wording, CI details) are deliberately left out.

## Decision

| Rule | Enforced by |
|---|---|
| No file over 1 MB; no datasets, weights, traces or raw logs in history | `.gitignore` + `.githooks/pre-commit` |
| No credentials in history | `.githooks/pre-commit` |
| Commit subject `<type>(<scope>): <summary>`, English, summary ≤ 72 chars | `.githooks/commit-msg` |
| Both machines commit as `Avrora4 <asagiprog@gmail.com>` | `tools/setup_clone.zsh` warning |
| Linear history; no force push or deletion of `main` | GitHub ruleset (once public) + `pull.rebase=true` |
| Formatting defined by `.clang-format`; bulk reformat commits listed in `.git-blame-ignore-revs` | format on save |
| ADRs are append-only | `docs/adr/README.md` (convention only) |
| Articles link to commits by hash, never to a branch | convention |
| Directories are created when their first file lands (no `.gitkeep` scaffolding) | convention |
| Machine IDs are fixed to `m3air16` and `m4air32`; adding one requires an ADR | `tools/setup_clone.zsh` allow-list |

`git clone` transfers neither hooks nor local configuration, so every clone
runs `tools/setup_clone.zsh <machine-id>` once.

### Visibility and rollout

The repository is created private and made public once the build, test and
benchmark foundation is committed, so that its first public state is coherent.
Branch rulesets are applied after it becomes public, because they are not
enforced on private repositories under the current plan.

Until then, only `m3air16` commits; `m4air32` follows with `git pull`. This
keeps the bootstrap history linear without relying on the ruleset.

### Files that deliberately live elsewhere

- The bootstrap generator that produced the reference files is not committed.
  Files were copied from its output one commit at a time, so that each commit
  records a single decision.
- `check-env.zsh`, the environment checker published with the setup articles,
  lives in the article repository (`Avrora4/zenn-contents`, `scripts/`). It is
  not duplicated here, so the two copies cannot drift apart.

## Consequences

- Datasets, checkpoints and weights live outside git entirely.
- Because force pushes are blocked once public, a pushed commit hash stays
  valid forever, which is what makes hash permalinks in articles safe.
- The author email is visible to anyone who clones the repository.

## Rejected because

- **GitHub noreply address:** the author email is already public through other
  repositories, including the article repository, so hiding it here would gain
  nothing while splitting the author's identity across projects.
- **pre-commit framework (Python):** adds a runtime dependency for two hooks
  that fit in 60 lines of zsh.
- **Git LFS for weights and datasets:** keeps them attached to the repository
  and invites exactly the growth these rules exist to prevent.
- **Squash merging:** collapses per-commit history that the commit-msg hook
  already keeps meaningful. The article repository uses squash merging; that
  is a separate repository with a separate policy.
- **Committing the bootstrap generator:** it produces a single-commit snapshot
  of the whole tree, which is the opposite of the one-decision-per-commit
  history this repository keeps.
