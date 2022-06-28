module AlgebraicRL

using Pkg
using ReinforcementLearning
using StableRNGs
using Flux, Flux.Losses
using Catlab,  Catlab.WiringDiagrams, Catlab.Graphics, Catlab.Graphics.Graphviz
using LabelledArrays
using Plots
using IntervalSets
using StatsBase
using AlgebraicDynamics, AlgebraicDynamics.DWDDynam
using Random


# all internal includes go here. Order matters, do not change!
include("MDPAgent.jl")
include("MDPAgentMachine.jl")



end # module