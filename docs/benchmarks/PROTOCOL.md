# Benchmark protocol (fanless machines)

Both target machines are MacBook Airs with no fan. Sustained load causes a
monotonic performance decay, so the usual "warm up, then take the median"
recipe produces numbers that depend on measurement order.

## Rules

1. **Interleave variants.** Run A, B, C, A, B, C … never A ×11 then B ×11.
   Sequential runs let the later candidate inherit the heat of the earlier one.
2. **Force a cooldown** between rounds and record its length in `notes`.
3. **Report two numbers**: `burst` (from cold) and `steady` (after sustained
   saturation). Never a single unlabelled figure.
4. **Attach the decay curve** (`thermal.state: decay` with `t_s`) to any claim
   about sustained performance.
5. **Record thermal context**: room temperature, stand or surface, AC power.
6. **Close the editor** before measuring. Background indexing heats the chassis.
7. **Deactivate conda and unset `CC`/`CXX`.** `tools/bench_context.zsh`
   enforces this.

## Cross-machine comparisons

Build both machines with the lower common baseline (`-mcpu=apple-m3`), so that
compiler code generation does not contaminate the hardware comparison.
Measurements of machine-specific features (SME on `m4air32`) are recorded as
separate data points with their own flags.

Schema: [SCHEMA.md](SCHEMA.md)
