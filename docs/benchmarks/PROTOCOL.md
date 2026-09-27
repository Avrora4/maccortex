# Benchmark protocol (fanless machines)

Both target machines are MacBook Airs with no fan. Sustained load causes a
monotonic performance decay, so the usual "warm up, then take the median"
recipe produces numbers that depend on measurement order.

## Rules

1. **Interleave variants.** Run A, B, C, A, B, C … never A ×11 then B ×11.
   Sequential runs let the later candidate inherit the heat of the earlier one.
2. **Cool down after every measurement**, not only between rounds: within a
   fixed order, B would otherwise always start where A left the chassis.
   The cooldown length is recorded in `notes`.
3. **Report two numbers**: `burst` (from cold) and `steady` (after sustained
   saturation). Never a single unlabelled figure.
4. **Attach the decay curve** (`thermal.state: decay` with `t_s`) to any claim
   about sustained performance.
5. **Record thermal context**: room temperature, stand or surface, AC power.
6. **Close the editor** before measuring. Background indexing heats the chassis.
7. **Deactivate conda and unset `CC`/`CXX`.** `tools/bench_context.zsh`
   enforces this.
8. **Measure on a clean tree.** `tools/bench_runner.zsh` refuses a dirty one.

## Running

`tools/bench_runner.zsh` implements rules 1, 2 and 8 and adds the context to
every record:

```sh
# interleaved comparison, 11 rounds, 30 s cooldown after every measurement
tools/bench_runner.zsh --subject hello_gemm --variants "accelerate naive" \
  --rounds 11 --cooldown 30 -- build/macos-release/bench/bench_hello --state burst

# the same comparison in the opposite order (order-bias check)
tools/bench_runner.zsh --subject hello_gemm --variants "accelerate naive" \
  --rounds 11 --cooldown 30 --reverse -- build/macos-release/bench/bench_hello --state burst

# one continuous run: a sample every 2 s for 30 minutes
tools/bench_runner.zsh --subject hello_gemm_decay --variants accelerate \
  --rounds 1 --cooldown 0 -- build/macos-release/bench/bench_hello \
  --state decay --duration-s 1800 --interval-s 2
```

`tools/plot_bench.py` draws the figures and performs the order-bias check
(`compare`): the median of every variant must agree within the tolerance
between the two orders. If it does not, the cooldown is too short — lengthen
it; do not widen the tolerance.

## Cross-machine comparisons

Build both machines with the lower common baseline (`-mcpu=apple-m3`), so that
compiler code generation does not contaminate the hardware comparison.
Measurements of machine-specific features (SME on `m4air32`) are recorded as
separate data points with their own flags.

Schema: [SCHEMA.md](SCHEMA.md)
