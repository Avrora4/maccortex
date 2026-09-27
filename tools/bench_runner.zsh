#!/usr/bin/env zsh
# bench_runner.zsh — interleaved benchmark runner for fanless Macs.
#
#   tools/bench_runner.zsh --subject NAME --variants "a b" [--rounds N]
#                          [--cooldown S] [--reverse] [--allow-dirty]
#                          -- <binary> [binary args...]
#
# Runs a, b, a, b, ... (never a xN then b xN) and idles --cooldown seconds after
# every measurement: on a fanless machine the later candidate otherwise
# inherits the earlier one's heat, and the order decides the result.
#
# The binary receives "--variant V --round R" appended to its arguments and
# must print schema v1 records without context. Each record is merged with the
# context from bench_context.zsh and written to
#   docs/benchmarks/results/<UTC stamp>_<machine>_<subject>.jsonl
# The file only gets that name when the run completes; until then it is
# <name>.partial, so an interrupted or failed run can never pass for a result.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

usage() {
  sed -n '2,15p' "$0" >&2
  exit 2
}

rounds=11
cooldown=30
reverse=0
allow_dirty=0
subject=""
typeset -a variants
while (( $# > 0 )); do
  case "$1" in
    --rounds)      rounds="$2"; shift 2 ;;
    --cooldown)    cooldown="$2"; shift 2 ;;
    --reverse)     reverse=1; shift ;;
    --allow-dirty) allow_dirty=1; shift ;;
    --subject)     subject="$2"; shift 2 ;;
    --variants)    variants=(${=2}); shift 2 ;;
    --)            shift; break ;;
    *)             print -u2 "unknown option: $1"; usage ;;
  esac
done
(( $# >= 1 )) && [[ -n "$subject" ]] && (( ${#variants} >= 1 )) || usage
bin="$1"; shift
[[ -x "$bin" ]] || { print -u2 "✗ not an executable: $bin (build it first)"; exit 1 }

# Context once per run; this also enforces the conda and CC/CXX guards.
ctx=$(./tools/bench_context.zsh)
if [[ "$(print -r -- "$ctx" | jq -r .git)" == *-dirty ]] && (( ! allow_dirty )); then
  print -u2 "✗ working tree is dirty; results would not be reproducible (SCHEMA.md rule 4)"
  print -u2 "  commit first, or pass --allow-dirty for an exploratory run"
  exit 1
fi
machine=$(print -r -- "$ctx" | jq -r .machine)

(( reverse )) && variants=(${(Oa)variants})
notes="cooldown=${cooldown}s order=${(j:,:)variants}"
out="docs/benchmarks/results/$(date -u +%Y%m%dT%H%M%SZ)_${machine}_${subject}.jsonl"
partial="${out}.partial"
mkdir -p "${out:h}"
if [[ -e "$out" || -e "$partial" ]]; then
  print -u2 "✗ ${out} already exists; wait a second and run again"
  exit 1
fi

print -r -- "subject  : ${subject}"
print -r -- "order    : ${(j: -> :)variants}"
print -r -- "rounds   : ${rounds}, cooldown ${cooldown}s after every measurement"
print -r -- "output   : ${out}"

total=$(( rounds * ${#variants} ))
count=0
for (( r = 1; r <= rounds; r++ )); do
  for v in $variants; do
    # caffeinate keeps the machine awake for long runs; it does not change clocks.
    caffeinate -i "$bin" "$@" --variant "$v" --round "$r" \
      | jq -c --argjson ctx "$ctx" --arg notes "$notes" '(. * $ctx) + {notes: $notes}' \
      >> "$partial"
    count=$(( count + 1 ))
    print -r -- "  [${count}/${total}] round ${r} ${v}: $(tail -n 1 "$partial" | jq -r '"\(.value) \(.unit), pressure \(.thermal.pressure)"')"
    if (( count < total && cooldown > 0 )); then
      sleep "$cooldown"
    fi
  done
done

mv "$partial" "$out"
print -r -- "done -> ${out} ($(wc -l < "$out" | tr -d ' ') records)"
