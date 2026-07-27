# Changelog

All notable changes to MacroEnergyScaling.jl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this
project follows Julia package versioning through `Project.toml` releases.

## 0.4.0 - 2026-07-27

### Added

  * Added `scale_objective!(model, settings)` for scalar-affine objectives,
    including variable-only and constant affine objectives. It preserves objective
    sense and the affine constant, and reuses the existing proxy-variable cache.
  * Added `objective_coeff_lb`, `objective_coeff_ub`, and
    `objective_min_coeff` settings. `objective_min_coeff = 0.0` is the exact,
    safe default; a positive value deliberately prunes smaller objective terms
    before scaling.
  * Added opt-in uniform objective scaling through
    `scale_objective_uniformly = true`. It selects a multiplier that places the
    greatest number of retained objective coefficients within the requested range,
    then uses proxy variables only for remaining out-of-range terms.
  * Added `objective_scaling_factor`, which records cumulative uniform objective
    scaling and can be used to recover the original objective value.
  * Added separate `constraint_max_proxy_depth` and
    `objective_max_proxy_depth` settings. A value of `-1` allows unlimited proxy
    steps, `0` disables proxy variables, and a positive value permits that many
    proxy steps per term.
  * Added support for non-wide scalar-affine interval constraints. Wide intervals
    can be skipped with `scale_wideintervals = false`; otherwise the package
    reports the offending constraint.
  * Added HiGHS direct-model coverage and benchmarks, along with optional
    direct-model tests for licensed solvers such as Gurobi.

### Changed

  * Constraint and objective scaling now preserve the mathematical model exactly
    by default. Terms are only pruned when the corresponding explicit minimum
    coefficient setting is positive.
  * Renamed `min_coeff` to `constraint_min_coeff`. It is now a deliberate
    pre-scaling pruning threshold, with a default of `0.0`, rather than a
    post-scaling proxy-termination mechanism.
  * Renamed `proxy_var_ratio_ub` to `proxy_multiplier_reuse_ratio`; its behaviour
    is unchanged.
  * Replaced `allow_recursion` with explicit proxy-depth limits for constraints
    and objectives.
  * Reduced constraint-scaling allocations and unnecessary work by collecting
    extrema while pruning, batching changed terms, and avoiding updates when no
    change is required.
  * Reorganised internal scaling code into `constraint_scaling.jl` and
    `scaling_utilities.jl`. Downstream packages should use exported APIs rather
    than internal source files or non-exported helpers.

### Fixed

  * Fixed constraint scaling replacing constraints in a way that could invalidate
    stored `ConstraintRef`s. Constraints are now updated in place, so downstream
    code can continue to access its existing references after scaling.
  * Improved direct-model compatibility for incremental constraint updates.

### Documentation

  * Added objective-scaling documentation, including recommended ordering with
    constraint scaling and recovery of uniformly scaled objective values.
  * Added Mermaid workflow diagrams for constraint and objective scaling.
  * Documented the exact-default behaviour, deliberate pruning trade-offs,
    interval-constraint handling, proxy depth limits, and uniform-scaling effects
    on reported objective values and constraint duals.

### Migration guide

  * Update renamed settings and replace `allow_recursion` with explicit depth
    limits. The closest equivalent to `allow_recursion = false` is a depth of `1`,
    which permits the initial proxy step but no further recursion:

    ```julia
    # Before
    settings = ScalingSettings(
        min_coeff = 1e-9,
        proxy_var_ratio_ub = 10.0,
        allow_recursion = false,
    )

    # After
    settings = ScalingSettings(
        constraint_min_coeff = 1e-9,
        proxy_multiplier_reuse_ratio = 10.0,
        constraint_max_proxy_depth = 1,
        objective_max_proxy_depth = 1,
    )
    ```

  * Use a depth of `0` to prohibit proxy variables entirely, or `-1` to allow
    unlimited proxy depth. Configure both depth settings when scaling both
    constraints and objectives.
  * Prefer keyword construction of `ScalingSettings`; its field layout has
    expanded, so positional construction is more fragile.
  * To scale objectives as well as constraints, use the same settings object and
    scale the objective first so that the proxy equalities it creates are processed
    with the constraints:

    ```julia
    settings = ScalingSettings()
    scale_objective!(model, settings)
    scale_constraints!(model, settings)
    ```

  * Uniform objective scaling is opt-in. It changes the solver-reported objective
    value and the scale of constraint duals; recover the original objective value
    with:

    ```julia
    original_value = objective_value(model) / settings.objective_scaling_factor
    ```

  * A positive `objective_min_coeff` or `constraint_min_coeff` deliberately
    approximates the model. Objective pruning may change the selected optimum or
    tie-breaking and cannot be reversed with `objective_scaling_factor`.
