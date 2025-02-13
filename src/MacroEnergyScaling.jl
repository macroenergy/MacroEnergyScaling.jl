module MacroEnergyScaling

export scale_constraints!
export get_scaling_settings

using JuMP
using OrderedCollections
using MathOptInterface
const MOI = MathOptInterface

src_dir = @__DIR__

include(joinpath(src_dir, "scaling_settings.jl"))
include(joinpath(src_dir, "model_scaling.jl"))

end