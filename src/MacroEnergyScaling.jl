module MacroEnergyScaling

export scale_constraints!
export scale_objective!
export get_scaling_settings

using JuMP
using OrderedCollections
using MathOptInterface
const MOI = MathOptInterface

src_dir = @__DIR__

include(joinpath(src_dir, "scaling_settings.jl"))
include(joinpath(src_dir, "scaling_utilities.jl"))
include(joinpath(src_dir, "constraint_scaling.jl"))
include(joinpath(src_dir, "objective_scaling.jl"))

end
