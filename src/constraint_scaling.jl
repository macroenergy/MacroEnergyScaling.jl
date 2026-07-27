# Constraint scaling workflow

@doc raw"""
    scale_constraints!(EP::Model, scaling_settings::ScalingSettings=ScalingSettings())

Scale the scalar-affine constraints in the model `EP` using the scaling settings `scaling_settings`.
"""
function scale_constraints!(EP::Model, scaling_settings::ScalingSettings=ScalingSettings())
    validate_scaling_settings(scaling_settings)
    constraint_types = list_of_constraint_types(EP)
    validate_constraint_types(constraint_types, EP, scaling_settings)
    for (function_type, set_type) in constraint_types
        if is_scalar_affine_constraint(function_type, set_type)
            con_list = all_constraints(EP, function_type, set_type)
            scale_constraints!(con_list, scaling_settings)
        end
    end
    return nothing
end

@doc raw"""
    scale_constraints!(constraint_list::AbstractVector{<:ConstraintRef}, scaling_settings::ScalingSettings=ScalingSettings())

Scale the coefficients and RHS of the homogeneous constraint group `constraint_list`
using the scaling settings `scaling_settings`.
"""
function scale_constraints!(constraint_list::AbstractVector{T}, scaling_settings::ScalingSettings=ScalingSettings()) where {T<:ConstraintRef}
    validate_scaling_settings(scaling_settings)
    if isempty(constraint_list)
        return nothing
    end
    if !isconcretetype(T)
        throw(ArgumentError("constraint_list must have a concrete, homogeneous ConstraintRef element type. Pass constraints grouped by JuMP constraint type."))
    end
    if !is_scalar_affine_constraint(first(constraint_list))
        if scaling_settings.scale_nonaffine
            error("Non-scalar-affine constraints are not currently supported by MacroEnergyScaling. Set scale_nonaffine = false to skip these constraints")
        end
        return nothing
    end
    for con_ref in constraint_list
        scale_constraint!(con_ref, scaling_settings)
    end
    return nothing
end

@doc raw"""
    validate_constraint_types(constraint_types, EP::Model, scaling_settings::ScalingSettings)

Validate that `constraint_types` and the nonlinear constraints in `EP` are supported.
"""
function validate_constraint_types(constraint_types, EP::Model, scaling_settings::ScalingSettings)
    if scaling_settings.scale_nonaffine && num_nonlinear_constraints(EP) > 0
        error("Non-scalar-affine constraints are not currently supported by MacroEnergyScaling. Set scale_nonaffine = false to skip these constraints")
    end
    if scaling_settings.scale_nonaffine
        for (function_type, set_type) in constraint_types
            if function_type != VariableRef && !is_scalar_affine_constraint(function_type, set_type)
                error("Non-scalar-affine constraints are not currently supported by MacroEnergyScaling. Set scale_nonaffine = false to skip these constraints")
            end
        end
    end
    return nothing
end

is_scalar_affine_constraint(::Type, ::Type) = false

is_scalar_affine_constraint(::Type{<:AffExpr}, ::Type{<:MOI.LessThan}) = true

is_scalar_affine_constraint(::Type{<:AffExpr}, ::Type{<:MOI.GreaterThan}) = true

is_scalar_affine_constraint(::Type{<:AffExpr}, ::Type{<:MOI.EqualTo}) = true

is_scalar_affine_constraint(::Type{<:AffExpr}, ::Type{<:MOI.Interval}) = true

is_scalar_affine_constraint(::ConstraintRef) = false

is_scalar_affine_constraint(::ConstraintRef{<:AbstractModel,<:MOI.ConstraintIndex{<:MOI.ScalarAffineFunction,<:MOI.LessThan},<:ScalarShape}) = true

is_scalar_affine_constraint(::ConstraintRef{<:AbstractModel,<:MOI.ConstraintIndex{<:MOI.ScalarAffineFunction,<:MOI.GreaterThan},<:ScalarShape}) = true

is_scalar_affine_constraint(::ConstraintRef{<:AbstractModel,<:MOI.ConstraintIndex{<:MOI.ScalarAffineFunction,<:MOI.EqualTo},<:ScalarShape}) = true

is_scalar_affine_constraint(::ConstraintRef{<:AbstractModel,<:MOI.ConstraintIndex{<:MOI.ScalarAffineFunction,<:MOI.Interval},<:ScalarShape}) = true

