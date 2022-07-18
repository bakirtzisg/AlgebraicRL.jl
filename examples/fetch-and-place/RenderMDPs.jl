
include("../src/AlgebraicRL.jl");
include("fetch-and-place/FetchAndPlace.jl");
using .AlgebraicRL
using .FetchAndPlace

using AlgebraicDynamics, AlgebraicDynamics.DWDDynam
using ReinforcementLearning
using StableRNGs
using Flux
using Flux.Losses
using Catlab.WiringDiagrams, Catlab.Graphics, Catlab.Graphics.Graphviz
using StatsBase, Random
using GR

# these are the 4 possible mdps to render
box_env = BoxMDP()
fetched_env = FetchedMDP()
placed_env = PlacedMDP()
mega_env = MegaMDP()


#=

README

To see the internal workings of the MDP, I have provided a basic rendering function. 
Depending on your system, you may have to click the GKS QT window, after running this script, to show the output

It shows the following:
   The arm is rendered as a red circle.
   The object is rendered as a blue circle. 
   The box is rendered as a black border.
   The arm and object location is rendered as a purple circle (when the object is held by the arm)
   The destination is rendered as a green circle
   Note the Mega MDP displays the rendering of the currently active MdP and switches between them

   The agent in this case is randomized.
   Change the following line to set which MDP is active. Nothing else should be edited.
=#
env = mega_env # one of box_env, fetched_env, placed_env, mega_env





# reset and run an episode
reset!(env)

for t in 1:10000
    obs = state(env)
    action = map(rand, action_space(env)) # finds random action
    env(action)
    GR.plot(env)
    if is_terminated(env)
        break
    end
end

