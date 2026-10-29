# Structural checks do not need an optimizer. Numerical checks can be reused
# by the package's HiGHS and optional Gurobi test environments.
function test_constraint_scaling_factors(optimizer)
    @testset "constraint scaling factors" begin
        test_constraint_factor_rejection()
        @testset "uniform rows and zero RHS" begin
            for set_type in (JuMP.MOI.LessThan, JuMP.MOI.GreaterThan, JuMP.MOI.EqualTo)
                for (coefficient, rhs, expected) in ((1e8, 1e7, 0.01), (1e-8, 1e-7, 1e5), (1e8, 0.0, 0.01))
                    model = Model()
                    @variable(model, x)
                    row = @constraint(model, coefficient * x in set_type(rhs))
                    settings = MES.ScalingSettings()
                    @test isempty(settings.constraint_scaling_factors)
                    @test MES.scale_constraints!(model, settings) === nothing
                    @test settings.constraint_scaling_factors[row] ≈ expected
                    @test normalized_coefficient(row, x) ≈ coefficient * expected
                    @test normalized_rhs(row) ≈ rhs * expected
                    @test MES.scale_constraints!([row], settings) === nothing
                    @test settings.constraint_scaling_factors[row] ≈ expected
                end
            end
        end

        @testset "cumulative factors and independent settings" begin
            model = Model()
            @variable(model, x)
            row = @constraint(model, 1e8 * x <= 1e7)
            settings = MES.ScalingSettings()
            MES.scale_constraints!([row], settings)
            settings.coeff_ub = 1e4
            settings.rhs_ub = 1e4
            MES.scale_constraints!([row], settings)
            @test settings.constraint_scaling_factors[row] ≈ 1e-4
            @test normalized_coefficient(row, x) ≈ 1e4
            @test isempty(MES.ScalingSettings().constraint_scaling_factors)
            @test isempty(MES.get_scaling_settings(Dict()).constraint_scaling_factors)
        end

        @testset "sparse recording and proxy rows" begin
            for (coefficient, rhs) in ((2.0, 4.0), (1e9, 1.0))
                model = Model()
                @variable(model, x)
                @variable(model, y)
                row = @constraint(model, coefficient * x + 1e-9 * y <= rhs)
                settings = MES.ScalingSettings()
                MES.scale_constraints!(model, settings)
                @test !haskey(settings.constraint_scaling_factors, row)
                @test get(settings.constraint_scaling_factors, row, 1.0) == 1.0
                @test num_variables(model) > 2
            end
            model = Model()
            @variable(model, x)
            @variable(model, y)
            row = @constraint(model, 1e9 * x + 1e-4 * y <= 1e9)
            settings = MES.ScalingSettings()
            MES.scale_constraints!(model, settings)
            @test num_variables(model) > 2
            @test settings.constraint_scaling_factors[row] ≈ normalized_rhs(row) / 1e9
            @test settings.constraint_scaling_factors[row] != 1.0

            untouched = Model()
            @variable(untouched, z)
            @constraint(untouched, 2.0 * z <= 4.0)
            unchanged = MES.ScalingSettings()
            MES.scale_constraints!(untouched, unchanged)
            @test isempty(unchanged.constraint_scaling_factors)
        end

        @testset "intervals and skipped rows" begin
            model = Model()
            @variable(model, x)
            @variable(model, y)
            row = @constraint(model, 1e-8 <= 1e-8 * x <= 1e-6)
            hybrid = @constraint(model, 1e8 <= 1e9 * x + 1e-4 * y <= 1e9)
            wide = @constraint(model, 1e-9 <= x <= 1e9)
            settings = MES.ScalingSettings(scale_wideintervals=false)
            MES.scale_constraints!(model, settings)
            @test settings.constraint_scaling_factors[row] ≈ 1e5
            @test settings.constraint_scaling_factors[hybrid] ≈ 1e-3
            @test constraint_object(hybrid).set.upper ≈ 1e6
            @test !haskey(settings.constraint_scaling_factors, wide)
            @test num_variables(model) > 2
        end

        @testset "original-unit duals with row and objective scaling" begin
            for direct in (false, true), uniform_objective in (false, true), rhs in (0.0, 1e7)
                model = if direct
                    direct_model(optimizer())
                else
                    Model(optimizer)
                end
                set_silent(model)
                @variable(model, x)
                row = @constraint(model, 1e8 * x <= rhs)
                @objective(model, Min, -1e8 * x)
                settings = MES.ScalingSettings(scale_objective_uniformly=uniform_objective)
                MES.scale_objective!(model, settings)
                MES.scale_constraints!(model, settings)
                optimize!(model)
                @test termination_status(model) == JuMP.MOI.OPTIMAL
                factor = get(settings.constraint_scaling_factors, row, 1.0)
                @test factor ≈ 0.01
                @test factor * dual(row) / settings.objective_scaling_factor ≈ -1.0
                @test objective_value(model) / settings.objective_scaling_factor ≈ -rhs atol=1e-7
                # Independently perturb the original RHS through its scaled row.
                old_cost = objective_value(model) / settings.objective_scaling_factor
                delta = 100.0
                set_normalized_rhs(row, (rhs + delta) * factor)
                optimize!(model)
                @test termination_status(model) == JuMP.MOI.OPTIMAL
                sensitivity = (objective_value(model) / settings.objective_scaling_factor - old_cost) / delta
                @test sensitivity ≈ -1.0
            end
        end
    end
