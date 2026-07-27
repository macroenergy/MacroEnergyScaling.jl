using BenchmarkTools
using HiGHS
using JuMP
using MacroEnergyScaling

const MES = MacroEnergyScaling

function build_in_range_model(n::Integer, model=Model())
    @variable(model, x[1:n])
    for i in 1:n
        @constraint(model, 2.0 * x[i] <= 4.0)
    end
    return model
end

function build_in_place_scaling_model(n::Integer, model=Model())
    @variable(model, x[1:n])
    for i in 1:n
        @constraint(model, 1.0e8 * x[i] <= 1.0e7)
    end
    return model
end

function build_proxy_scaling_model(n::Integer, model=Model())
    @variable(model, x[1:n])
    @variable(model, y[1:n])
    for i in 1:n
        @constraint(model, 1.0e9 * x[i] + 1.0e-9 * y[i] <= 1.0)
    end
    return model
end

function build_dense_in_place_scaling_model(n::Integer, terms_per_constraint::Integer, model=Model())
    @variable(model, x[1:terms_per_constraint])
    expression = sum(1.0e8 * x[j] for j in 1:terms_per_constraint)
    for _ in 1:n
        @constraint(model, expression <= 1.0e7)
    end
    return model
end

function build_dense_proxy_scaling_model(n::Integer, terms_per_constraint::Integer, model=Model())
    @variable(model, x[1:terms_per_constraint])
    @variable(model, y[1:terms_per_constraint])
    expression = sum(1.0e9 * x[j] + 1.0e-9 * y[j] for j in 1:terms_per_constraint)
    for _ in 1:n
        @constraint(model, expression <= 1.0)
    end
    return model
end

function build_in_range_objective_model(n::Integer, model=Model())
    @variable(model, x[1:n])
    @objective(model, Min, sum(2.0 * x[i] for i in 1:n))
    return model
end

function build_mixed_objective_model(n::Integer, model=Model())
    @variable(model, x[1:n])
    @variable(model, y[1:n])
    @objective(model, Min, sum(1.0e9 * x[i] + 1.0e-9 * y[i] for i in 1:n))
    return model
end

function build_proxy_objective_model(n::Integer, model=Model())
    @variable(model, x[1:n])
    @objective(model, Min, sum(1.0e9 * x[i] for i in 1:n))
    return model
end

function build_uniform_objective_model(n::Integer, model=Model())
    @variable(model, x[1:n])
    @objective(model, Min, sum(1.0e8 * x[i] for i in 1:n))
    return model
end

function build_direct_model()
    model = direct_model(HiGHS.Optimizer())
    set_silent(model)
    return model
end

function scaling_benchmarks(n::Integer=100, terms_per_constraint::Integer=50)
    suite = BenchmarkGroup()
    suite["already in range"] = @benchmarkable MES.scale_constraints!(model, settings) setup=(model = build_in_range_model($n); settings = MES.ScalingSettings()) evals=1
    suite["in-place scaling"] = @benchmarkable MES.scale_constraints!(model, settings) setup=(model = build_in_place_scaling_model($n); settings = MES.ScalingSettings()) evals=1
    suite["proxy scaling"] = @benchmarkable MES.scale_constraints!(model, settings) setup=(model = build_proxy_scaling_model($n); settings = MES.ScalingSettings()) evals=1
    suite["dense in-place scaling"] = @benchmarkable MES.scale_constraints!(model, settings) setup=(model = build_dense_in_place_scaling_model($n, $terms_per_constraint); settings = MES.ScalingSettings()) evals=1
    suite["dense proxy scaling"] = @benchmarkable MES.scale_constraints!(model, settings) setup=(model = build_dense_proxy_scaling_model($n, $terms_per_constraint); settings = MES.ScalingSettings()) evals=1
    suite["direct already in range"] = @benchmarkable MES.scale_constraints!(model, settings) setup=(model = build_in_range_model($n, build_direct_model()); settings = MES.ScalingSettings()) evals=1
    suite["direct in-place scaling"] = @benchmarkable MES.scale_constraints!(model, settings) setup=(model = build_in_place_scaling_model($n, build_direct_model()); settings = MES.ScalingSettings()) evals=1
    suite["direct dense in-place scaling"] = @benchmarkable MES.scale_constraints!(model, settings) setup=(model = build_dense_in_place_scaling_model($n, $terms_per_constraint, build_direct_model()); settings = MES.ScalingSettings()) evals=1
    suite["direct proxy scaling"] = @benchmarkable MES.scale_constraints!(model, settings) setup=(model = build_proxy_scaling_model($n, build_direct_model()); settings = MES.ScalingSettings()) evals=1
    suite["objective already in range"] = @benchmarkable MES.scale_objective!(model, settings) setup=(model = build_in_range_objective_model($n); settings = MES.ScalingSettings()) evals=1
    suite["objective mixed scaling"] = @benchmarkable MES.scale_objective!(model, settings) setup=(model = build_mixed_objective_model($n); settings = MES.ScalingSettings()) evals=1
    suite["objective proxy scaling"] = @benchmarkable MES.scale_objective!(model, settings) setup=(model = build_proxy_objective_model($n); settings = MES.ScalingSettings()) evals=1
    suite["objective uniform scaling"] = @benchmarkable MES.scale_objective!(model, settings) setup=(model = build_uniform_objective_model($n); settings = MES.ScalingSettings(scale_objective_uniformly = true)) evals=1
    suite["objective hybrid uniform scaling"] = @benchmarkable MES.scale_objective!(model, settings) setup=(model = build_mixed_objective_model($n); settings = MES.ScalingSettings(scale_objective_uniformly = true)) evals=1
    return suite
end

if abspath(PROGRAM_FILE) == @__FILE__
    n = parse(Int, get(ENV, "MES_BENCHMARK_CONSTRAINTS", "1000"))
    terms_per_constraint = parse(Int, get(ENV, "MES_BENCHMARK_DENSE_TERMS", "50"))
    results = run(scaling_benchmarks(n, terms_per_constraint); verbose=true)
    for (name, trial) in results
        println("\n$(name)")
        show(stdout, MIME("text/plain"), trial)
        println()
    end
end
