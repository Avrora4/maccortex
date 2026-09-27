#!/usr/bin/env python3
"""Plot and check benchmark results (schema v1, docs/benchmarks/SCHEMA.md).

  plot_bench.py decay   RESULTS.jsonl -o FIGURE.png [--steady-after 600]
      throughput over time from a continuous run (thermal.state == "decay")
  plot_bench.py rounds  RESULTS.jsonl -o FIGURE.png
      throughput per interleaving round, one line per variant
  plot_bench.py compare FIRST.jsonl SECOND.jsonl [--tolerance 0.05]
      median per variant in two runs made in opposite orders; exits 1 if any
      variant differs by more than the tolerance (order bias not removed)

Plotting and reference-value generation are the only uses of Python in this
repository; the library itself never depends on it.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

SUPPORTED_SCHEMAS = {1}
PRESSURE_COLOURS = {"fair": "#f2d7a6", "serious": "#f0a58f", "critical": "#d9534f"}


def load(path: Path) -> list[dict]:
    records = []
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        record = json.loads(line)
        if record.get("schema") not in SUPPORTED_SCHEMAS:
            sys.exit(f"{path}:{number}: unsupported schema {record.get('schema')!r}")
        records.append(record)
    if not records:
        sys.exit(f"{path}: no records")
    return records


def describe(records: list[dict]) -> str:
    first = records[0]
    env = first.get("env", {})
    return (f"{first.get('machine')} · macOS {env.get('macos')} · Xcode {env.get('xcode')} · "
            f"{env.get('compiler')} {env.get('flags')} · git {first.get('git')}")


def import_pyplot():
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    return plt


def cmd_decay(args: argparse.Namespace) -> None:
    records = [r for r in load(args.results) if r["thermal"]["state"] == "decay"]
    if not records:
        sys.exit("no records with thermal.state == 'decay'")
    t = [r["t_s"] for r in records]
    v = [r["value"] for r in records]
    unit = records[0]["unit"]

    burst = v[0]
    steady_values = [value for time, value in zip(t, v) if time >= args.steady_after]
    steady = statistics.median(steady_values) if steady_values else None

    plt = import_pyplot()
    fig, ax = plt.subplots(figsize=(9, 4.5))
    # Shade the intervals where the OS reported elevated thermal pressure.
    shaded: set[str] = set()
    for i, record in enumerate(records):
        pressure = record["thermal"].get("pressure", "")
        colour = PRESSURE_COLOURS.get(pressure)
        if colour and i + 1 < len(records):
            label = None if pressure in shaded else f"thermal pressure: {pressure}"
            shaded.add(pressure)
            ax.axvspan(t[i], t[i + 1], color=colour, linewidth=0, label=label)
    ax.plot(t, v, linewidth=1.2, color="#2b6cb0", label="throughput")
    ax.axhline(burst, linestyle=":", color="#555555", linewidth=1, label="burst (first sample)")
    if steady is not None:
        ax.axhline(steady, linestyle="--", color="#555555", linewidth=1,
                   label=f"steady (median after {args.steady_after:.0f} s)")
    ax.legend(loc="lower left", fontsize=8)
    ax.set_xlabel("time since start (s)")
    ax.set_ylabel(f"throughput ({unit})")
    variant = records[0]["variant"]
    ax.set_title(f"{records[0]['subject']} / {variant}: sustained load", loc="left")
    fig.text(0.01, 0.01, describe(records), fontsize=7, color="#555555")
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    fig.savefig(args.output, dpi=150)

    print(f"samples : {len(records)} over {t[-1]:.0f} s")
    print(f"burst   : {burst:.1f} {unit} (first sample)")
    if steady is not None:
        print(f"steady  : {steady:.1f} {unit} (median after {args.steady_after:.0f} s)")
        print(f"steady/burst: {steady / burst:.1%}")
    else:
        print(f"steady  : n/a (run shorter than {args.steady_after:.0f} s)")
    print(f"figure  : {args.output}")


def cmd_rounds(args: argparse.Namespace) -> None:
    records = load(args.results)
    by_variant: dict[str, list[tuple[int, float]]] = defaultdict(list)
    for r in records:
        by_variant[r["variant"]].append((r["round"], r["value"]))

    plt = import_pyplot()
    fig, ax = plt.subplots(figsize=(9, 4.5))
    for variant, points in by_variant.items():
        points.sort()
        ax.plot([p[0] for p in points], [p[1] for p in points], marker="o", label=variant)
    ax.set_xlabel("round")
    ax.set_ylabel(f"throughput ({records[0]['unit']})")
    ax.set_title(f"{records[0]['subject']}: interleaved rounds ({records[0].get('notes', '')})",
                 loc="left")
    ax.legend()
    fig.text(0.01, 0.01, describe(records), fontsize=7, color="#555555")
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    fig.savefig(args.output, dpi=150)
    print(f"figure: {args.output}")


def medians(records: list[dict]) -> dict[str, float]:
    by_variant: dict[str, list[float]] = defaultdict(list)
    for r in records:
        by_variant[r["variant"]].append(r["value"])
    return {variant: statistics.median(values) for variant, values in by_variant.items()}


def cmd_compare(args: argparse.Namespace) -> None:
    first, second = load(args.first), load(args.second)
    m1, m2 = medians(first), medians(second)
    if set(m1) != set(m2):
        sys.exit(f"variants differ: {sorted(m1)} vs {sorted(m2)}")
    print(f"first  : {first[0].get('notes', '')}")
    print(f"second : {second[0].get('notes', '')}")
    print(f"{'variant':<12} {'first':>10} {'second':>10} {'diff':>8}")
    worst = 0.0
    for variant in sorted(m1):
        diff = abs(m1[variant] - m2[variant]) / max(m1[variant], m2[variant])
        worst = max(worst, diff)
        print(f"{variant:<12} {m1[variant]:>10.2f} {m2[variant]:>10.2f} {diff:>8.1%}")
    verdict = "PASS" if worst <= args.tolerance else "FAIL"
    print(f"{verdict}: largest difference {worst:.1%} (tolerance {args.tolerance:.0%})")
    sys.exit(0 if verdict == "PASS" else 1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    decay = sub.add_parser("decay")
    decay.add_argument("results", type=Path)
    decay.add_argument("-o", "--output", type=Path, required=True)
    decay.add_argument("--steady-after", type=float, default=600.0)
    decay.set_defaults(func=cmd_decay)

    rounds = sub.add_parser("rounds")
    rounds.add_argument("results", type=Path)
    rounds.add_argument("-o", "--output", type=Path, required=True)
    rounds.set_defaults(func=cmd_rounds)

    compare = sub.add_parser("compare")
    compare.add_argument("first", type=Path)
    compare.add_argument("second", type=Path)
    compare.add_argument("--tolerance", type=float, default=0.05)
    compare.set_defaults(func=cmd_compare)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