@doc raw"""
    scale_constraint!(con_ref::ConstraintRef, scaling_settings::ScalingSettings)

Scale the coefficients and RHS of the constraint `con_ref` using the scaling settings `scaling_settings`.
`con_ref` is a JuMP constraint reference.
"""
function scale_constraint!(con_ref::ConstraintRef, scaling_settings::ScalingSettings)
    coeff_lb = scaling_settings.coeff_lb
    coeff_ub = scaling_settings.coeff_ub

    con_obj = constraint_object(con_ref)
    rhs = normalized_rhs(con_ref)
    con_obj, has_nonzero_coefficient, min_coefficient, max_coefficient = constraint_scaling_preflight!(
        con_ref,
        con_obj,
        rhs,
        scaling_settings.constraint_min_coeff,
    )
    if !has_nonzero_coefficient
        return nothing
    end

    # If all the coefficients are within the bounds, we don't need to do anything
    if coeff_lb <= min_coefficient && max_coefficient <= coeff_ub
        return nothing
    end

    # Find the ratio of the maximum and minimum coefficients to the bounds
    # A value > 1 for either indicates that the coefficients are too large or too small
    max_ratio = max_coefficient / coeff_ub
    min_ratio = coeff_lb / min_coefficient

    # If some coefficients are too large, and none too small
    # and dividing by max_ratio will not make any coefficients less than coeff_lb
    if max_ratio > 1 && min_ratio < 1 && min_ratio * max_ratio < 1
        scale_constraint_terms!(con_ref, con_obj.func.terms, 1.0 / max_ratio)
        set_normalized_rhs(con_ref, rhs / max_ratio)
    # Else-if some coefficients are too small, and none too large
    # and multiplying by min_ratio will not make any coefficients greater than coeff_ub
    elseif min_ratio > 1 && max_ratio < 1 && max_ratio * min_ratio < 1
        scale_constraint_terms!(con_ref, con_obj.func.terms, min_ratio)
        set_normalized_rhs(con_ref, rhs * min_ratio)
    # Else we'll update the constraint with proxy variables to scale the coefficients one-by-one
    else
        scale_and_update_constraint!(con_ref, con_obj, rhs, min_coefficient, max_coefficient, scaling_settings)
    end
    return nothing
end

@doc raw"""
    scale_constraint!(con_ref::ConstraintRef, scaling_settings::ScalingSettings)

Scale a scalar-affine interval constraint in place without changing its
`ConstraintRef`. Wide intervals, whose bounds cannot share a scaling
multiplier, are either skipped or rejected according to `scale_wideintervals`.
"""
function scale_constraint!(con_ref::ConstraintRef{<:AbstractModel,<:MOI.ConstraintIndex{<:MOI.ScalarAffineFunction,<:MOI.Interval},<:ScalarShape}, scaling_settings::ScalingSettings)
    con_obj = constraint_object(con_ref)
    interval = con_obj.set
    multiplier = calc_interval_multiplier(interval, scaling_settings.rhs_lb, scaling_settings.rhs_ub)
    if isnothing(multiplier)
        if scaling_settings.scale_wideintervals
            error("Wide interval constraints where the LB and UB must be scaled differently are not currently supported by MacroEnergyScaling. Set scale_wideintervals = false to skip these constraints or break them into two one-sided constraints.\nConstraint: $(con_ref)")
        end
        return nothing
    end
    con_obj, coefficients_need_scaling = interval_scaling_preflight!(
        con_ref,
        con_obj,
        multiplier,
        scaling_settings,
    )
    if multiplier != 1.0 || coefficients_need_scaling
        scale_and_update_terms!(con_ref, con_obj, multiplier, scaling_settings)
    end
    if multiplier != 1.0
        set_interval_bounds!(con_ref, interval.lower * multiplier, interval.upper * multiplier)
    end
    return nothing
end

