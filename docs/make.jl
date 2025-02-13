using Documenter
using MacroEnergyScaling
using OrderedCollections

DocMeta.setdocmeta!(MacroEnergyScaling, :DocTestSetup, :(using MacroEnergyScaling); recursive = true)

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
modules = [MacroEnergyScaling],
authors = "Ruaridh Macdonald",
sitename = "MacroEnergyScaling.jl",
format = Documenter.HTML(;
    prettyurls = get(ENV, "CI", "false") == "true",
    canonical = "https://macroenergy.github.io/MacroEnergyScaling.jl",
    sidebar_sitename = false,
    collapselevel = 1
),
pages = [p for p in pages]
)

# Deploy built documentation
# ===========================

deploydocs(;
repo = "github.com/macroenergy/MacroEnergyScaling.jl.git",
devbranch = "main"
)