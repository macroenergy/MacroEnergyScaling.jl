using Test
using Gurobi
using JuMP
using MacroEnergyScaling

include(joinpath(@__DIR__, "..", "direct_model_contract.jl"))

test_direct_model_scaling(Gurobi.Optimizer)

const MES = MacroEnergyScaling
include(joinpath(@__DIR__, "..", "constraint_scaling_factors.jl"))
test_constraint_scaling_factors(Gurobi.Optimizer)
