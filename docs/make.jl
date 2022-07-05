push!(LOAD_PATH,"../src/")
using Documenter, ReinforcementLearning, AlgebraicDynamics, AlgebraicDynamics.DWDDynam, AlgebraicRL

makedocs(sitename="AlgebraicRL.JL")

deploydocs(repo = "github.com/bakirtzisg/AlgebraicRL.jl.git",)