@doc raw"""
    calc_interval_multiplier(interval::MOI.Interval, rhs_lb::Real, rhs_ub::Real)

Return a positive multiplier that puts both nonzero interval bounds within the
RHS range, or `nothing` if no common multiplier exists.
"""
function calc_interval_multiplier(interval::MOI.Interval, rhs_lb::Real, rhs_ub::Real)
    multiplier_lb = 0.0
    multiplier_ub = Inf
    for bound in (interval.lower, interval.upper)
        magnitude = abs(bound)
        if magnitude > 0.0
            multiplier_lb = max(multiplier_lb, rhs_lb / magnitude)
            multiplier_ub = min(multiplier_ub, rhs_ub / magnitude)
        end
    end
    if multiplier_lb > multiplier_ub
        return nothing
    end
    return clamp(1.0, multiplier_lb, multiplier_ub)
end

function interval_coefficients_need_scaling(con_obj, multiplier::Real, scaling_settings::ScalingSettings)
    for coefficient in con_obj.func.terms.vals
        scaled_magnitude = abs(coefficient * multiplier)
        if scaled_magnitude > 0.0 && !(scaling_settings.coeff_lb <= scaled_magnitude <= scaling_settings.coeff_ub)
            return true
        end
    end
    return false
end

function set_interval_bounds!(con_ref::ConstraintRef, lower::Real, upper::Real)
    MOI.set(owner_model(con_ref), MOI.ConstraintSet(), con_ref, MOI.Interval(lower, upper))
    return nothing
end

@doc raw"""
    scale_constraint_terms!(con_ref::ConstraintRef, terms, multiplier::Real)

Multiply the coefficients in `terms` by `multiplier` in place. Multi-term
constraints use JuMP's batched coefficient-update API; one-term constraints use
the scalar API to avoid allocating batch vectors.
"""
function scale_constraint_terms!(con_ref::ConstraintRef, terms, multiplier::Real)
    if isempty(terms)
        return nothing
    elseif length(terms) == 1
        variable, coefficient = first(terms)
        set_normalized_coefficient(con_ref, variable, coefficient * multiplier)
        return nothing
    end
    variables = Vector{VariableRef}(undef, length(terms))
    coefficients = Vector{Float64}(undef, length(terms))
    for (index, (variable, coefficient)) in enumerate(terms)
        variables[index] = variable
        coefficients[index] = coefficient * multiplier
    end
    set_normalized_coefficient(fill(con_ref, length(terms)), variables, coefficients)
    return nothing
end

@doc raw"""
    constraint_scaling_preflight!(con_ref::ConstraintRef, con_obj, rhs::Real, constraint_min_coeff::Real)

Inspect the terms in `con_obj` once. If `constraint_min_coeff` is positive,
remove terms with smaller nonzero coefficient magnitudes while collecting the
extrema of the retained terms and `rhs`. Return the current constraint object,
whether a nonzero coefficient or RHS was found, and the extrema.
"""
function constraint_scaling_preflight!(con_ref::ConstraintRef, con_obj, rhs::Real, constraint_min_coeff::Real)
    if constraint_min_coeff == 0.0
        has_nonzero_coefficient, min_coefficient, max_coefficient = nonzero_coefficient_extrema(con_obj, rhs)
        return con_obj, has_nonzero_coefficient, min_coefficient, max_coefficient
    end

    variables_to_prune = nothing
    min_coefficient = Inf
    max_coefficient = 0.0
    has_nonzero_coefficient = false
    for (variable, coefficient) in con_obj.func.terms
        magnitude = abs(coefficient)
        if magnitude == 0.0
            continue
        elseif magnitude < constraint_min_coeff
            isnothing(variables_to_prune) && (variables_to_prune = VariableRef[])
            push!(variables_to_prune, variable)
            continue
        elseif !has_nonzero_coefficient
            has_nonzero_coefficient = true
            min_coefficient = magnitude
            max_coefficient = magnitude
        elseif magnitude < min_coefficient
            min_coefficient = magnitude
        elseif magnitude > max_coefficient
            max_coefficient = magnitude
        end
    end
    rhs_magnitude = abs(rhs)
    if rhs_magnitude > 0.0
        if !has_nonzero_coefficient
            has_nonzero_coefficient = true
            min_coefficient = rhs_magnitude
            max_coefficient = rhs_magnitude
        elseif rhs_magnitude < min_coefficient
            min_coefficient = rhs_magnitude
        elseif rhs_magnitude > max_coefficient
            max_coefficient = rhs_magnitude
        end
    end
    if !isnothing(variables_to_prune)
        set_zero_coefficients!(con_ref, variables_to_prune)
        con_obj = constraint_object(con_ref)
    end
    return con_obj, has_nonzero_coefficient, min_coefficient, max_coefficient
