push!(LOAD_PATH,"../src/")
using Documenter, ReinforcementLearning, AlgebraicDynamics, AlgebraicDynamics.DWDDynam, AlgebraicRL

makedocs(   sitename="AlgebraicRL.JL",
            pages     = Any[
                "AlgebraicRL.jl" => "index.md",
                "API" => "api.md"
            ]
        )

deploydocs(repo = "github.com/bakirtzisg/AlgebraicRL.jl.git",)