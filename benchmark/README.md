# Benchmarks

This directory contains microbenchmarks for constraint and objective scaling.
Model construction happens in BenchmarkTools' `setup` phase, so timings measure
only `scale_constraints!` or `scale_objective!`. The suite includes caching-model
and HiGHS direct-model constraint cases, dense constraints, and objective no-op,
mixed-scale, and proxy-scaling cases.
The objective cases also compare proxy-only scaling with opt-in uniform and
hybrid uniform scaling.

From the repository root, initialize the dedicated benchmark environment once:

```sh
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'
```

Then run the benchmark suite:

```sh
julia --project=benchmark benchmark/benchmarks.jl
```

Set `MES_BENCHMARK_CONSTRAINTS` to change the number of constraints per case.
Set `MES_BENCHMARK_DENSE_TERMS` to change the number of terms in each dense
constraint (default: 50). BenchmarkTools reports elapsed time as well as
allocations and allocated bytes.
