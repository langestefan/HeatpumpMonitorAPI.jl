```@meta
CurrentModule = HeatpumpMonitorAPI
```

# HeatpumpMonitorAPI.jl

Documentation for [HeatpumpMonitorAPI.jl](https://github.com/langestefan/HeatpumpMonitorAPI.jl).

A Julia REST/JSON API wrapper scaffolded with
[OpenAPITemplate.jl](https://github.com/langestefan/OpenAPITemplate.jl).

## Quick start

```julia
using HeatpumpMonitorAPI

client = Client("https://api.example.com"; auth = BearerToken(ENV["HEATPUMPMONITORAPI_TOKEN"]))
```

See the [Getting Started](getting_started.md) guide for a worked example, or
the [Julia API Reference](julia_reference.md) for the full surface.
