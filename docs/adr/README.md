# Architecture Decision Records

## Rules

1. Numbers are never reused. Rejected or abandoned ADRs stay in the repository.
2. An accepted ADR is never rewritten. To change a decision, write a new ADR.
3. The superseded ADR receives exactly one added line:
   `Status: superseded by ADR-XXXX`.
4. Every ADR states the options that were NOT taken, and why.
5. Typos and broken links may be fixed in place, as long as the meaning does
   not change.
6. Numbers are assigned when a decision is made, not when it is committed, so
   the commit order of ADRs may differ from their numbering.

These rules have no enforcement mechanism, which is why they are written here.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-project-conventions.md) | Project name, namespace and identifier conventions | accepted |
| [0004](0004-repository-rules.md) | Repository rules | accepted |

Template: [0000-template.md](0000-template.md)