end

@doc raw"""
    interval_scaling_preflight!(con_ref::ConstraintRef, con_obj, multiplier::Real, scaling_settings::ScalingSettings)

Inspect interval constraint terms once, removing terms below
`constraint_min_coeff` and determining whether any retained term still needs
scaling after `multiplier` is applied. Return the current constraint object and
whether coefficient scaling is needed.
"""
function interval_scaling_preflight!(con_ref::ConstraintRef, con_obj, multiplier::Real, scaling_settings::ScalingSettings)
    constraint_min_coeff = scaling_settings.constraint_min_coeff
    if constraint_min_coeff == 0.0
        return con_obj, interval_coefficients_need_scaling(con_obj, multiplier, scaling_settings)
    end

    variables_to_prune = nothing
    coefficients_need_scaling = false
    for (variable, coefficient) in con_obj.func.terms
        magnitude = abs(coefficient)
        if magnitude == 0.0
            continue
        elseif magnitude < constraint_min_coeff
            isnothing(variables_to_prune) && (variables_to_prune = VariableRef[])
            push!(variables_to_prune, variable)
        elseif !(scaling_settings.coeff_lb <= magnitude * multiplier <= scaling_settings.coeff_ub)
            coefficients_need_scaling = true
        end
    end
    if !isnothing(variables_to_prune)
        set_zero_coefficients!(con_ref, variables_to_prune)
        con_obj = constraint_object(con_ref)
    end
    return con_obj, coefficients_need_scaling
end

function set_zero_coefficients!(con_ref::ConstraintRef, variables::Vector{VariableRef})
    if length(variables) == 1
        set_normalized_coefficient(con_ref, only(variables), 0.0)
    else
        set_normalized_coefficient(fill(con_ref, length(variables)), variables, fill(0.0, length(variables)))
    end
    return nothing
end

@doc raw"""
    nonzero_coefficient_extrema(con_obj, rhs)

Return whether a nonzero coefficient was found, followed by the smallest and
largest nonzero coefficient magnitudes in `con_obj`, including `rhs`.
"""
function nonzero_coefficient_extrema(con_obj, rhs)
    min_coefficient = Inf
    max_coefficient = 0.0
    has_nonzero_coefficient = false
    for coefficient in con_obj.func.terms.vals
        magnitude = abs(coefficient)
        if magnitude > 0.0
            if !has_nonzero_coefficient
                has_nonzero_coefficient = true
                min_coefficient = magnitude
                max_coefficient = magnitude
            elseif magnitude < min_coefficient
                min_coefficient = magnitude
            elseif magnitude > max_coefficient
                max_coefficient = magnitude
            end
        end
    end
    rhs_magnitude = abs(rhs)
    if rhs_magnitude > 0.0
        if !has_nonzero_coefficient
            has_nonzero_coefficient = true
            min_coefficient = rhs_magnitude
            max_coefficient = rhs_magnitude
        elseif rhs_magnitude < min_coefficient
            min_coefficient = rhs_magnitude
        elseif rhs_magnitude > max_coefficient
            max_coefficient = rhs_magnitude
        end
    end
    return has_nonzero_coefficient, min_coefficient, max_coefficient
end

@doc raw"""
    scale_and_update_constraint!(con_ref::ConstraintRef, con_obj, rhs::Real, min_coefficient::Real, max_coefficient::Real, scaling_settings::ScalingSettings)

Scale the coefficients and RHS of the constraint `con_ref` using the scaling settings `scaling_settings`
without changing its `ConstraintRef`.

First we check if we can scale the right-hand side constant without creating proxy variables.
Next, we iterate over the variable-coefficient pairs and scale them using proxy variables if necessary.
The scaled variable-coefficient pairs are then applied to the original constraint in place.
"""
function scale_and_update_constraint!(con_ref::ConstraintRef, con_obj, rhs::Real, min_coefficient::Real, max_coefficient::Real, scaling_settings::ScalingSettings)
    # First we want to check if we need to scale the RHS constant
    # We'd like to do this without making it impossible to scale some coefficients with proxy variables
    rhs_multiplier = calc_rhs_multiplier(rhs, scaling_settings.rhs_lb, scaling_settings.rhs_ub, scaling_settings.coeff_lb, scaling_settings.coeff_ub, min_coefficient, max_coefficient)

    scale_and_update_terms!(con_ref, con_obj, rhs_multiplier, scaling_settings)
    if rhs_multiplier != 1.0
        set_normalized_rhs(con_ref, rhs * rhs_multiplier)
    end
    return nothing
