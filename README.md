# MacroEnergyScaling.jl

A package to rescale and improve the numerical stability of JuMP-based optimization models

## Instructions

This package should work with any JuMP-based optimization model. To use it, simply add the package to your project and call the `scale_constraints!(EP)` function with your model `EP`. The package will automatically rescale the model and improve its numerical stability. The objective function is not rescaled.

The user can adjust the manner in which the model is rescaled by creating a `ScalingSettings` object and passing it to the `scale_constraints!(EP, settings)` function. The `ScalingSettings` object can be created by providing the preferred settings in a dictionary.

Some constraints will be rescaled using proxy variables, where a new variable will be created which is a multiple of the original variable. This will add additonal constraints to the model. In addition, some constraints will be deleted and recreated with the same name but re-scaled coefficients. This can change the order of the constraints in the model, potentially affecting the solution.

Note, this package does not reformulate the model, it only rescales it. Better performance and numerical stability can be achieved by reformulating the model. This can achieve the same re-scaled coefficients and right-hand sides but without the need for proxy variables and additional constraints.
