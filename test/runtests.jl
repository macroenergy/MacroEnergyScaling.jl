using Test
using HiGHS
using JuMP
using MacroEnergyScaling

const MES = MacroEnergyScaling

function coefficient_values(con_ref)
    terms = JuMP.constraint_object(con_ref).func.terms
    return collect(values(terms))
end

function objective_coefficient(model, variable)
    objective = JuMP.objective_function(model, JuMP.AffExpr)
    return get(objective.terms, variable, 0.0)
end

include("direct_model_contract.jl")

@testset "MacroEnergyScaling" begin
    @testset "scaling settings validation" begin
        @test_throws ArgumentError MES.ScalingSettings(coeff_lb = 0.0)
        @test_throws ArgumentError MES.ScalingSettings(coeff_lb = 2.0, coeff_ub = 1.0)
        @test_throws ArgumentError MES.ScalingSettings(rhs_lb = 0.0)
        @test_throws ArgumentError MES.ScalingSettings(constraint_min_coeff = 1.0e-2)
        @test_throws ArgumentError MES.ScalingSettings(proxy_multiplier_reuse_ratio = 1.0)
        @test_throws ArgumentError MES.ScalingSettings(objective_coeff_lb = 0.0)
        @test_throws ArgumentError MES.ScalingSettings(objective_min_coeff = 1.0e-2)
        @test_throws ArgumentError MES.ScalingSettings(objective_scaling_factor = 0.0)
        @test MES.ScalingSettings().scale_wideintervals
        @test MES.ScalingSettings().constraint_min_coeff == 0.0
        @test MES.ScalingSettings().constraint_max_proxy_depth == -1
        @test MES.ScalingSettings().objective_max_proxy_depth == -1
        @test MES.ScalingSettings().objective_min_coeff == 0.0
        @test MES.ScalingSettings().objective_scaling_factor == 1.0

        legacy_settings = MES.ScalingSettings(
            1.0e-3,
            1.0e6,
            1.0e-9,
            1.0e-3,
            1.0e6,
            -1,
            true,
            true,
            10.0,
            Dict{VariableRef, Vector{Tuple{VariableRef, Float64}}}(),
        )
        @test legacy_settings.objective_coeff_lb == 1.0e-3
        @test legacy_settings.objective_coeff_ub == 1.0e6

        settings = MES.ScalingSettings()
        settings.coeff_lb = 0.0
        @test_throws ArgumentError MES.scale_constraints!(Model(), settings)
    end

    @testset "in-place scaling" begin
        model = Model(HiGHS.Optimizer)
        @variable(model, x)
        con = @constraint(model, 1.0e8 * x <= 1.0e7)

        settings = MES.ScalingSettings()
        @test MES.scale_constraints!(model, settings) === nothing
        @test JuMP.is_valid(model, con)
        @test coefficient_values(con) == [1.0e6]
        @test JuMP.normalized_rhs(con) == 1.0e5
    end

    @testset "batched in-place scaling" begin
        model = Model(HiGHS.Optimizer)
        @variable(model, x[1:2])
        con = @constraint(model, 1.0e8 * x[1] + 1.0e8 * x[2] <= 1.0e7)

        @test MES.scale_constraints!(model) === nothing
        @test JuMP.is_valid(model, con)
        @test coefficient_values(con) == [1.0e6, 1.0e6]
        @test JuMP.normalized_rhs(con) == 1.0e5
    end

    @testset "constraint coefficient pruning" begin
        pruned_model = Model()
        @variable(pruned_model, pruned_x)
        @variable(pruned_model, pruned_y)
        pruned_con = @constraint(pruned_model, 1.0e-9 * pruned_x + 2.0 * pruned_y <= 4.0)
        pruning_settings = MES.ScalingSettings(constraint_min_coeff = 1.0e-8)

        @test MES.scale_constraints!(pruned_model, pruning_settings) === nothing
        @test JuMP.is_valid(pruned_model, pruned_con)
        @test JuMP.normalized_coefficient(pruned_con, pruned_x) == 0.0
        @test JuMP.normalized_coefficient(pruned_con, pruned_y) == 2.0
        @test isempty(pruning_settings.proxy_var_map)

        interval_model = Model()
        @variable(interval_model, interval_x)
        @variable(interval_model, interval_y)
        interval_con = @constraint(interval_model, 1.0 <= 1.0e-9 * interval_x + 2.0 * interval_y <= 4.0)
        interval_settings = MES.ScalingSettings(constraint_min_coeff = 1.0e-8)

        @test MES.scale_constraints!(interval_model, interval_settings) === nothing
        @test JuMP.is_valid(interval_model, interval_con)
        @test JuMP.normalized_coefficient(interval_con, interval_x) == 0.0
        @test JuMP.normalized_coefficient(interval_con, interval_y) == 2.0
        @test isempty(interval_settings.proxy_var_map)

        retained_model = Model()
        @variable(retained_model, retained_x)
        @variable(retained_model, retained_y)
        retained_con = @constraint(retained_model, 1.0e-20 * retained_x + retained_y <= 1.0)
        retained_settings = MES.ScalingSettings()

        @test MES.scale_constraints!(retained_model, retained_settings) === nothing
        @test JuMP.is_valid(retained_model, retained_con)
        @test haskey(retained_settings.proxy_var_map, retained_x)

        depth_zero_model = Model()
        @variable(depth_zero_model, depth_zero_x)
        @constraint(depth_zero_model, 1.0e-20 * depth_zero_x <= 1.0)
        depth_zero_settings = MES.ScalingSettings(constraint_max_proxy_depth = 0)

        @test MES.scale_constraints!(depth_zero_model, depth_zero_settings) === nothing
        @test JuMP.num_variables(depth_zero_model) == 1

        depth_one_model = Model()
        @variable(depth_one_model, depth_one_x)
        @constraint(depth_one_model, 1.0e-20 * depth_one_x <= 1.0)
        depth_one_settings = MES.ScalingSettings(constraint_max_proxy_depth = 1)

        @test MES.scale_constraints!(depth_one_model, depth_one_settings) === nothing
        @test JuMP.num_variables(depth_one_model) == 2
    end

    test_direct_model_scaling(HiGHS.Optimizer)

    @testset "objective scaling" begin
        no_op_model = Model()
        @variable(no_op_model, no_op_x)
        @objective(no_op_model, Min, 2.0 * no_op_x)
        no_op_settings = MES.ScalingSettings(scale_objective_uniformly = true)
        @test MES.scale_objective!(no_op_model, no_op_settings) === nothing
        @test JuMP.num_variables(no_op_model) == 1
        @test isempty(no_op_settings.proxy_var_map)
        @test no_op_settings.objective_scaling_factor == 1.0

        model = Model(HiGHS.Optimizer)
        @variable(model, x)
        @variable(model, y)
        @objective(model, Min, 1.0e9 * x - 1.0e-9 * y + 7.0)

        @test MES.scale_objective!(model) === nothing
        objective = JuMP.objective_function(model, JuMP.AffExpr)
        @test objective.constant == 7.0
        @test objective_coefficient(model, x) == 0.0
        @test objective_coefficient(model, y) == 0.0
        @test all(1.0e-3 <= abs(coeff) <= 1.0e6 for coeff in values(objective.terms))

        variable_model = Model()
        @variable(variable_model, variable_x)
        @objective(variable_model, Min, 1.0e9 * variable_x)
        @test MES.scale_objective!(variable_model) === nothing
        @test objective_coefficient(variable_model, variable_x) == 0.0

        depth_zero_objective_model = Model()
        @variable(depth_zero_objective_model, depth_zero_objective_x)
        @objective(depth_zero_objective_model, Min, 1.0e-20 * depth_zero_objective_x)
        depth_zero_objective_settings = MES.ScalingSettings(objective_max_proxy_depth = 0)

        @test MES.scale_objective!(depth_zero_objective_model, depth_zero_objective_settings) === nothing
        @test JuMP.num_variables(depth_zero_objective_model) == 1

        constant_model = Model()
        @variable(constant_model, constant_x)
        @objective(constant_model, Min, 7.0)
        @test MES.scale_objective!(constant_model) === nothing
        @test JuMP.objective_function(constant_model, JuMP.AffExpr).constant == 7.0
        @test JuMP.num_variables(constant_model) == 1

        prune_model = Model()
        @variable(prune_model, prune_x)
        @variable(prune_model, prune_y)
        @objective(prune_model, Min, 1.0e-12 * prune_x + 2.0 * prune_y + 7.0)
        prune_settings = MES.ScalingSettings(objective_min_coeff = 1.0e-9)
        @test MES.scale_objective!(prune_model, prune_settings) === nothing
        @test objective_coefficient(prune_model, prune_x) == 0.0
        @test objective_coefficient(prune_model, prune_y) == 2.0
        @test JuMP.objective_function(prune_model, JuMP.AffExpr).constant == 7.0

        prune_uniform_model = Model()
        @variable(prune_uniform_model, prune_uniform_x)
        @variable(prune_uniform_model, prune_uniform_y)
        @objective(prune_uniform_model, Min, 1.0e8 * prune_uniform_x + 1.0e-12 * prune_uniform_y + 7.0)
        prune_uniform_settings = MES.ScalingSettings(
            objective_min_coeff = 1.0e-9,
            scale_objective_uniformly = true,
        )
        @test MES.scale_objective!(prune_uniform_model, prune_uniform_settings) === nothing
        @test objective_coefficient(prune_uniform_model, prune_uniform_x) == 1.0e6
        @test objective_coefficient(prune_uniform_model, prune_uniform_y) == 0.0
        @test JuMP.objective_function(prune_uniform_model, JuMP.AffExpr).constant == 0.07
        @test prune_uniform_settings.objective_scaling_factor == 1.0e-2
        @test JuMP.num_variables(prune_uniform_model) == 2

        reuse_model = Model()
        @variable(reuse_model, reuse_x)
        reuse_settings = MES.ScalingSettings()
        @objective(reuse_model, Min, 1.0e-9 * reuse_x)
        MES.scale_objective!(reuse_model, reuse_settings)
        first_proxy = only(reuse_settings.proxy_var_map[reuse_x])[1]
        @objective(reuse_model, Min, 2.0e-9 * reuse_x)
        MES.scale_objective!(reuse_model, reuse_settings)
        @test JuMP.num_variables(reuse_model) == 2
        @test objective_coefficient(reuse_model, first_proxy) == 2.0e-3

        function uniform_objective_model()
            uniform_model = Model(HiGHS.Optimizer)
            @variable(uniform_model, uniform_x >= 0)
            @variable(uniform_model, uniform_y >= 0)
            @constraint(uniform_model, uniform_x + uniform_y >= 1.0)
            @objective(uniform_model, Min, 1.0e8 * uniform_x + 1.0e7 * uniform_y + 2.0)
            return uniform_model, uniform_x, uniform_y
        end
        uniform_original, uniform_original_x, uniform_original_y = uniform_objective_model()
        optimize!(uniform_original)
        uniform_original_value = objective_value(uniform_original)
        uniform_scaled, uniform_scaled_x, uniform_scaled_y = uniform_objective_model()
        uniform_settings = MES.ScalingSettings(scale_objective_uniformly = true)
        MES.scale_objective!(uniform_scaled, uniform_settings)
        @test uniform_settings.objective_scaling_factor == 1.0e-2
        @test JuMP.num_variables(uniform_scaled) == 2
        @test JuMP.objective_function(uniform_scaled, JuMP.AffExpr).constant == 2.0e-2
        optimize!(uniform_scaled)
        @test isapprox(
            objective_value(uniform_scaled),
            uniform_settings.objective_scaling_factor * uniform_original_value;
            atol = 1.0e-8,
        )
        @test isapprox(value(uniform_scaled_x), value(uniform_original_x); atol = 1.0e-8)
        @test isapprox(value(uniform_scaled_y), value(uniform_original_y); atol = 1.0e-8)
        MES.scale_objective!(uniform_scaled, uniform_settings)
        @test uniform_settings.objective_scaling_factor == 1.0e-2

        cumulative_factor_model = Model()
        @variable(cumulative_factor_model, cumulative_factor_x)
        @objective(cumulative_factor_model, Min, 1.0e8 * cumulative_factor_x)
        cumulative_factor_settings = MES.ScalingSettings(
            scale_objective_uniformly = true,
            objective_scaling_factor = 2.0,
        )
        MES.scale_objective!(cumulative_factor_model, cumulative_factor_settings)
        @test cumulative_factor_settings.objective_scaling_factor == 2.0e-2

        hybrid_model = Model()
        @variable(hybrid_model, hybrid_x)
        @variable(hybrid_model, hybrid_y)
        @objective(hybrid_model, Min, 1.0e12 * hybrid_x + 1.0e-9 * hybrid_y + 4.0)
        hybrid_settings = MES.ScalingSettings(scale_objective_uniformly = true)
        @test MES.scale_objective!(hybrid_model, hybrid_settings) === nothing
        @test hybrid_settings.objective_scaling_factor == 1.0e-6
        @test JuMP.num_variables(hybrid_model) == 4
        @test JuMP.objective_function(hybrid_model, JuMP.AffExpr).constant == 4.0e-6

        proxy_only_model = Model()
        @variable(proxy_only_model, proxy_only_x)
        @variable(proxy_only_model, proxy_only_y)
        @objective(proxy_only_model, Min, 1.0e12 * proxy_only_x + 1.0e-9 * proxy_only_y + 4.0)
        MES.scale_objective!(proxy_only_model)
        @test JuMP.num_variables(proxy_only_model) == 5

        function objective_scale_model()
            objective_model = Model(HiGHS.Optimizer)
            @variable(objective_model, objective_x >= 0)
            @variable(objective_model, objective_y >= 0)
            @constraint(objective_model, objective_x + objective_y >= 1.0)
            @objective(objective_model, Min, 1.0e9 * objective_x + 1.0e-9 * objective_y + 3.0)
            return objective_model, objective_x, objective_y
        end
        original, original_x, original_y = objective_scale_model()
        optimize!(original)
        original_objective = objective_value(original)
        scaled, scaled_x, scaled_y = objective_scale_model()
        workflow_settings = MES.ScalingSettings()
        MES.scale_objective!(scaled, workflow_settings)
        MES.scale_constraints!(scaled, workflow_settings)
        optimize!(scaled)
        @test isapprox(objective_value(scaled), original_objective; atol = 1.0e-8)
        @test isapprox(value(scaled_x), value(original_x); atol = 1.0e-8)
        @test isapprox(value(scaled_y), value(original_y); atol = 1.0e-8)

        feasibility_model = Model()
        @test MES.scale_objective!(feasibility_model) === nothing

        quadratic_model = Model()
        @variable(quadratic_model, quadratic_x)
        @objective(quadratic_model, Min, quadratic_x^2)
        @test_throws ErrorException MES.scale_objective!(quadratic_model)

        nonlinear_model = Model()
        @variable(nonlinear_model, nonlinear_x)
        @objective(nonlinear_model, Min, sin(nonlinear_x))
        @test_throws ErrorException MES.scale_objective!(nonlinear_model)
    end

    @testset "interval constraints" begin
        model = Model(HiGHS.Optimizer)
        @variable(model, x)
        con = @constraint(model, 1.0e-8 <= 1.0e-8 * x <= 1.0e-6)

        @test MES.scale_constraints!(model) === nothing
        @test JuMP.is_valid(model, con)
        @test coefficient_values(con) == [1.0e-3]
        interval = JuMP.constraint_object(con).set
        @test interval.lower ≈ 1.0e-3
        @test interval.upper ≈ 1.0e-1

        proxy_model = Model(HiGHS.Optimizer)
        @variable(proxy_model, x)
        @variable(proxy_model, y)
        proxy_con = @constraint(proxy_model, 1.0 <= 1.0e9 * x + 1.0e-9 * y <= 2.0)
        @test MES.scale_constraints!(proxy_model) === nothing
        @test JuMP.is_valid(proxy_model, proxy_con)
        @test JuMP.normalized_coefficient(proxy_con, x) == 0.0
        @test JuMP.normalized_coefficient(proxy_con, y) == 0.0

        wide_model = Model(HiGHS.Optimizer)
        @variable(wide_model, z)
        wide_con = @constraint(wide_model, 1.0e-9 <= 1.0 * z <= 1.0e9)
        expected_message = "Wide interval constraints where the LB and UB must be scaled differently are not currently supported by MacroEnergyScaling. Set scale_wideintervals = false to skip these constraints or break them into two one-sided constraints."
        error = try
            MES.scale_constraints!(wide_model)
            nothing
        catch caught_error
            caught_error
        end
        @test error isa ErrorException
        @test startswith(sprint(showerror, error), expected_message)
        @test occursin(string(wide_con), sprint(showerror, error))
        @test JuMP.is_valid(wide_model, wide_con)
        @test JuMP.constraint_object(wide_con).set.lower == 1.0e-9
        @test MES.scale_constraints!(wide_model, MES.ScalingSettings(scale_wideintervals = false)) === nothing
        @test JuMP.constraint_object(wide_con).set.upper == 1.0e9
    end

    @testset "scaling inspection does not mutate a constraint expression" begin
        model = Model(HiGHS.Optimizer)
        @variable(model, x)
        con = @constraint(model, 2.0 * x <= 4.0)
        terms = JuMP.constraint_object(con).func.terms
        original_storage_length = length(terms.vals)

        MES.scale_constraints!(model)
        @test length(terms.vals) == original_storage_length
        @test length(terms.vals) == length(terms)
    end

    @testset "RHS boundary values are valid during rebuild" begin
        model = Model(HiGHS.Optimizer)
        @variable(model, x)
        # The coefficient forces the proxy/rebuild path while the RHS is exactly rhs_lb.
        @constraint(model, 1.0e9 * x <= 1.0e-3)

        @test_nowarn MES.scale_constraints!(model)
    end

    @testset "zero RHS does not trigger global scaling" begin
        model = Model(HiGHS.Optimizer)
        @variable(model, x)
        @variable(model, y)
        con = @constraint(model, 1.0e6 * x + 1.0e-9 * y <= 0.0)
        settings = MES.ScalingSettings()

        @test MES.calc_rhs_multiplier(
            JuMP.constraint_object(con),
            JuMP.normalized_rhs(con),
            settings.rhs_lb,
            settings.rhs_ub,
            settings.coeff_lb,
            settings.coeff_ub,
        ) == 1.0
        @test MES.scale_constraints!(model, settings) === nothing
        @test JuMP.is_valid(model, con)
        @test JuMP.normalized_rhs(con) == 0.0
        @test JuMP.normalized_coefficient(con, x) == 1.0e6
        @test JuMP.normalized_coefficient(con, y) == 0.0
    end

    @testset "non-scalar-affine constraints" begin
        expected_message = "Non-scalar-affine constraints are not currently supported by MacroEnergyScaling. Set scale_nonaffine = false to skip these constraints"

        model = Model()
        @variable(model, x)
        @variable(model, y)
        affine_con = @constraint(model, 1.0e8 * x <= 1.0e7)
        quadratic_con = @constraint(model, y^2 <= 1.0)

        error = try
            MES.scale_constraints!(model)
            nothing
        catch caught_error
            caught_error
        end
        @test error isa ErrorException
        @test sprint(showerror, error) == expected_message
        @test JuMP.normalized_coefficient(affine_con, x) == 1.0e8
        @test_throws ArgumentError MES.scale_constraints!(ConstraintRef[affine_con, quadratic_con])
        @test JuMP.normalized_coefficient(affine_con, x) == 1.0e8

        settings = MES.ScalingSettings(scale_nonaffine = false)
        @test MES.scale_constraints!(model, settings) === nothing
        @test JuMP.normalized_coefficient(affine_con, x) == 1.0e6
        @test JuMP.is_valid(model, quadratic_con)
        @test_throws ErrorException MES.scale_constraints!([quadratic_con])
        @test MES.scale_constraints!([quadratic_con], settings) === nothing

        nonlinear_model = Model()
        @variable(nonlinear_model, z)
        @constraint(nonlinear_model, sin(z) <= 1.0)
        @test_throws ErrorException MES.scale_constraints!(nonlinear_model)
        @test_nowarn MES.scale_constraints!(nonlinear_model, MES.ScalingSettings(scale_nonaffine = false))
    end

    @testset "proxy scaling preserves an optimum" begin
        function mixed_scale_model()
            model = Model(HiGHS.Optimizer)
            @variable(model, x >= 0)
            @variable(model, y == 0)
            @constraint(model, 1.0e9 * x + 1.0e-9 * y >= 1.0)
            @objective(model, Min, x)
            return model, x
        end

        original, original_x = mixed_scale_model()
        optimize!(original)
        original_objective = objective_value(original)
        original_x_value = value(original_x)

        scaled, scaled_x = mixed_scale_model()
        MES.scale_constraints!(scaled)
        optimize!(scaled)

        @test isapprox(objective_value(scaled), original_objective; atol = 1e-12)
        @test isapprox(value(scaled_x), original_x_value; atol = 1e-12)
    end

    @testset "rebuilding preserves the original ConstraintRef" begin
        model = Model(HiGHS.Optimizer)
        @variable(model, x)
        @variable(model, y)
        # Coefficients on both sides of the allowed range require proxy variables.
        con = @constraint(model, 1.0e9 * x + 1.0e-9 * y <= 1.0)

        MES.scale_constraints!(model)

        @test JuMP.is_valid(model, con)
        @test JuMP.name(con) == ""
        @test JuMP.normalized_coefficient(con, x) == 0.0
        @test JuMP.normalized_coefficient(con, y) == 0.0
        @test JuMP.normalized_rhs(con) == 1.0
    end
end
