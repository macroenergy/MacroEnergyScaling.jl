@doc raw"""
    scale_objective!(model::Model, scaling_settings::ScalingSettings=ScalingSettings())

Scale a scalar-affine objective using proxy variables. By default, the
objective value is preserved. With `scale_objective_uniformly = true`, a
uniform multiplier may also be applied; the cumulative multiplier is stored in
`objective_scaling_factor`.

For a fully scaled model, call `scale_objective!` before `scale_constraints!`
with the same `ScalingSettings` object.
"""
function scale_objective!(model::Model, scaling_settings::ScalingSettings=ScalingSettings())
    validate_scaling_settings(scaling_settings)
    if objective_sense(model) == MOI.FEASIBILITY_SENSE
        return nothing
    end
    objective = scalar_affine_objective(model)
    uniform_multiplier = scaling_settings.scale_objective_uniformly ?
        uniform_objective_multiplier(objective, scaling_settings) : 1.0
    if !objective_needs_scaling(objective, uniform_multiplier, scaling_settings)
        return nothing
    end
    updated_scaling_factor = scaling_settings.objective_scaling_factor * uniform_multiplier
    if !isfinite(updated_scaling_factor) || updated_scaling_factor <= 0.0
        error("The cumulative objective scaling factor must remain finite and positive.")
    end
    scaled_objective = AffExpr(objective.constant * uniform_multiplier)
    for (var, coeff) in objective.terms
        magnitude = abs(coeff)
        if magnitude == 0.0 || magnitude < scaling_settings.objective_min_coeff
            continue
        end
        scaled_coeff = coeff * uniform_multiplier
        if scaling_settings.objective_coeff_lb <= abs(scaled_coeff) <= scaling_settings.objective_coeff_ub
            add_to_expression!(scaled_objective, scaled_coeff, var)
        else
            scaled_var, scaled_coeff = scaled_var_coeff_pair(
                var,
                scaled_coeff,
                scaling_settings.objective_coeff_lb,
                scaling_settings.objective_coeff_ub,
                scaling_settings.objective_max_proxy_depth,
                scaling_settings,
            )
            add_to_expression!(scaled_objective, scaled_coeff, scaled_var)
        end
    end
    set_objective_function(model, scaled_objective)
    scaling_settings.objective_scaling_factor = updated_scaling_factor
    return nothing
end

function objective_needs_scaling(objective, uniform_multiplier::Real, scaling_settings::ScalingSettings)
    if uniform_multiplier != 1.0
        return true
    end
    for coeff in values(objective.terms)
        magnitude = abs(coeff)
        if magnitude != 0.0 && (
            magnitude < scaling_settings.objective_min_coeff ||
            !(scaling_settings.objective_coeff_lb <= magnitude <= scaling_settings.objective_coeff_ub)
        )
            return true
        end
    end
    return false
end

function uniform_objective_multiplier(objective, scaling_settings::ScalingSettings)
    events = Tuple{Float64, Bool}[]
    count_at_one = 0
    for coeff in values(objective.terms)
        magnitude = abs(coeff)
        if magnitude == 0.0 || magnitude < scaling_settings.objective_min_coeff
            continue
        end
        lower = scaling_settings.objective_coeff_lb / magnitude
        upper = scaling_settings.objective_coeff_ub / magnitude
        push!(events, (lower, true))
        push!(events, (upper, false))
        if lower <= 1.0 <= upper
            count_at_one += 1
        end
    end
    isempty(events) && return 1.0
    sort!(events; by=first)
    active_count = 0
    best_count = count_at_one
    best_multiplier = 1.0
    event_index = 1
    while event_index <= length(events)
        multiplier = events[event_index][1]
        last_index = event_index
        starts = 0
        ends = 0
        while last_index <= length(events) && events[last_index][1] == multiplier
            if events[last_index][2]
                starts += 1
            else
                ends += 1
            end
            last_index += 1
        end
        active_count += starts
        if isfinite(multiplier) && multiplier > 0.0 && (
            active_count > best_count ||
            (active_count == best_count && abs(log(multiplier)) < abs(log(best_multiplier)))
        )
            best_count = active_count
            best_multiplier = multiplier
        end
        active_count -= ends
        event_index = last_index
    end
    return best_multiplier
end

function scalar_affine_objective(model::Model)
    try
        return objective_function(model, AffExpr)
    catch caught_error
        if caught_error isa InexactError || caught_error isa ArgumentError
            error("Non-scalar-affine objectives are not currently supported by MacroEnergyScaling.")
        end
        rethrow()
    end
end
