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

function get_scaling_settings(settings::Dict)
    scaling_settings = Dict{String, Any}()
    for scaling_setting in [String(x) for x in fieldnames(ScalingSettings)]
        if haskey(settings, scaling_setting)
            scaling_settings[scaling_setting] = settings[scaling_setting]
        end
    end
    return ScalingSettings(; scaling_settings...)
end