@doc raw"""
    ScalingSettings

A structure to store the scaling settings for the scaling algorithm. The fields are:
    coeff_lb::Float64 = 1e-3: Lower bound for the scaling coefficients.
    coeff_ub::Float64 = 1e6: Upper bound for the scaling coefficients.
    min_coeff::Float64 = 1e-9: Minimum value for the scaling coefficients.
    rhs_lb::Float64 = 1e-3: Lower bound for the right-hand side scaling.
    rhs_ub::Float64 = 1e6: Upper bound for the right-hand side scaling.
    allow_recursion::Bool = true: Whether to allow recursion in the scaling algorithm.
    count_actions::Bool = false: Whether to count the number of scaling actions.
    proxy_var_ratio_ub::Float64 = 10.0: Upper bound for the ratio of proxy variables to variables.
    proxy_var_map::Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}} = Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}}(): A dictionary mapping variables to a vector of tuples of variables and scaling coefficients.
"""
@Base.kwdef mutable struct ScalingSettings
    coeff_lb::Float64 = 1e-3
    coeff_ub::Float64 = 1e6
    min_coeff::Float64 = 1e-9
    rhs_lb::Float64 = 1e-3
    rhs_ub::Float64 = 1e6
    allow_recursion::Bool = true
    count_actions::Bool = false
    proxy_var_ratio_ub::Float64 = 10.0  
    proxy_var_map::Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}} = Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}}()
end

@doc raw"""
    get_scaling_settings(settings::Dict)::ScalingSettings

Extracts the scaling settings from a dictionary and returns a `ScalingSettings` object.
"""
function get_scaling_settings(settings::Dict)::ScalingSettings
    scaling_settings = Dict{String, Any}()
    for scaling_setting in [String(x) for x in fieldnames(ScalingSettings)]
        if haskey(settings, scaling_setting)
            scaling_settings[scaling_setting] = settings[scaling_setting]
        end
    end
    return ScalingSettings(; scaling_settings...)
end