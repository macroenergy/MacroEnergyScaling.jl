using Documenter
using MacroEnergySystemsScaling
using OrderedCollections

DocMeta.setdocmeta!(MacroEnergySystemsScaling, :DocTestSetup, :(using MacroEnergySystemsScaling); recursive = true)

pages = OrderedDict(
    "Introduction" => "index.md",
    "Reference" => [
        "Model Scaling" => "model_scaling.md",
        "Scaling Settings" => "scaling_settings.md",
    ]
    # "Examples" => "examples.md",
)

# Build documentation
# ====================

makedocs(;
modules = [MacroEnergySystemsScaling],
authors = "Ruaridh Macdonald",
sitename = "MacroEnergySystemsScaling.jl",
format = Documenter.HTML(;
    prettyurls = get(ENV, "CI", "false") == "true",
    canonical = "https://macroenergy.github.io/MacroEnergySystemsScaling.jl",
    sidebar_sitename = false,
    collapselevel = 1
),
pages = [p for p in pages]
)

# Deploy built documentation
# ===========================

deploydocs(;
repo = "github.com/macroenergy/MacroEnergySystemsScaling.jl.git",
devbranch = "main"
)