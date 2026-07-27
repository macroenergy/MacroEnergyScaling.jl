@doc raw"""
    ScalingSettings

A structure to store the scaling settings for the scaling algorithm. The fields are:
    
- coeff_lb::Float64 = 1e-3: Lower bound for the scaling coefficients.
- coeff_ub::Float64 = 1e6: Upper bound for the scaling coefficients.
- constraint_min_coeff::Float64 = 0.0: Constraint coefficients with a smaller absolute value are dropped before scaling.
- rhs_lb::Float64 = 1e-3: Lower bound for the right-hand side scaling.
- rhs_ub::Float64 = 1e6: Upper bound for the right-hand side scaling.
- constraint_max_proxy_depth::Int = -1: Maximum number of proxy substitutions for a constraint term. Negative values allow unlimited recursion; `0` disables proxy substitutions.
- scale_nonaffine::Bool = true: Whether to error when non-scalar-affine constraints are encountered.
- scale_wideintervals::Bool = true: Whether to error when scalar-affine interval constraints require their bounds to be scaled differently.
- proxy_multiplier_reuse_ratio::Float64 = 10.0: Reuse an existing proxy when its multiplier is within this multiplicative factor of the requested multiplier.
- proxy_var_map::Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}} = Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}}(): A dictionary mapping variables to a vector of tuples of variables and scaling coefficients.
- objective_coeff_lb::Float64 = 1e-3: Lower bound for objective coefficients.
- objective_coeff_ub::Float64 = 1e6: Upper bound for objective coefficients.
- objective_min_coeff::Float64 = 0.0: Objective coefficients with a smaller absolute value are dropped before scaling.
- scale_objective_uniformly::Bool = false: Whether to apply a uniform multiplier before proxy scaling objective terms.
- objective_scaling_factor::Float64 = 1.0: Cumulative uniform multiplier applied to the objective.
- objective_max_proxy_depth::Int = -1: Maximum number of proxy substitutions for an objective term. Negative values allow unlimited recursion; `0` disables proxy substitutions.
"""
@Base.kwdef mutable struct ScalingSettings
    coeff_lb::Float64 = 1e-3
    coeff_ub::Float64 = 1e6
    constraint_min_coeff::Float64 = 0.0
    rhs_lb::Float64 = 1e-3
    rhs_ub::Float64 = 1e6
    constraint_max_proxy_depth::Int = -1
    scale_nonaffine::Bool = true
    scale_wideintervals::Bool = true
    proxy_multiplier_reuse_ratio::Float64 = 10.0
    proxy_var_map::Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}} = Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}}()
    objective_coeff_lb::Float64 = 1e-3
    objective_coeff_ub::Float64 = 1e6
    objective_min_coeff::Float64 = 0.0
    scale_objective_uniformly::Bool = false
    objective_scaling_factor::Float64 = 1.0
    objective_max_proxy_depth::Int = -1

    function ScalingSettings(coeff_lb, coeff_ub, constraint_min_coeff, rhs_lb, rhs_ub, constraint_max_proxy_depth, scale_nonaffine, scale_wideintervals, proxy_multiplier_reuse_ratio, proxy_var_map, objective_coeff_lb=1e-3, objective_coeff_ub=1e6, objective_min_coeff=0.0, scale_objective_uniformly=false, objective_scaling_factor=1.0, objective_max_proxy_depth=-1)
        coeff_lb = convert(Float64, coeff_lb)
        coeff_ub = convert(Float64, coeff_ub)
        constraint_min_coeff = convert(Float64, constraint_min_coeff)
        rhs_lb = convert(Float64, rhs_lb)
        rhs_ub = convert(Float64, rhs_ub)
        constraint_max_proxy_depth = convert(Int, constraint_max_proxy_depth)
        scale_nonaffine = convert(Bool, scale_nonaffine)
        scale_wideintervals = convert(Bool, scale_wideintervals)
        proxy_multiplier_reuse_ratio = convert(Float64, proxy_multiplier_reuse_ratio)
        proxy_var_map = convert(Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}}, proxy_var_map)
        objective_coeff_lb = convert(Float64, objective_coeff_lb)
        objective_coeff_ub = convert(Float64, objective_coeff_ub)
        objective_min_coeff = convert(Float64, objective_min_coeff)
        scale_objective_uniformly = convert(Bool, scale_objective_uniformly)
        objective_scaling_factor = convert(Float64, objective_scaling_factor)
        objective_max_proxy_depth = convert(Int, objective_max_proxy_depth)
        validate_scaling_values(coeff_lb, coeff_ub, constraint_min_coeff, rhs_lb, rhs_ub, proxy_multiplier_reuse_ratio)
        validate_objective_scaling_values(objective_coeff_lb, objective_coeff_ub, objective_min_coeff, objective_scaling_factor)
        return new(coeff_lb, coeff_ub, constraint_min_coeff, rhs_lb, rhs_ub, constraint_max_proxy_depth, scale_nonaffine, scale_wideintervals, proxy_multiplier_reuse_ratio, proxy_var_map, objective_coeff_lb, objective_coeff_ub, objective_min_coeff, scale_objective_uniformly, objective_scaling_factor, objective_max_proxy_depth)
    end