end

@doc raw"""
    scale_and_update_terms!(con_ref::ConstraintRef, con_obj, multiplier::Real, scaling_settings::ScalingSettings)

Scale the terms in `con_obj` by `multiplier`, using proxy variables for terms
which cannot be brought into the coefficient range with that multiplier.
"""
function scale_and_update_terms!(con_ref::ConstraintRef, con_obj, multiplier::Real, scaling_settings::ScalingSettings)
    var_coeff_pairs = con_obj.func.terms
    new_var_coeff_pairs = OrderedDict{VariableRef, Float64}()

    for (var, coeff) in var_coeff_pairs
        if coeff == 0.0 || (scaling_settings.coeff_lb <= (abs(coeff) * multiplier) <= scaling_settings.coeff_ub)
            new_var_coeff_pairs[var] = coeff * multiplier
            continue
        end
        updated_var, updated_coeff = scaled_var_coeff_pair(
            var,
            coeff * multiplier,
            scaling_settings.coeff_lb,
            scaling_settings.coeff_ub,
            scaling_settings.constraint_max_proxy_depth,
            scaling_settings,
        )
        new_var_coeff_pairs[updated_var] = updated_coeff
    end
    update_scaled_terms!(con_ref, var_coeff_pairs, new_var_coeff_pairs)
    return nothing
end

@doc raw"""
    update_scaled_terms!(con_ref::ConstraintRef, original_var_coeff_pairs, scaled_var_coeff_pairs::AbstractDict{VariableRef, Float64})

Update the terms of `con_ref` in place using the scaled variable-coefficient pairs.
Only terms which changed, were added, or were removed are modified. This preserves the
identity and validity of `con_ref`.
"""
function update_scaled_terms!(con_ref::ConstraintRef, original_var_coeff_pairs, scaled_var_coeff_pairs::AbstractDict{VariableRef, Float64})
    original_coefficients = Dict(original_var_coeff_pairs)
    variables = VariableRef[]
    coefficients = Float64[]
    for (var, scaled_coeff) in scaled_var_coeff_pairs
        if !haskey(original_coefficients, var) || original_coefficients[var] != scaled_coeff
            push!(variables, var)
            push!(coefficients, scaled_coeff)
        end
        delete!(original_coefficients, var)
    end
    for (var, original_coeff) in original_coefficients
        if original_coeff != 0.0
            push!(variables, var)
            push!(coefficients, 0.0)
        end
    end
    if !isempty(variables)
        set_normalized_coefficient(fill(con_ref, length(variables)), variables, coefficients)
    end
    return nothing
end

@doc raw"""
    calc_rhs_multiplier(con_obj, rhs::Real, rhs_lb::Real, rhs_ub::Real, coeff_lb::Real, coeff_ub::Real)

Calculate the multiplier that keeps `rhs` compatible with the coefficient bounds in `con_obj` and the RHS bounds `rhs_lb` and `rhs_ub`.
"""
function calc_rhs_multiplier(con_obj, rhs::Real, rhs_lb::Real, rhs_ub::Real, coeff_lb::Real, coeff_ub::Real)
    _, min_coefficient, max_coefficient = nonzero_coefficient_extrema(con_obj, rhs)
    return calc_rhs_multiplier(rhs, rhs_lb, rhs_ub, coeff_lb, coeff_ub, min_coefficient, max_coefficient)
end

function calc_rhs_multiplier(rhs::Real, rhs_lb::Real, rhs_ub::Real, coeff_lb::Real, coeff_ub::Real, min_coefficient::Real, max_coefficient::Real)
    iszero(rhs) && return 1.0
    abs_rhs = abs(rhs)
    if rhs_lb <= abs_rhs <= rhs_ub
        return 1.0
    end
    if abs_rhs > rhs_ub
        return max(1.0 / abs_rhs, coeff_lb / coeff_ub / min_coefficient)
    end
    if abs_rhs < rhs_lb
        return min(1.0 / abs_rhs, coeff_ub / coeff_lb / max_coefficient)
    end
end
