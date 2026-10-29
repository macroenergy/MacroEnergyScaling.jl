# Constraint Scaling Functions

```@autodocs
Modules = [MacroEnergyScaling]
Pages = ["constraint_scaling.jl", "scaling_utilities.jl"]
```

## Recovering duals in original units

Pass an explicit `ScalingSettings` object to retain scaling information:

```julia
settings = MacroEnergyScaling.ScalingSettings()
scale_objective!(model, settings)    # Optional; defaults to proxy-only scaling.
scale_constraints!(model, settings)
optimize!(model)

row_factor = get(settings.constraint_scaling_factors, constraint, 1.0)
original_dual = dual(constraint) * row_factor / settings.objective_scaling_factor
```

Each factor means `scaled row = factor * original row`, after expressing any
proxy variables in the original variables. The map contains only constraints
that received a non-unit uniform row multiplier; absent entries mean `1.0`.
Proxy substitutions alone do not change the row factor. Original constraint
references stay valid, including for zero-RHS and interval constraints.

Factors accumulate across calls using the same settings object. Keep that object
for the same model's scaling workflow; the package does not automatically attach
it to the model, and scaling functions continue to return `nothing`. If the
original constraint or objective is replaced or manually rescaled, start a new
scaling workflow or update/reset its metadata accordingly. Scaling factors cannot
undo terms deliberately removed by coefficient-pruning settings.