end

function validate_objective_scaling_values(objective_coeff_lb::Float64, objective_coeff_ub::Float64, objective_min_coeff::Float64, objective_scaling_factor::Float64)
    if !all(isfinite, (objective_coeff_lb, objective_coeff_ub, objective_min_coeff, objective_scaling_factor))
        throw(ArgumentError("Objective scaling settings must be finite."))
    elseif objective_coeff_lb <= 0.0 || objective_coeff_lb > objective_coeff_ub
        throw(ArgumentError("objective_coeff_lb must be positive and no greater than objective_coeff_ub."))
    elseif objective_min_coeff < 0.0 || objective_min_coeff > objective_coeff_lb
        throw(ArgumentError("objective_min_coeff must be nonnegative and no greater than objective_coeff_lb."))
    elseif objective_scaling_factor <= 0.0
        throw(ArgumentError("objective_scaling_factor must be positive."))
    end
    return nothing
end

function validate_scaling_values(coeff_lb::Float64, coeff_ub::Float64, constraint_min_coeff::Float64, rhs_lb::Float64, rhs_ub::Float64, proxy_multiplier_reuse_ratio::Float64)
    if !all(isfinite, (coeff_lb, coeff_ub, constraint_min_coeff, rhs_lb, rhs_ub, proxy_multiplier_reuse_ratio))
        throw(ArgumentError("Scaling settings must be finite."))
    elseif coeff_lb <= 0.0 || coeff_lb > coeff_ub
        throw(ArgumentError("coeff_lb must be positive and no greater than coeff_ub."))
    elseif rhs_lb <= 0.0 || rhs_lb > rhs_ub
        throw(ArgumentError("rhs_lb must be positive and no greater than rhs_ub."))
    elseif constraint_min_coeff < 0.0 || constraint_min_coeff > coeff_lb
        throw(ArgumentError("constraint_min_coeff must be nonnegative and no greater than coeff_lb."))
    elseif proxy_multiplier_reuse_ratio <= 1.0
        throw(ArgumentError("proxy_multiplier_reuse_ratio must be greater than 1."))
    end
    return nothing
end

function validate_scaling_settings(scaling_settings::ScalingSettings)
    validate_scaling_values(
        scaling_settings.coeff_lb,
        scaling_settings.coeff_ub,
        scaling_settings.constraint_min_coeff,
        scaling_settings.rhs_lb,
        scaling_settings.rhs_ub,
        scaling_settings.proxy_multiplier_reuse_ratio,
    )
    validate_objective_scaling_values(
        scaling_settings.objective_coeff_lb,
        scaling_settings.objective_coeff_ub,
        scaling_settings.objective_min_coeff,
        scaling_settings.objective_scaling_factor,
    )
    return nothing
end

@doc raw"""
    get_scaling_settings(settings::Dict)::ScalingSettings

Extracts the scaling settings from a dictionary and returns a `ScalingSettings` object.
"""
function get_scaling_settings(settings::Dict)::ScalingSettings
    scaling_settings = Dict{Symbol, Any}()
    for scaling_setting in [String(x) for x in fieldnames(ScalingSettings)]
        if haskey(settings, scaling_setting)
            scaling_settings[Symbol(scaling_setting)] = settings[scaling_setting]
        end
    end
    return ScalingSettings(; scaling_settings...)
end
