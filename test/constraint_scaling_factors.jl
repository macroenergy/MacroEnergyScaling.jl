# Structural checks do not need an optimizer. Numerical checks can be reused
# by the package's HiGHS and optional Gurobi test environments.
function test_constraint_scaling_factors(optimizer)
    @testset "constraint scaling factors" begin
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
