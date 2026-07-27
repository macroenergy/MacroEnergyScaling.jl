@doc raw"""
    scaled_var_coeff_pair(var::VariableRef, coeff::Real, coefficient_lb::Real, coefficient_ub::Real, max_proxy_depth::Int, scaling_settings::ScalingSettings)

Return a variable-coefficient pair equivalent to `(var, coeff)` whose
coefficient is within `coefficient_lb:coefficient_ub` when possible, using
proxy variables as needed.
"""
function scaled_var_coeff_pair(var::VariableRef, coeff::Real, coefficient_lb::Real, coefficient_ub::Real, max_proxy_depth::Int, scaling_settings::ScalingSettings, proxy_depth::Int=0)
    if max_proxy_depth >= 0 && proxy_depth >= max_proxy_depth
        return var, coeff
    end
    multiplier = calc_coeff_multiplier(coeff, coefficient_lb, coefficient_ub)
    new_coeff = coeff * multiplier
    proxy_var, multiplier = get_proxy_var(
        var,
        multiplier,
        scaling_settings.proxy_var_map,
        scaling_settings.proxy_multiplier_reuse_ratio,
    )
    new_coeff = coeff * multiplier
    new_coeff, _ = prune_coefficients(new_coeff, coeff, multiplier)
    if coefficient_lb <= abs(new_coeff) <= coefficient_ub
        return proxy_var, new_coeff
    end
    return scaled_var_coeff_pair(proxy_var, new_coeff, coefficient_lb, coefficient_ub, max_proxy_depth, scaling_settings, proxy_depth + 1)
end

@doc raw"""
    prune_coefficients(new_coeff::Real, coeff::Real, multiplier::Real)

If a new coefficient is close to 1.0 or -1.0, return 1.0 or -1.0 respectively.
"close" is defined using the Julia `isapprox` function.
"""
function prune_coefficients(new_coeff::Real, coeff::Real, multiplier::Real)
    if new_coeff ≈ 1.0
        return 1.0, new_coeff / coeff
    elseif new_coeff ≈ -1.0
        return -1.0, new_coeff / coeff
    end
    return new_coeff, multiplier
end

@doc raw"""
    calc_coeff_multiplier(coeff::Real, coeff_lb::Real, coeff_ub::Real)

Calculate the multiplier to scale the coefficient `coeff` to be within the bounds
`coeff_lb:coeff_ub`.
"""
function calc_coeff_multiplier(coeff::Real, coeff_lb::Real, coeff_ub::Real)
    abs_coeff = abs(coeff)
    if abs_coeff < coeff_lb
        return min(coeff_ub, 1.0 / abs_coeff)
    end
    if abs_coeff > coeff_ub
        return max(coeff_lb, 1.0 / abs_coeff)
    end
end

@doc raw"""
    get_proxy_var(var::VariableRef, multiplier::Real, proxy_var_map::Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}}, proxy_multiplier_reuse_ratio::Real)

Return a cached proxy for `var` with a sufficiently similar multiplier, or
create and cache a new proxy.
"""
function get_proxy_var(var::VariableRef, multiplier::Real, proxy_var_map::Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}}, proxy_multiplier_reuse_ratio::Real)
    cached_result = existing_proxy_var(var, multiplier, proxy_var_map, proxy_multiplier_reuse_ratio)
    if !isnothing(cached_result)
        return cached_result
    end
    proxy_var = make_proxy_var(var, multiplier)
    if !haskey(proxy_var_map, var)
        proxy_var_map[var] = Vector{Tuple{VariableRef, Float64}}()
    end
    push!(proxy_var_map[var], (proxy_var, multiplier))
    return proxy_var, multiplier
end

function existing_proxy_var(var::VariableRef, multiplier::Real, proxy_var_map::Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}}, proxy_multiplier_reuse_ratio::Real)
    if !haskey(proxy_var_map, var)
        return nothing
    end
    for (proxy_var, cached_multiplier) in proxy_var_map[var]
        if 1 / proxy_multiplier_reuse_ratio < multiplier / cached_multiplier < proxy_multiplier_reuse_ratio
            return proxy_var, cached_multiplier
        end
    end
    return nothing
end

function make_proxy_var(var::VariableRef, multiplier::Real)
    model = var.model
    proxy_var = @variable(model)
    if has_lower_bound(var)
        set_lower_bound(proxy_var, lower_bound(var) * multiplier)
    end
    if has_upper_bound(var)
        set_upper_bound(proxy_var, upper_bound(var) * multiplier)
    end
    @constraint(model, var == proxy_var * multiplier)
    return proxy_var
end