end

# A rejected cumulative multiplier must leave the row and factor consistent,
# including on retry. Proxy creation must not happen before this validation.
function test_rejected_constraint_factor(model, row, settings)
    original_function = copy(constraint_object(row).func)
    original_set = constraint_object(row).set
    original_factors = copy(settings.constraint_scaling_factors)
    original_proxies = Dict(variable => copy(proxies) for (variable, proxies) in settings.proxy_var_map)
    original_variables = num_variables(model)
    original_constraints = num_constraints(model; count_variable_in_set_constraints=true)
    for _ in 1:2
        @test_throws r"The cumulative constraint scaling factor must remain finite and positive" MES.scale_constraints!([row], settings)
        @test isequal(constraint_object(row).func, original_function)
        @test isequal(constraint_object(row).set, original_set)
        @test settings.constraint_scaling_factors == original_factors
        @test settings.proxy_var_map == original_proxies
        @test num_variables(model) == original_variables
        @test num_constraints(model; count_variable_in_set_constraints=true) == original_constraints
    end
end

function test_constraint_factor_rejection()
    @testset "cumulative factor validation precedes row updates" begin
        @testset "review overflow reproduction and recovery" begin
            model = Model()
            @variable(model, x)
            row = @constraint(model, 1e-300 * x <= 0.0)
            settings = MES.ScalingSettings()
            MES.scale_constraints!([row], settings)
            @test normalized_coefficient(row, x) ≈ 1e-3
            @test settings.constraint_scaling_factors[row] ≈ 1e297
            settings.coeff_lb = 1e10
            settings.coeff_ub = 1e20
            test_rejected_constraint_factor(model, row, settings)
            settings.coeff_lb = 1e-3
            settings.coeff_ub = 1e6
            @test MES.scale_constraints!([row], settings) === nothing
            @test normalized_coefficient(row, x) ≈ 1e-3
        end

        # Seed a finite existing factor near a Float64 limit to exercise each
        # scaling path without depending on a long history of transformations.
        @testset "successful scaling still prunes coefficients" begin
            model = Model()
            @variable(model, x)
            @variable(model, y)
            row = @constraint(model, 1e8 * x + 1e-20 * y <= 1e7)
            settings = MES.ScalingSettings(constraint_min_coeff=1e-9)
            MES.scale_constraints!([row], settings)
            @test normalized_coefficient(row, x) ≈ 1e6
            @test normalized_coefficient(row, y) == 0.0
            @test normalized_rhs(row) ≈ 1e5
            @test settings.constraint_scaling_factors[row] ≈ 0.01
        end
        @testset "uniform increase overflow" begin
            model = Model()
            @variable(model, x)
            @variable(model, y)
            row = @constraint(model, 1e-8 * x + 1e-20 * y <= 1e-7)
            settings = MES.ScalingSettings(constraint_min_coeff=1e-9)
            settings.constraint_scaling_factors[row] = floatmax(Float64)
            test_rejected_constraint_factor(model, row, settings)
        end
        @testset "uniform decrease underflow" begin
            model = Model()
            @variable(model, x)
            @variable(model, y)
            row = @constraint(model, 1e8 * x + 1e-20 * y <= 1e7)
            settings = MES.ScalingSettings(constraint_min_coeff=1e-9)
            settings.constraint_scaling_factors[row] = nextfloat(0.0)
            test_rejected_constraint_factor(model, row, settings)
        end
        @testset "hybrid proxy increase overflow" begin
            model = Model()
            @variable(model, x)
            @variable(model, y)
            @variable(model, z)
            row = @constraint(model, 1e3 * x + 1e-9 * y + 1e-20 * z <= 1e-6)
            settings = MES.ScalingSettings(constraint_min_coeff=1e-12)
            settings.constraint_scaling_factors[row] = floatmax(Float64)
            test_rejected_constraint_factor(model, row, settings)
        end
        @testset "hybrid proxy decrease underflow" begin
            model = Model()
            @variable(model, x)
            @variable(model, y)
            @variable(model, z)
            row = @constraint(model, 1e9 * x + 1e-4 * y + 1e-20 * z <= 1e9)
            settings = MES.ScalingSettings(constraint_min_coeff=1e-9)
            settings.constraint_scaling_factors[row] = nextfloat(0.0)
            test_rejected_constraint_factor(model, row, settings)
        end
        @testset "interval increase overflow before pruning" begin
            model = Model()
            @variable(model, x)
            @variable(model, y)
            row = @constraint(model, 1e-8 <= 1e-8 * x + 1e-20 * y <= 1e-6)
            settings = MES.ScalingSettings(constraint_min_coeff=1e-9)
            settings.constraint_scaling_factors[row] = floatmax(Float64)
            test_rejected_constraint_factor(model, row, settings)
        end
        @testset "interval decrease underflow before proxies" begin
            model = Model()
            @variable(model, x)
            @variable(model, y)
            row = @constraint(model, 1e8 <= 1e8 * x + 1e-12 * y <= 1e9)
            settings = MES.ScalingSettings()
            settings.constraint_scaling_factors[row] = nextfloat(0.0)
            test_rejected_constraint_factor(model, row, settings)
        end
    end
end
