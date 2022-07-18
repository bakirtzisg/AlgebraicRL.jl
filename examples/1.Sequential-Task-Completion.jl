### A Pluto.jl notebook ###
# v0.19.9

using Markdown
using InteractiveUtils

# ╔═╡ ec5ed565-26bb-43b3-bf76-d1c7bd5496d1
function ingredients(path::String)
    # this is from the Julia source code (evalfile in base/loading.jl)
    # but with the modification that it returns the module instead of the last object
    name = Symbol(basename(path))
    m = Module(name)
    Core.eval(m,
        Expr(:toplevel,
             :(eval(x) = $(Expr(:core, :eval))($name, x)),
             :(include(x) = $(Expr(:top, :include))($name, x)),
             :(include(mapexpr::Function, x) = $(Expr(:top, :include))(mapexpr, $name, x)),
             :(include($path))))
    m
end

# ╔═╡ fe976d47-f3f2-42f2-9315-01a5766ad01f
begin
	using AlgebraicRL
	FP = ingredients("./fetch-and-place/FetchAndPlace.jl")
	using AlgebraicDynamics, AlgebraicDynamics.DWDDynam
	using ReinforcementLearning
	using StableRNGs
	using Flux
	using Flux.Losses
	using Catlab.WiringDiagrams, Catlab.Graphics, Catlab.Graphics.Graphviz
	using IntervalSets
	using GR
end

# ╔═╡ c39174d0-b3a7-41fb-bd62-276d6f538111
md"""
## Sequential task completion, compositionally

Authors: Georgios Bakirtzis ([bakirtzis.net](https://bakirtzis.net)) and
Tyler Ingebrand (tyleringebrand@gmail.com)

Building systems that complete tasks sequentially without breaking the
tasks into subproblems is computationally expensive. Compositionality in
this setting gives us a precise way of chaining subprocesses to create
complex behaviors. We shall design a fetch-and-place robot. The problem
formulation of fetch-and-place is an Markov decision process (MDP) where
a robotic arm must move an object from a box to a destination. We
abstract the robotic arm and the object to be points. We divide the
problem into three subprocesses.

1.  *Box*: the subprocess simulating the robotic arm behavior of picking
    up the object from a box.
2.  *Fetched*: the suprocess simulating the arm having picked up the
    object and transitioning to moving it to a prespecified destination.
3.  *Placed*: the suprocess simulating the arm having set the object in
    the desired location and moving away from the object (as a form of
    showing the task completion).

![](https://raw.githubusercontent.com/bakirtzisg/AlgebraicRL.jl/main/.github/logo.png)

We first attempt to solve the problem using traditional reinforcement
learning methods. That is, one agent taught using deep deterministic
policy gradient (DDPG) in this case, trying to solve the entire
fetch-and-place problem. We then solve it compositionally by optimizing
each subprocess individually and then composing the behavior to solve
the total behavior.

In particular, we will see how zig-zag diagrams of the above form can be transformed into *wiring diagrams* and how they can totally define the behavior of the whole by examining the behavior of the parts. By engineering compositionally, we show that categorical semantics partially address emergence, a significant issue with any type of learning incorporated into the system.
"""

# ╔═╡ 2a5a4798-341a-4c0b-98db-4db1cd45047c
md"""
### An ignoreable sidenote on training algorithms

The categorical semantics that provide us with compositional guarrantees
don't particularly care *how* we train the individual subprocesses
after the problem formulation; that is, the MDPs, are well-formed and
their composition makes physical sense.

In this particular example we use
[DDPG](https://web.archive.org/web/20220630072039/https://spinningup.openai.com/en/latest/algorithms/ddpg.html)
(see also the [paper](https://arxiv.org/abs/1509.02971)) for solving
MDPs with continuous state and action spaces. DDPG uses a few more key
tricks beyond the explanation below. DDPG is a deep learning algorithm
that learns how to solve a MDP by interacting with it over many
episodes. It learns which actions are good and bad by trial-and-error.

To do so, DDPG uses an actor and a critic. The actor---a neural
network---produces an action from the current state. The critic, another
neural network, evaluates whether that action was good or bad given the
current state. Concretely, it predicts the expected value of a
state-action pair, where value is the lifetime reward to be received
given this state-action pair.

At first, both the actor and critic know nothing. Their outputs are
effectively meaningless. Therefore, the algorithm will typically try
randomized actions at first to learn about the environment. This is
known as exploration.

However, as the algorithm progresses, it remembers what it has
experienced about the environment. These experiences are in the form of
the current state, the action taken, the following state, the reward
received, and whether this led to the end of the episode (termination).
These experiences can be used to update the critic and make it learn.
Mathematically, it uses the [Bellman
equation](https://en.wikipedia.org/wiki/Bellman_equation), which is a
form of dynamic programming. It works as follows: when a state-action
has bad reward, it learns the lifetime value of that state-action is
low. Otherwise, when the state-action has high reward, it learns the
lifetime value of that state-action is high.

While the critic is learning, the actor is learning as well. It learns
by listening to the critic. If the critic says a state-action pair is
bad, it will not produce that action from that state again. Likewise, if
the critic says a state-action pair is good, it will produce it again.
Mathematically, the actor learns by changing it\'s parameters to make
the critic produce a higher value given a constant state via gradient
descent.

Once the algorithm has learned how to correctly predict the value of a
state-action pair, and the actor has learned how to output the action
with the best value according to the critic, the MDP is solved. The
algorithm will stop producing randomized actions and will instead do
what the actor says. This is known as exploitation.

You can use any algorithm that implements the AbstractPolicy
[interface](https://github.com/JuliaReinforcementLearning/ReinforcementLearning.jl/blob/master/src/ReinforcementLearningBase/src/interface.jl)
provided by `ReinforcementLearning.jl`.

Basically, your policy must implement a function to read the state of an
MDP, and produce an action to apply to the environment. You may also
implement a function called
`optimise!(AbstractPolicy, Experience)` which is where your
algorithm learns from an experience. This
[interface](https://github.com/JuliaReinforcementLearning/ReinforcementLearning.jl/tree/master/src/ReinforcementLearningExperiments/deps/experiments/experiments)
supports you favourite flavour of learning algorithms.

You don't even need to use learning! Dynamic programming algorithms
stemming from control theory would also work, provided they implement
the interface. You could even hard code a solution to a given MDP. The
policy chosen is flexible. The only real requirement is that it is
capable of solving the MDP you apply it to.

Fetc-and-place correctly assumes that all MDPs have continuous state and
action spaces. This is not a requirement. You could also use MDPs with
discrete state or action spaces, and corresponding AbstractPolicies
capable of solving them. As with any other form of system design this
too is an art.
"""

# ╔═╡ 91101688-0f53-43a4-a7f0-10a0c60cfb36
md"""
### Visualizing problem solutions to MDPs
The following agent is following a random policy, but gives a good indication of how to visualize MDPs with their associated agent and policy. To examine how each sub-MDP is constructed, consult `RenderMDPs.jl` in `./fetch-and-place`.
"""

# ╔═╡ c233e8bb-547f-409e-a5cc-bae14b248fce
GR.inline("mov") # records video

# ╔═╡ 56321ee4-55eb-4cb8-ba0c-765425b1a2e8
envViz = FP.FetchAndPlace.MegaMDP() # the simplified fetch and place MDP

# ╔═╡ cb5eb128-95a7-4a4f-ae10-12cef0114fc4
reset!(envViz)

# ╔═╡ e8de9781-51ae-4d39-98ae-d6d9d4bd4133
for t in 1:10000
    envViz(map(rand, action_space(envViz)))
    GR.plot(envViz)
    if is_terminated(envViz)
        break
    end
end

# ╔═╡ af94357b-610a-4497-9e25-4be9a4e6b118
GR.show()

# ╔═╡ 9c6b303a-cd04-4893-a962-663458c52999
md"""
## Fetch and place robot design
"""

# ╔═╡ 6c11b2f8-1545-4dfd-9fd0-5d9fd51fcd29
rng = StableRNG(123)

# ╔═╡ 55254db7-522a-45f8-9885-f99ea2654dbb
mega_env = FP.FetchAndPlace.MegaMDP()

# ╔═╡ 150d93ef-d17f-40eb-b81d-bf74b698c3da
ns = length(RLBase.state_space(mega_env))

# ╔═╡ 3b50e947-5af4-4ae2-8e53-01008274982b
na = length(RLBase.action_space(mega_env))

# ╔═╡ 2cb966ab-e129-44ce-b76d-3c718a16f879
init = glorot_uniform(rng)

# ╔═╡ 86d70d8f-fb4a-4f7b-94d8-d5e8e8018d61
create_actor() = Chain(
    Dense(ns, 30, relu; init = init),
    Dense(30, 30, relu; init = init),
    Dense(30, na, tanh; init = init),
) |> gpu

# ╔═╡ ba227c04-8e74-4327-b1a7-6e75322192d7
create_critic() = Chain(
    Dense(ns + na, 30, relu; init = init),
    Dense(30, 30, relu; init = init),
    Dense(30, 1; init = init),
) |> gpu

# ╔═╡ 1998d403-8476-4a0e-b681-8c2252e69bed
mega_agent = Agent(
    policy = DDPGPolicy(
        behavior_actor = NeuralNetworkApproximator(
            model = create_actor(),
            optimizer = ADAM(),
        ),
        behavior_critic = NeuralNetworkApproximator(
            model = create_critic(),
            optimizer = ADAM(),
        ),
        target_actor = NeuralNetworkApproximator(
            model = create_actor(),
            optimizer = ADAM(),
        ),
        target_critic = NeuralNetworkApproximator(
            model = create_critic(),
            optimizer = ADAM(),
        ),
        γ = 0.99f0,
        ρ = 0.995f0,
        na = na,
        batch_size = 64,
        start_steps = 1000,
        start_policy = RandomPolicy(RLBase.action_space(mega_env); rng = rng),
        update_after = 1000,
        update_freq = 1,
        act_limit = 1.0,
        act_noise = 0.1,
        rng = rng,
    ),
    trajectory = CircularArraySARTTrajectory(
        capacity = 10000,
        state = Vector{Float32} => (ns,),
        action = Float32 => (na, ),
    ),
)

# ╔═╡ 8fb6ec3a-67e2-4316-834a-c80f20477ed4
stop_condition = StopAfterStep(120_000, is_show_progress=false)

# ╔═╡ 6d0b546a-8536-4d6a-80f2-6596bae0c193
hook = TotalRewardPerEpisode();

# ╔═╡ d89c10e7-80cc-443e-bf5c-ef657f75903c
md"""
### Training agents

We choose to train with DDPG. It is going to run for 100,000 timesteps, keeping track of rewards.
"""

# ╔═╡ 5cc7cbc5-5dd5-42a1-a171-f87838e5a9b8
run(mega_agent, mega_env, stop_condition, hook)

# ╔═╡ f63fb266-2db3-449f-a068-a2693c7eab50
reset!(mega_env)

# ╔═╡ 423c0a27-7c62-421f-a12f-984d41b1d813
# test it
GR.inline("mov") # records video

# ╔═╡ d9afab58-a2a4-4c54-99a6-9cfd98d7a374
env = FP.FetchAndPlace.MegaMDP() # the simplified fetch and place MDP

# ╔═╡ 001ec938-b9be-4c62-af16-11e63b6fb10b
reset!(env)

# ╔═╡ 39a35b1a-2512-444f-8df7-3e2aa81c71a8
#env.box.super_env.arm_position = Cartesian(10,10,10)
#env.box.super_env.obj_position = Cartesian(20,20,20)
#env.fetched.destination = Cartesian(30,30,30)


for t in 1:1000
    env(mega_agent(env))
    GR.plot(env)
    GR.plot(env)
    GR.plot(env)
    if is_terminated(env)
        reset!(env)
    end
end

# ╔═╡ e34303ff-4e55-4d73-858f-79db366e6ada
println("Is terminated? ", is_terminated(env))

# ╔═╡ dc7c2d91-2542-4df1-ba18-c671f4e42370
GR.show()

# ╔═╡ 210d17b4-9e6b-458b-bc85-5a6e63055890
md"""
We need to define internal state functions. Because we are setting the initial state, we need a custom function for that.

We are expenting the robot to learn to work in complex environments. It is, therefore, very likely that the policy we compute will not be able to solve the problem in all cases. Therefore, we have to add a timeout to the MDP to prevent an infinite loop. Also, we want to know how the MDP terminated, for example, via timeout or task completed, which requires a custom readout function to check. 
"""

# ╔═╡ fd37de83-ced0-48da-b932-e017183184f5
function input_function_mega(env::FP.FetchAndPlace.MegaMDP, internal_state::Vector)
    env.box.super_env.arm_position.x = internal_state[1]
    env.box.super_env.arm_position.y = internal_state[2]
    env.box.super_env.arm_position.z = internal_state[3]
    env.box.super_env.obj_position.x = internal_state[4]
    env.box.super_env.obj_position.y = internal_state[5]
    env.box.super_env.obj_position.z = internal_state[6]
    env.fetched.destination.x = internal_state[7]
    env.fetched.destination.y = internal_state[8]
    env.fetched.destination.z = internal_state[9]
    env.max_t = 50000 # will timeout after 50,000 timesteps
end

# ╔═╡ 888b1660-de93-46a7-b246-bf98b6680bc7
function output_function_mega(env::FP.FetchAndPlace.MegaMDP)
    if env.current_MDP == FP.FetchAndPlace.mdp_symbols[3] && RLBase.is_terminated(env.placed)
        println("Task completed! Time taken = ", env.t)
        return 1.0
    end
    if env.t > env.max_t
        println("Task failed! Time expired at task ", env.current_MDP, " after ", env.t, " timesteps.")
        println("Recall tasks go in the order Box -> Fetched -> Placed, with Fetched being the most complex.")
        return 0.0
    end
    return -1.0  # this should never happen, but if it does something went wrong.
end;

# ╔═╡ 46430782-9bc0-462b-891e-c006179c792b
md"""
### The wiring diagram category

We would like to solve this problem *compositionally*, a straightforward way is to construct a wiring diagram. But first we will try to solve the problem with just one MDP, which does not require us to work compositionally. We will see how even in this straightforward task the MDP and its associated agent fail to find a solution to the problem.

In the current problem formulation we require only one box because we are attemping to use a single MDP to solve it. It has 9 inputs, which consists of three sets of $$(x, y, z)$$ values. The first is the starting arm position. The second set is the starting object position. The final set is the destination object position. 

We also want to be able to see if it found a solution or not. Because the MDP can timeout (to prevent infinite loops), our readout function checks if it has found a solution or if it hasn't converged. 
"""

# ╔═╡ a0575bec-7ac2-4288-b5f1-59b966dc9ac3
mdp_mega = Box(:Mega, [:arm_position_x, :arm_position_y, :arm_position_z, :obj_position_x, :obj_position_y, :obj_position_z, :dest_x, :dest_y, :dest_z], 
                      [:done])

# ╔═╡ a3199ba1-a660-468d-ac10-ec3acbe6ce86
wiring_diagram = WiringDiagram([:arm_position_x, :arm_position_y, :arm_position_z, :obj_position_x, :obj_position_y, :obj_position_z, :dest_x, :dest_y, :dest_z], 
                              [:done])

# ╔═╡ b0764acd-70f4-44b7-9eb6-8a6ecf9a2e78
mdp_mega_id = add_box!(wiring_diagram, mdp_mega)

# ╔═╡ 983a77fd-62fc-4147-a0d3-c10b32ee71cc
add_wires!(wiring_diagram, [
  # Inputs to box     
  (input_id(wiring_diagram), 1) => (mdp_mega_id, 1),
  (input_id(wiring_diagram), 2) => (mdp_mega_id, 2),
  (input_id(wiring_diagram), 3) => (mdp_mega_id, 3),
  (input_id(wiring_diagram), 4) => (mdp_mega_id, 4),
  (input_id(wiring_diagram), 5) => (mdp_mega_id, 5),
  (input_id(wiring_diagram), 6) => (mdp_mega_id, 6),
  (input_id(wiring_diagram), 7) => (mdp_mega_id, 9),
  (input_id(wiring_diagram), 8) => (mdp_mega_id, 8),
  (input_id(wiring_diagram), 9) => (mdp_mega_id, 9),

  # Outputs
  (mdp_mega_id, 1) => (output_id(wiring_diagram),1),
])

# ╔═╡ 8aeae588-b63a-47c2-87a6-a954f594d3cc
to_graphviz(wiring_diagram, orientation=LeftToRight, labels=true)

# ╔═╡ 2a51d9be-b6a2-4f2e-8f21-148310d6f481
md"""
An MDP is merely the problem formulation, we would like to inhabit the box `Mega` with an agent that works according to some policy we have computed.
"""

# ╔═╡ f9c195dc-676d-41bf-8b67-a5da3998d7bb
mega_machine = MDPAgentMachine( mega_env, 
								mega_agent,
                                input_size=9,
								input_function=input_function_mega,
                                output_size=1, 
								output_function=output_function_mega );  

# ╔═╡ 4706b18d-64ff-40d4-b556-695684e388ab
md"""
Next we would like to run the machine in the diagram by running a forward pass. 

To do so we use our `readout` function to see if it solved the MDP or timed out. We set our timeout to be a long time, so if it times out, it most likely failed!
"""

# ╔═╡ 78a69da9-df5f-4c94-82d8-06b633c3a34a
comp = oapply( wiring_diagram, [mega_machine] )

# ╔═╡ 788e2704-1b8b-45e7-b65e-49facc64423d
# arm initial position = 0,0,0
# obj initial position = 10,10,10
# dest initial position = 20,20,20
init_values = [0,0,0, 10,10,10, 20,20,20]

# ╔═╡ f3eb7c53-dc2f-41a7-ba10-d027713098af
# do a forward pass
eval_dynamics(comp, init_values)

# ╔═╡ 8797b80d-0baa-4e6e-857f-09058b91e969
readout_value = read_output(comp)

# ╔═╡ 09579ac9-6a41-4e30-9b99-ddb6f5b387ff
println("Readout = ", readout_value)

# ╔═╡ 8c24dc44-019c-4fe6-a563-5dbb7896d9f0
md"""Readout of 1.0 signifies task completed successfully. A value of 0.0, instead, signifies a failure due to time limits. The agent failed!

The agent failed to solve the problem. This means that we cannot find a policy to solve the problem. Though it is impossible to say with certainty, this is most likely because of the added complexity of a sequential task completion problem. Basically, the behavior of the agent changes depending on whats already happened. Turns out, that is a hard behavior to learn.

### Exploiting the compositionality feature
Let's see how we can achieve better results by exploiting the compositionality feature. First, to solve fetch and place compositionally, we are going to solve each subproblem on its own, and then combine the behavior. This means we should first solve each subproblem. The subproblems are *box*, *fetched*, and *placed*. The fact that we are working within a category gives us theoretical guarantees that composition will work (with some art added to the mix).

#### Box
We will start by solving *box*. The training time is 10,000 steps, which ought to take only a few seconds, because this problem is easy to solve on its own.
 """

# ╔═╡ 2833d140-487b-44a7-b91f-04e5ecf715b2
rng_box = StableRNG(123)

# ╔═╡ 99964a25-3f79-4716-bd10-f193ce26e555
box_env = FP.FetchAndPlace.BoxMDP()

# ╔═╡ 411866fa-1540-43f2-8d45-4a617714c2cd
ns_box = length(RLBase.state_space(box_env))

# ╔═╡ bd41bec9-3f10-4dc4-8180-c4ba90848abe
na_box = length(RLBase.action_space(box_env))

# ╔═╡ 3f36d62b-6a1b-4bd5-9054-825ac49a4631
init_box = glorot_uniform(rng_box)

# ╔═╡ c596f70f-ca3b-4345-b2c4-75e1d96a75b4
create_actor_box() = Chain(
    Dense(ns_box, 30, relu; init = init_box),
    Dense(30, 30, relu; init = init_box),
    Dense(30, na_box, tanh; init = init_box),
) |> gpu

# ╔═╡ ceb871f0-a7c3-421d-8403-c24f118fdc9c
create_critic_box() = Chain(
    Dense(ns_box + na_box, 30, relu; init = init_box),
    Dense(30, 30, relu; init = init_box),
    Dense(30, 1; init = init_box),
) |> gpu

# ╔═╡ 2ff50d8d-8c0e-4e0d-af95-937770106650
box_agent = Agent(
    policy = DDPGPolicy(
        behavior_actor = NeuralNetworkApproximator(
            model = create_actor_box(),
            optimizer = ADAM(),
        ),
        behavior_critic = NeuralNetworkApproximator(
            model = create_critic_box(),
            optimizer = ADAM(),
        ),
        target_actor = NeuralNetworkApproximator(
            model = create_actor_box(),
            optimizer = ADAM(),
        ),
        target_critic = NeuralNetworkApproximator(
            model = create_critic_box(),
            optimizer = ADAM(),
        ),
        γ = 0.99f0,
        ρ = 0.995f0,
        na = na_box,
        batch_size = 64,
        start_steps = 1000,
        start_policy = RandomPolicy(RLBase.action_space(box_env); rng = rng_box),
        update_after = 1000,
        update_freq = 1,
        act_limit = 1.0,
        act_noise = 0.1,
        rng = rng_box,
    ),
    trajectory = CircularArraySARTTrajectory(
        capacity = 10000,
        state = Vector{Float32} => (ns_box,),
        action = Float32 => (na_box, ),
    ),
)

# ╔═╡ c67ec070-5621-4bbe-ac01-e8b2da875090
stop_condition_box = StopAfterStep(10_000, is_show_progress=false)

# ╔═╡ 851b9f62-766e-48c6-96a4-f6026535db6f
hook_box = TotalRewardPerEpisode()

# ╔═╡ 7f7429f5-ab6e-4533-b5f8-ab52cec2bda8
run(box_agent, box_env, stop_condition_box, hook_box)

# ╔═╡ d6e4b562-7b8f-4cf9-9364-cc115346da7a
md"""
#### Fetch

This problem by itself requires 100,000 steps to train because it requires navigating a large state space. We also require a very precise solution. 
"""

# ╔═╡ db3889ba-2c3a-443c-9e0e-ee93090cdf49
rng_fetch = StableRNG(123)

# ╔═╡ fe570421-def3-45d4-8c9d-53d0eb26f7a0
fetched_env = FP.FetchAndPlace.FetchedMDP()

# ╔═╡ 8d3be9d2-eef1-4547-9abe-4eb1a4390448
ns_fetch = length(RLBase.state_space(fetched_env))

# ╔═╡ 14c98b36-48c9-4d08-a28a-b52973013258
na_fetch = length(RLBase.action_space(fetched_env))

# ╔═╡ 544c96b7-e2bd-4017-a477-8cf36ebba491
init_fetch = glorot_uniform(rng_fetch)

# ╔═╡ e0573f1f-067e-4b23-975a-afbec7e1f1cb
create_actor_fetch() = Chain(
    Dense(ns_fetch, 30, relu; init = init_fetch),
    Dense(30, 30, relu; init = init_fetch),
    Dense(30, na_fetch, tanh; init = init_fetch),
) |> gpu

# ╔═╡ d68003bb-e4f0-4e1a-9f56-64195bddcac1
create_critic_fetch() = Chain(
    Dense(ns_fetch + na_fetch, 30, relu; init = init_fetch),
    Dense(30, 30, relu; init = init_fetch),
    Dense(30, 1; init = init_fetch),
) |> gpu

# ╔═╡ be6fdc11-b851-402c-8f3d-9d9b05ddb02b
fetched_agent = Agent(
    policy = DDPGPolicy(
        behavior_actor = NeuralNetworkApproximator(
            model = create_actor_fetch(),
            optimizer = ADAM(),
        ),
        behavior_critic = NeuralNetworkApproximator(
            model = create_critic_fetch(),
            optimizer = ADAM(),
        ),
        target_actor = NeuralNetworkApproximator(
            model = create_actor_fetch(),
            optimizer = ADAM(),
        ),
        target_critic = NeuralNetworkApproximator(
            model = create_critic_fetch(),
            optimizer = ADAM(),
        ),
        γ = 0.99f0,
        ρ = 0.995f0,
        na = na_fetch,
        batch_size = 64,
        start_steps = 1000,
        start_policy = RandomPolicy(RLBase.action_space(fetched_env); rng = rng_fetch),
        update_after = 1000,
        update_freq = 1,
        act_limit = 1.0,
        act_noise = 0.1,
        rng = rng_fetch,
    ),
    trajectory = CircularArraySARTTrajectory(
        capacity = 10000,
        state = Vector{Float32} => (ns_fetch,),
        action = Float32 => (na_fetch, ),
    ),
)

# ╔═╡ 0fa50f7c-2509-448f-9538-0bc768c7e0a3
stop_condition_fetch = StopAfterStep(100_000, is_show_progress=false)

# ╔═╡ 8c93ec50-dd77-41b2-90cb-fb3247aae014
hook_fetch = TotalRewardPerEpisode()

# ╔═╡ d5555915-1144-41e3-bf09-9e2046b44a23
run(fetched_agent, fetched_env, stop_condition_fetch, hook_fetch)

# ╔═╡ b8c81229-f6de-4276-8720-aff3416bc52c
md"""
#### Place
The training time is 10,000 steps, only a few seconds, because this problem is easy to solve on its own.
"""

# ╔═╡ 9d290533-515d-41f3-9927-cb3b71a46375
rng_place = StableRNG(123)

# ╔═╡ fc3c687e-7c80-4ddd-b341-75850792dd76
placed_env = FP.FetchAndPlace.PlacedMDP()

# ╔═╡ 7351db8a-6dce-423b-b137-a08a6a0d2517
ns_place = length(RLBase.state_space(placed_env))

# ╔═╡ b1818829-aa28-4994-9b41-6328090e83c2
na_place = length(RLBase.action_space(placed_env))

# ╔═╡ 5861b2b5-10c4-49e1-a756-63edea4cb206
init_place = glorot_uniform(rng_place)

# ╔═╡ 0b757ad5-48c0-470d-a20e-b13683286365
create_actor_place() = Chain(
    Dense(ns_place, 30, relu; init = init_place),
    Dense(30, 30, relu; init = init_place),
    Dense(30, na_place, tanh; init = init_place),
) |> gpu

# ╔═╡ eeb750eb-31aa-49f7-81db-f0337ae3b74d
create_critic_place() = Chain(
    Dense(ns_place + na_place, 30, relu; init = init_place),
    Dense(30, 30, relu; init = init_place),
    Dense(30, 1; init = init_place),
) |> gpu

# ╔═╡ a26b8f74-7971-4d40-87a5-839aad126fc2
placed_agent = Agent(
    policy = DDPGPolicy(
        behavior_actor = NeuralNetworkApproximator(
            model = create_actor_place(),
            optimizer = ADAM(),
        ),
        behavior_critic = NeuralNetworkApproximator(
            model = create_critic_place(),
            optimizer = ADAM(),
        ),
        target_actor = NeuralNetworkApproximator(
            model = create_actor_place(),
            optimizer = ADAM(),
        ),
        target_critic = NeuralNetworkApproximator(
            model = create_critic_place(),
            optimizer = ADAM(),
        ),
        γ = 0.99f0,
        ρ = 0.995f0,
        na = na_place,
        batch_size = 64,
        start_steps = 1000,
        start_policy = RandomPolicy(RLBase.action_space(placed_env); rng = rng_place),
        update_after = 1000,
        update_freq = 1,
        act_limit = 1.0,
        act_noise = 0.1,
        rng = rng_place,
    ),
    trajectory = CircularArraySARTTrajectory(
        capacity = 10000,
        state = Vector{Float32} => (ns_place,),
        action = Float32 => (na_place, ),
    ),
)

# ╔═╡ 69f0616b-0321-44ee-969e-f403812707b2
stop_condition_place = StopAfterStep(10_000, is_show_progress=false)

# ╔═╡ 62e65a0f-de32-4b43-b9fb-294df64ce71f
hook_place = TotalRewardPerEpisode()

# ╔═╡ f1c8735f-4fa9-4843-902a-e562b22f918a
run(placed_agent, placed_env, stop_condition_place, hook_place)

# ╔═╡ 020a13eb-318b-4e4c-827c-96e599f6f891
md"""
### Wiring diagram architecture

Composing MDPs in the wiring diagram category requires us to first construct an *architecture*, which defines how empty boxes connect. For the composed MDP to work, we have to pass the internal state between MDPs. After an MDP finishes, it passes its state to the next one. In effect, each MDP starts from the state where the previous one stopped.

Our three subprocess MDPs are box, fetch, and place. 

The MDP formulating box has a pair of coordinates $$(x, y, z)$$ for data. The first corresponds to the arm position and the second the object position.

The MDP formulating fetch assumes the arm has picked up the object. Now, the arm and object must share the same $$(x, y, z)$$ coordinates. We pass this location from box to fetch. We also need a destination to place the object.

Finally, the MDP formulating place assumes we have reached the final destination and set down the object. The arm and object can now move independently again. The location of the arm and object come from the MDP formulating fetch. To show we have dropped the object, this MDP terminates when the object and arm are sufficiently far apart.
"""

# ╔═╡ 86a6447f-71ff-44c1-9ada-709f56a5ad2f
mdp_box = Box(:box, [:arm_position_x,
					 :arm_position_y,
					 :arm_position_z,
					 :obj_position_x,
					 :obj_position_y,
					 :obj_position_z],                                         [:arm_and_obj_position_x, 
					 :arm_and_obj_position_y,
					 :arm_and_obj_position_z])

# ╔═╡ 744660cf-325e-44fc-8041-9a10f4df5a07
mdp_fetched = Box(:fetched, [:arm_and_obj_position_x,
							 :arm_and_obj_position_y, 
							 :arm_and_obj_position_z,
							 :dest_x,
							 :dest_y,
							 :dest_z],      
                            [:arm_position_x,
							 :arm_position_y,
							 :arm_position_z,
							 :obj_position_x,
							 :obj_position_y,
							 :obj_position_z])

# ╔═╡ 7c548d75-8dad-4969-9e2a-f54038d055f3
mdp_placed= Box(:placed, [:arm_position_x,
						  :arm_position_y,
						  :arm_position_z,
						  :obj_position_x,
					      :obj_position_y,
						  :obj_position_z],
	                      [:done])

# ╔═╡ 0e73ec15-5b68-4785-8a1b-2c3a71354da1
wiring_diagram_fp = WiringDiagram([:arm_position_x, 
								   :arm_position_y,
								   :arm_position_z,
								   :obj_position_x,
								   :obj_position_y,
								   :obj_position_z,
								   :dest_x,
								   :dest_y,
							       :dest_z], 
                             	   [:done])

# ╔═╡ 0f36523a-ad70-4d66-b1ef-fa203ffe1a15
# Add a box for each sub-MDP
mdp_box_id = add_box!(wiring_diagram_fp, mdp_box)

# ╔═╡ 98cadad1-85ff-44a4-ad5d-9d0865985753
mdp_fetched_id = add_box!(wiring_diagram_fp, mdp_fetched)

# ╔═╡ c0d901a4-8cad-4100-a8ea-c0333e7546aa
mdp_placed_id = add_box!(wiring_diagram_fp, mdp_placed)

# ╔═╡ 0ffcc67c-fe73-4952-98c5-6f3ada1bc7fd
add_wires!(wiring_diagram_fp, [
  # Inputs to box     
  (input_id(wiring_diagram_fp), 1) => (mdp_box_id, 1), # Arm x
  (input_id(wiring_diagram_fp), 2) => (mdp_box_id, 2), # Arm y
  (input_id(wiring_diagram_fp), 3) => (mdp_box_id, 3), # Arm z
  (input_id(wiring_diagram_fp), 4) => (mdp_box_id, 4), # Object x
  (input_id(wiring_diagram_fp), 5) => (mdp_box_id, 5), # Object y
  (input_id(wiring_diagram_fp), 6) => (mdp_box_id, 6), # Object z

  # inputs to fetched
  (mdp_box_id, 1) => (mdp_fetched_id, 1), # Arm and Object x
  (mdp_box_id, 2) => (mdp_fetched_id, 2), # Arm and Object y
  (mdp_box_id, 3) => (mdp_fetched_id, 3), # Arm and Object z
  (input_id(wiring_diagram_fp), 7) => (mdp_fetched_id, 4), # Destination X
  (input_id(wiring_diagram_fp), 8) => (mdp_fetched_id, 5), # Destination y
  (input_id(wiring_diagram_fp), 9) => (mdp_fetched_id, 6), # Destination z

  # inputs to placed
  (mdp_fetched_id, 1) => (mdp_placed_id, 1), # Arm x
  (mdp_fetched_id, 2) => (mdp_placed_id, 2), # Arm y
  (mdp_fetched_id, 3) => (mdp_placed_id, 3), # Arm z
  (mdp_fetched_id, 4) => (mdp_placed_id, 4), # Object x
  (mdp_fetched_id, 5) => (mdp_placed_id, 5), # Object y
  (mdp_fetched_id, 6) => (mdp_placed_id, 6), # Object z

  # Output from placed
  (mdp_placed_id, 1) => (output_id(wiring_diagram_fp),1), # done
])

# ╔═╡ a3d9c05c-0d30-41e5-8043-30602b215142
to_graphviz(wiring_diagram_fp, orientation=LeftToRight, labels=true)

# ╔═╡ a940c40f-5d8e-4dd8-9c39-9a2f738a6f91
md"""
### Wiring diagram semantics

Now that we have an architecture, we need to *inhabit* the boxes with some meaning. In our case that meaning is the agent behavior computed as a policy. By inhabitting the boxes with semantics in a particular architecture we can totally define the behavior of the whole, as long as it makes physical sense.

First, we must define the functions to set and fetch the internal state. This will allow us to make physical sense of the wiring diagram architecture. 
"""

# ╔═╡ a70e9f5d-9529-4464-a9df-ee3340358479
function output_function_box(env::FP.FetchAndPlace.BoxMDP)
    return [env.super_env.arm_position.x, env.super_env.arm_position.y, env.super_env.arm_position.z]
end

# ╔═╡ 345dd53c-a470-4e31-aa6d-4c73d8e23ded
function input_function_box(env::FP.FetchAndPlace.BoxMDP, internal_state)
    env.super_env.arm_position.x = internal_state[1]
    env.super_env.arm_position.y = internal_state[2]
    env.super_env.arm_position.z = internal_state[3]
    env.super_env.obj_position.x = internal_state[4]
    env.super_env.obj_position.y = internal_state[5]
    env.super_env.obj_position.z = internal_state[6]
end

# ╔═╡ b41bc759-9765-418c-bdb1-35042ccad70f
function output_function_fetched(env::FP.FetchAndPlace.FetchedMDP)
    return [env.super_env.arm_position.x, env.super_env.arm_position.y, env.super_env.arm_position.z, 
            env.super_env.obj_position.x, env.super_env.obj_position.y, env.super_env.obj_position.z]
end

# ╔═╡ aee1fc47-977f-4b42-8356-760e47fdc553
function input_function_fetched(env::FP.FetchAndPlace.FetchedMDP, internal_state)
    env.super_env.arm_position.x = internal_state[1]
    env.super_env.arm_position.y = internal_state[2]
    env.super_env.arm_position.z = internal_state[3]
    env.super_env.obj_position = env.super_env.arm_position
    env.destination.x = internal_state[4]
    env.destination.y = internal_state[5]
    env.destination.z = internal_state[6]
    env.t = -Inf # so we dont timeout, set t to be negative infinity, thereby never reach the timeout
end

# ╔═╡ 4686b68d-4fba-4b90-a7d4-3292004b2b7e
# for the placed env, we must only set internal state. Readout can be default(default returns 1 if terminated)
function input_function_placed(env::FP.FetchAndPlace.PlacedMDP, internal_state)
    env.super_env.arm_position.x = internal_state[1]
    env.super_env.arm_position.y = internal_state[2]
    env.super_env.arm_position.z = internal_state[3]
    env.super_env.obj_position.x = internal_state[4]
    env.super_env.obj_position.y = internal_state[5]
    env.super_env.obj_position.z = internal_state[6]
end;

# ╔═╡ 1975467a-2df8-4d19-af49-b387b1b1e0a3
# next, we have to change the defaults in the machines to support our custom function
box_machine = MDPAgentMachine(box_env,
							  box_agent,
	                          input_size=6,
							  input_function=input_function_box, 
	                          output_size=3, output_function=output_function_box)

# ╔═╡ fc2a4f34-c3fb-4335-a857-9f21f7af7f2b
fetched_machine = MDPAgentMachine(fetched_env,
								  fetched_agent,
	                              input_size=6,
								  input_function=input_function_fetched,
                                  output_size=6,
								  output_function=output_function_fetched)

# ╔═╡ 7a8497d7-0bf1-48d0-904a-9485c7fee08a
placed_machine = MDPAgentMachine(placed_env,
								 placed_agent,
                                 input_size=6,
								 input_function=input_function_placed);

# ╔═╡ fc24737b-66eb-48f4-a5ae-5f40be19345c
comp_fp = oapply( wiring_diagram_fp, [box_machine, fetched_machine, placed_machine] )

# ╔═╡ d298b997-311f-43dd-9b8c-60ae01888ecb
# arm initial position = 0,0,0
# obj initial position = 10,10,10
# dest initial position = 20,20,20
init_values_fp = [0,0,0, 10,10,10, 20,20,20]

# ╔═╡ ce09240d-1521-4a1d-9013-d272183ec4bf
eval_dynamics(comp_fp, init_values_fp)

# ╔═╡ c48a4be4-a1c1-4cea-8c9e-c353bc637a8d
readout_value_fp = read_output(comp_fp)

# ╔═╡ fcbb1746-c41d-4176-a4d7-d2f8a3e82df6
md"""
#### Interpreting the output

The compositional interpretation of the problem gives us *a* solution to the fetch and place problem. The wiring diagram category and its use for reinforcement learning allow us to model the system by parts, whilst giving us compositional guarantees that the whole will be correctly computing, given that the parts make physical sense when chained together.
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
AlgebraicDynamics = "5fd6ff03-a254-427e-8840-ba658f502e32"
AlgebraicRL = "c16e2c52-81b3-496d-9adf-f7ef61ccdb53"
Catlab = "134e5e36-593f-5add-ad60-77f754baafbe"
Flux = "587475ba-b771-5e3f-ad9e-33799f191a9c"
GR = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"
ReinforcementLearning = "158674fc-8238-5cab-b5ba-03dfc80d1318"
StableRNGs = "860ef19b-820b-49d6-a774-d7a799459cd3"

[compat]
AlgebraicDynamics = "~0.1.6"
AlgebraicRL = "~0.1.1"
Catlab = "~0.13.12"
Flux = "~0.12.10"
GR = "~0.66.0"
IntervalSets = "~0.5.4"
ReinforcementLearning = "~0.10.1"
StableRNGs = "~1.0.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.7.3"
manifest_format = "2.0"

[[deps.AbstractFFTs]]
deps = ["ChainRulesCore", "LinearAlgebra"]
git-tree-sha1 = "69f7020bd72f069c219b5e8c236c1fa90d2cb409"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.2.1"

[[deps.AbstractTrees]]
git-tree-sha1 = "03e0550477d86222521d254b741d470ba17ea0b5"
uuid = "1520ce14-60c1-5f80-bbc7-55ef81b5835c"
version = "0.3.4"

[[deps.Adapt]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "af92965fb30777147966f58acb05da51c5616b5f"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.3.3"

[[deps.AlgebraicDynamics]]
deps = ["Catlab", "Compose", "DelayDiffEq", "DifferentialEquations", "LabelledArrays", "LinearAlgebra", "LinearMaps", "OrdinaryDiffEq", "Plots", "PrettyTables", "RecipesBase", "RecursiveArrayTools", "StaticArrays"]
git-tree-sha1 = "46e339a0af41055b1c3282e465b0a23f02d10ebe"
uuid = "5fd6ff03-a254-427e-8840-ba658f502e32"
version = "0.1.6"

[[deps.AlgebraicRL]]
deps = ["AlgebraicDynamics", "Pkg", "ReinforcementLearning"]
git-tree-sha1 = "82d73042345b3773705d99dcba0d373be2356f9a"
uuid = "c16e2c52-81b3-496d-9adf-f7ef61ccdb53"
version = "0.1.1"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[deps.ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "62e51b39331de8911e4a7ff6f5aaf38a5f4cc0ae"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.2.0"

[[deps.ArrayInterface]]
deps = ["Compat", "IfElse", "LinearAlgebra", "Requires", "SparseArrays", "Static"]
git-tree-sha1 = "81f0cb60dc994ca17f68d9fb7c942a5ae70d9ee4"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "5.0.8"

[[deps.ArrayInterfaceCore]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "7d255eb1d2e409335835dc8624c35d97453011eb"
uuid = "30b0a656-2188-435a-8636-2ec0e6a096e2"
version = "0.1.14"

[[deps.ArrayInterfaceStaticArraysCore]]
deps = ["Adapt", "ArrayInterfaceCore", "LinearAlgebra", "StaticArraysCore"]
git-tree-sha1 = "a1e2cf6ced6505cbad2490532388683f1e88c3ed"
uuid = "dd5226c6-a4d4-4bc7-8575-46859f9c95b9"
version = "0.1.0"

[[deps.ArrayLayouts]]
deps = ["FillArrays", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "ebe4bbfc4de38ef88323f67d60a4e848fb550f0e"
uuid = "4c555306-a7a7-4459-81d9-ec55ddd5c99a"
version = "0.8.9"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.AutoHashEquals]]
git-tree-sha1 = "45bb6705d93be619b81451bb2006b7ee5d4e4453"
uuid = "15f4f7f2-30c1-5605-9d31-71845cf9641f"
version = "0.2.0"

[[deps.BFloat16s]]
deps = ["LinearAlgebra", "Printf", "Random", "Test"]
git-tree-sha1 = "a598ecb0d717092b5539dbbe890c98bac842b072"
uuid = "ab4f0b2a-ad5b-11e8-123f-65d77653426b"
version = "0.2.0"

[[deps.BandedMatrices]]
deps = ["ArrayLayouts", "FillArrays", "LinearAlgebra", "Random", "SparseArrays"]
git-tree-sha1 = "0227886a3141dfbb9fab5bfbf2133ac57677c1f9"
uuid = "aae01518-5342-5314-be14-df237901396f"
version = "0.17.3"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BitTwiddlingConvenienceFunctions]]
deps = ["Static"]
git-tree-sha1 = "eaee37f76339077f86679787a71990c4e465477f"
uuid = "62783981-4cbd-42fc-bca8-16325de8dc4b"
version = "0.1.4"

[[deps.BoundaryValueDiffEq]]
deps = ["BandedMatrices", "DiffEqBase", "FiniteDiff", "ForwardDiff", "LinearAlgebra", "NLsolve", "Reexport", "SparseArrays"]
git-tree-sha1 = "d6a331230022493b704e1d5c11f928e2cce2d058"
uuid = "764a87c0-6b3e-53db-9096-fe964310641d"
version = "2.8.0"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[deps.CEnum]]
git-tree-sha1 = "eb4cb44a499229b3b8426dcfb5dd85333951ff90"
uuid = "fa961155-64e5-5f13-b03f-caf6b980ea82"
version = "0.4.2"

[[deps.CPUSummary]]
deps = ["CpuId", "IfElse", "Static"]
git-tree-sha1 = "b1a532a582dd18b34543366322d390e1560d40a9"
uuid = "2a0fbf3d-bb9c-48f3-b0a9-814d99fd7ab9"
version = "0.1.23"

[[deps.CUDA]]
deps = ["AbstractFFTs", "Adapt", "BFloat16s", "CEnum", "CompilerSupportLibraries_jll", "ExprTools", "GPUArrays", "GPUCompiler", "LLVM", "LazyArtifacts", "Libdl", "LinearAlgebra", "Logging", "Printf", "Random", "Random123", "RandomNumbers", "Reexport", "Requires", "SparseArrays", "SpecialFunctions", "TimerOutputs"]
git-tree-sha1 = "e4e5ece72fa2f108fb20c3c5538a5fa9ef3d668a"
uuid = "052768ef-5323-5732-b1bb-66c8b64840ba"
version = "3.11.0"

[[deps.Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "4b859a208b2397a7a623a03449e4636bdb17bcf2"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.16.1+1"

[[deps.Calculus]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f641eb0a4f00c343bbc32346e1217b86f3ce9dad"
uuid = "49dc2e85-a5d0-5ad3-a950-438e2897f1b9"
version = "0.5.1"

[[deps.Catlab]]
deps = ["AutoHashEquals", "Compose", "DataStructures", "GeneralizedGenerated", "JSON", "LightXML", "LinearAlgebra", "Logging", "MLStyle", "Pkg", "PrettyTables", "Random", "Reexport", "Requires", "SparseArrays", "StaticArrays", "Statistics", "Tables"]
git-tree-sha1 = "b09da82bc19d5a5f659a4f9dff6b99a7ea85b41e"
uuid = "134e5e36-593f-5add-ad60-77f754baafbe"
version = "0.13.12"

[[deps.ChainRules]]
deps = ["ChainRulesCore", "Compat", "Distributed", "IrrationalConstants", "LinearAlgebra", "Random", "RealDot", "SparseArrays", "Statistics"]
git-tree-sha1 = "cc81c5c6bab557f89e4b5951b252d7ab863639a4"
uuid = "082447d4-558c-5d27-93f4-14fc19e9eca2"
version = "1.37.0"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "2dd813e5f2f7eec2d1268c57cf2373d3ee91fcea"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.15.1"

[[deps.ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "1e315e3f4b0b7ce40feded39c73049692126cf53"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.3"

[[deps.CircularArrayBuffers]]
deps = ["Adapt"]
git-tree-sha1 = "a05b83d278a5c52111af07e2b2df64bf7b122f8c"
uuid = "9de3a189-e0c0-4e15-ba3b-b14b9fb0aec1"
version = "0.1.10"

[[deps.CloseOpenIntervals]]
deps = ["ArrayInterface", "Static"]
git-tree-sha1 = "5522c338564580adf5d58d91e43a55db0fa5fb39"
uuid = "fb6a15b2-703c-40df-9091-08a04967cfa9"
version = "0.1.10"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[deps.ColorSchemes]]
deps = ["ColorTypes", "ColorVectorSpace", "Colors", "FixedPointNumbers", "Random"]
git-tree-sha1 = "1fd869cc3875b57347f7027521f561cf46d1fcd8"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.19.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[deps.ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "SpecialFunctions", "Statistics", "TensorCore"]
git-tree-sha1 = "d08c20eef1f2cbc6e60fd3612ac4340b89fea322"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.9.9"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "417b0ed7b8b838aa6ca0a87aadf1bb9eb111ce40"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.8"

[[deps.CommonRLInterface]]
deps = ["MacroTools"]
git-tree-sha1 = "21de56ebf28c262651e682f7fe614d44623dc087"
uuid = "d842c3ba-07a1-494f-bbec-f5741b0a3e98"
version = "0.3.1"

[[deps.CommonSolve]]
git-tree-sha1 = "332a332c97c7071600984b3c31d9067e1a4e6e25"
uuid = "38540f10-b2f7-11e9-35d8-d573e4eb0ff2"
version = "0.2.1"

[[deps.CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[deps.Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "9be8be1d8a6f44b96482c8af52238ea7987da3e3"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.45.0"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.Compose]]
deps = ["Base64", "Colors", "DataStructures", "Dates", "IterTools", "JSON", "LinearAlgebra", "Measures", "Printf", "Random", "Requires", "Statistics", "UUIDs"]
git-tree-sha1 = "d853e57661ba3a57abcdaa201f4c9917a93487a2"
uuid = "a81c6b42-2e10-5240-aca2-a61377ecd94b"
version = "0.9.4"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "59d00b3139a9de4eb961057eabb65ac6522be954"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.4.0"

[[deps.Contour]]
deps = ["StaticArrays"]
git-tree-sha1 = "9f02045d934dc030edad45944ea80dbd1f0ebea7"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.5.7"

[[deps.CpuId]]
deps = ["Markdown"]
git-tree-sha1 = "fcbb72b032692610bfbdb15018ac16a36cf2e406"
uuid = "adafc99b-e345-5852-983c-f28acb93d879"
version = "0.3.1"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DEDataArrays]]
deps = ["ArrayInterface", "DocStringExtensions", "LinearAlgebra", "RecursiveArrayTools", "SciMLBase", "StaticArrays"]
git-tree-sha1 = "fb2693e875ba9db2e64b684b2765e210c0d41231"
uuid = "754358af-613d-5f8d-9788-280bf1605d4c"
version = "0.2.4"

[[deps.DataAPI]]
git-tree-sha1 = "fb5f5316dd3fd4c5e7c30a24d50643b73e37cd40"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.10.0"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DelayDiffEq]]
deps = ["ArrayInterface", "DataStructures", "DiffEqBase", "LinearAlgebra", "Logging", "NonlinearSolve", "OrdinaryDiffEq", "Printf", "RecursiveArrayTools", "Reexport", "SciMLBase", "UnPack"]
git-tree-sha1 = "078f21d61a6f43a7b3eab4620ac958183e44cee2"
uuid = "bcd4f6db-9728-5f36-b5f7-82caef46ccdb"
version = "5.37.0"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[deps.DensityInterface]]
deps = ["InverseFunctions", "Test"]
git-tree-sha1 = "80c3e8639e3353e5d2912fb3a1916b8455e2494b"
uuid = "b429d917-457f-4dbc-8f4c-0cc954292b1d"
version = "0.4.0"

[[deps.DiffEqBase]]
deps = ["ArrayInterface", "ChainRulesCore", "DEDataArrays", "DataStructures", "Distributions", "DocStringExtensions", "FastBroadcast", "ForwardDiff", "FunctionWrappers", "IterativeSolvers", "LabelledArrays", "LinearAlgebra", "Logging", "MuladdMacro", "NonlinearSolve", "Parameters", "PreallocationTools", "Printf", "RecursiveArrayTools", "RecursiveFactorization", "Reexport", "Requires", "SciMLBase", "Setfield", "SparseArrays", "StaticArrays", "Statistics", "SuiteSparse", "ZygoteRules"]
git-tree-sha1 = "bd3812f2be255da87a2438c3b87a0a478cdbd050"
uuid = "2b5f629d-d688-5b77-993f-72d75c75574e"
version = "6.84.0"

[[deps.DiffEqCallbacks]]
deps = ["DataStructures", "DiffEqBase", "ForwardDiff", "LinearAlgebra", "NLsolve", "Parameters", "RecipesBase", "RecursiveArrayTools", "SciMLBase", "StaticArrays"]
git-tree-sha1 = "cfef2afe8d73ed2d036b0e4b14a3f9b53045c534"
uuid = "459566f4-90b8-5000-8ac3-15dfb0a30def"
version = "2.23.1"

[[deps.DiffEqNoiseProcess]]
deps = ["DiffEqBase", "Distributions", "GPUArraysCore", "LinearAlgebra", "Markdown", "Optim", "PoissonRandom", "QuadGK", "Random", "Random123", "RandomNumbers", "RecipesBase", "RecursiveArrayTools", "ResettableStacks", "SciMLBase", "StaticArrays", "Statistics"]
git-tree-sha1 = "6f3fe6ebe1b6e6e3a9b72739ada313aa17c9bb66"
uuid = "77a26b50-5914-5dd7-bc55-306e6241c503"
version = "5.12.0"

[[deps.DiffResults]]
deps = ["StaticArrays"]
git-tree-sha1 = "c18e98cba888c6c25d1c3b048e4b3380ca956805"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.0.3"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "28d605d9a0ac17118fe2c5e9ce0fbb76c3ceb120"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.11.0"

[[deps.DifferentialEquations]]
deps = ["BoundaryValueDiffEq", "DelayDiffEq", "DiffEqBase", "DiffEqCallbacks", "DiffEqNoiseProcess", "JumpProcesses", "LinearAlgebra", "LinearSolve", "OrdinaryDiffEq", "Random", "RecursiveArrayTools", "Reexport", "SteadyStateDiffEq", "StochasticDiffEq", "Sundials"]
git-tree-sha1 = "0ccc4356a8f268d5eee641f0944074560c45267a"
uuid = "0c46a032-eb83-5123-abaf-570d42b7fbaa"
version = "7.2.0"

[[deps.Distances]]
deps = ["LinearAlgebra", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "3258d0659f812acde79e8a74b11f17ac06d0ca04"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.7"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.Distributions]]
deps = ["ChainRulesCore", "DensityInterface", "FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "SparseArrays", "SpecialFunctions", "Statistics", "StatsBase", "StatsFuns", "Test"]
git-tree-sha1 = "429077fd74119f5ac495857fd51f4120baf36355"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.65"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "b19534d1895d702889b219c382a6e18010797f0b"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.6"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[deps.DualNumbers]]
deps = ["Calculus", "NaNMath", "SpecialFunctions"]
git-tree-sha1 = "5837a837389fccf076445fce071c8ddaea35a566"
uuid = "fa6b7ba4-c1ee-5f82-b5fc-ecf0adba8f74"
version = "0.6.8"

[[deps.EarCut_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3f3a2501fa7236e9b911e0f7a588c657e822bb6d"
uuid = "5ae413db-bbd1-5e63-b57d-d24a61df00f5"
version = "2.2.3+0"

[[deps.ElasticArrays]]
deps = ["Adapt"]
git-tree-sha1 = "a0fcc1bb3c9ceaf07e1d0529c9806ce94be6adf9"
uuid = "fdbdab4c-e67f-52f5-8c3f-e7b388dad3d4"
version = "1.2.9"

[[deps.EllipsisNotation]]
deps = ["ArrayInterface"]
git-tree-sha1 = "03b753748fd193a7f2730c02d880da27c5a24508"
uuid = "da5c29d0-fa7d-589e-88eb-ea29b0a81949"
version = "1.6.0"

[[deps.Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bad72f730e9e91c08d9427d5e8db95478a3c323d"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.4.8+0"

[[deps.ExponentialUtilities]]
deps = ["ArrayInterfaceCore", "GPUArraysCore", "GenericSchur", "LinearAlgebra", "Printf", "SparseArrays", "libblastrampoline_jll"]
git-tree-sha1 = "b40c9037e1a33990466bc5d224ced34b34eebdb0"
uuid = "d4d017d3-3776-5f7e-afef-a10c40355c18"
version = "1.18.0"

[[deps.ExprTools]]
git-tree-sha1 = "56559bbef6ca5ea0c0818fa5c90320398a6fbf8d"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.8"

[[deps.FFMPEG]]
deps = ["FFMPEG_jll"]
git-tree-sha1 = "b57e3acbe22f8484b4b5ff66a7499717fe1a9cc8"
uuid = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
version = "0.4.1"

[[deps.FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "Pkg", "Zlib_jll", "libaom_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "ccd479984c7838684b3ac204b716c89955c76623"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.2+0"

[[deps.FastBroadcast]]
deps = ["LinearAlgebra", "Polyester", "Static", "StrideArraysCore"]
git-tree-sha1 = "2bef6a96059e40dcf7a69c39506672d551fee983"
uuid = "7034ab61-46d4-4ed7-9d0f-46aef9175898"
version = "0.1.17"

[[deps.FastClosures]]
git-tree-sha1 = "acebe244d53ee1b461970f8910c235b259e772ef"
uuid = "9aa1b823-49e4-5ca5-8b0f-3971ec8bab6a"
version = "0.3.2"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "9267e5f50b0e12fdfd5a2455534345c4cf2c7f7a"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.14.0"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FillArrays]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "Statistics"]
git-tree-sha1 = "246621d23d1f43e3b9c368bf3b72b2331a27c286"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "0.13.2"

[[deps.FiniteDiff]]
deps = ["ArrayInterfaceCore", "LinearAlgebra", "Requires", "SparseArrays", "StaticArrays"]
git-tree-sha1 = "e3af8444c9916abed11f4357c2f59b6801e5b376"
uuid = "6a86dc24-6348-571c-b903-95158fe2bd41"
version = "2.13.1"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Flux]]
deps = ["AbstractTrees", "Adapt", "ArrayInterface", "CUDA", "CodecZlib", "Colors", "DelimitedFiles", "Functors", "Juno", "LinearAlgebra", "MacroTools", "NNlib", "NNlibCUDA", "Pkg", "Printf", "Random", "Reexport", "SHA", "SparseArrays", "Statistics", "StatsBase", "Test", "ZipFile", "Zygote"]
git-tree-sha1 = "511b7c48eebb602a8f63e7d6c63e25633468dc16"
uuid = "587475ba-b771-5e3f-ad9e-33799f191a9c"
version = "0.12.10"

[[deps.Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions", "StaticArrays"]
git-tree-sha1 = "2f18915445b248731ec5db4e4a17e451020bf21e"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.30"

[[deps.FreeType]]
deps = ["CEnum", "FreeType2_jll"]
git-tree-sha1 = "cabd77ab6a6fdff49bfd24af2ebe76e6e018a2b4"
uuid = "b38be410-82b0-50bf-ab77-7b57e271db43"
version = "4.0.0"

[[deps.FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "87eb71354d8ec1a96d4a7636bd57a7347dde3ef9"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.10.4+0"

[[deps.FreeTypeAbstraction]]
deps = ["ColorVectorSpace", "Colors", "FreeType", "GeometryBasics"]
git-tree-sha1 = "b5c7fe9cea653443736d264b85466bad8c574f4a"
uuid = "663a7486-cb36-511b-a19d-713bb74d65c9"
version = "0.9.9"

[[deps.FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[deps.FunctionWrappers]]
git-tree-sha1 = "241552bc2209f0fa068b6415b1942cc0aa486bcc"
uuid = "069b7b12-0de2-55c6-9aab-29f3d0a68a2e"
version = "1.1.2"

[[deps.Functors]]
git-tree-sha1 = "223fffa49ca0ff9ce4f875be001ffe173b2b7de4"
uuid = "d9f16b24-f501-4c13-a1f2-28368ffc5196"
version = "0.2.8"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.GLFW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libglvnd_jll", "Pkg", "Xorg_libXcursor_jll", "Xorg_libXi_jll", "Xorg_libXinerama_jll", "Xorg_libXrandr_jll"]
git-tree-sha1 = "51d2dfe8e590fbd74e7a842cf6d13d8a2f45dc01"
uuid = "0656b61e-2033-5cc2-a64a-77c0f6c09b89"
version = "3.3.6+0"

[[deps.GPUArrays]]
deps = ["Adapt", "GPUArraysCore", "LLVM", "LinearAlgebra", "Printf", "Random", "Reexport", "Serialization", "Statistics"]
git-tree-sha1 = "470dcaf29237a0818bc2cc97f0c408f0bc052653"
uuid = "0c68f7d7-f131-5f86-a1c3-88cf8149b2d7"
version = "8.4.1"

[[deps.GPUArraysCore]]
deps = ["Adapt"]
git-tree-sha1 = "4078d3557ab15dd9fe6a0cf6f65e3d4937e98427"
uuid = "46192b85-c4d5-4398-a991-12ede77f4527"
version = "0.1.0"

[[deps.GPUCompiler]]
deps = ["ExprTools", "InteractiveUtils", "LLVM", "Libdl", "Logging", "TimerOutputs", "UUIDs"]
git-tree-sha1 = "47f63159f7cb5d0e5e0cfd2f20454adea429bec9"
uuid = "61eb1bfa-7361-4325-ad38-22787b887f55"
version = "0.16.1"

[[deps.GR]]
deps = ["Base64", "DelimitedFiles", "GR_jll", "HTTP", "JSON", "Libdl", "LinearAlgebra", "Pkg", "Printf", "Random", "RelocatableFolders", "Serialization", "Sockets", "Test", "UUIDs"]
git-tree-sha1 = "037a1ca47e8a5989cc07d19729567bb71bfabd0c"
uuid = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
version = "0.66.0"

[[deps.GR_jll]]
deps = ["Artifacts", "Bzip2_jll", "Cairo_jll", "FFMPEG_jll", "Fontconfig_jll", "GLFW_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pixman_jll", "Pkg", "Qt5Base_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "c8ab731c9127cd931c93221f65d6a1008dad7256"
uuid = "d2c73de3-f751-5644-a686-071e5b155ba9"
version = "0.66.0+0"

[[deps.GeneralizedGenerated]]
deps = ["DataStructures", "JuliaVariables", "MLStyle", "Serialization"]
git-tree-sha1 = "60f1fa1696129205873c41763e7d0920ac7d6f1f"
uuid = "6b9d7cbe-bcb9-11e9-073f-15a7a543e2eb"
version = "0.3.3"

[[deps.GenericSchur]]
deps = ["LinearAlgebra", "Printf"]
git-tree-sha1 = "fb69b2a645fa69ba5f474af09221b9308b160ce6"
uuid = "c145ed77-6b09-5dd9-b285-bf645a82121e"
version = "0.5.3"

[[deps.GeometryBasics]]
deps = ["EarCut_jll", "IterTools", "LinearAlgebra", "StaticArrays", "StructArrays", "Tables"]
git-tree-sha1 = "83ea630384a13fc4f002b77690bc0afeb4255ac9"
uuid = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
version = "0.4.2"

[[deps.Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[deps.Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "a32d672ac2c967f3deb8a81d828afc739c838a06"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.68.3+2"

[[deps.Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[deps.Graphs]]
deps = ["ArnoldiMethod", "Compat", "DataStructures", "Distributed", "Inflate", "LinearAlgebra", "Random", "SharedArrays", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "db5c7e27c0d46fd824d470a3c32a4fc6c935fa96"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.7.1"

[[deps.Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "Dates", "IniFile", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "bd11d3220f89382f3116ed34c92badaa567239c9"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.0.5"

[[deps.HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "129acf094d168394e80ee1dc4bc06ec835e510a3"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+1"

[[deps.HostCPUFeatures]]
deps = ["BitTwiddlingConvenienceFunctions", "IfElse", "Libdl", "Static"]
git-tree-sha1 = "b7b88a4716ac33fe31d6556c02fc60017594343c"
uuid = "3e5b6fbb-0976-4d2c-9146-d79de83f2fb0"
version = "0.1.8"

[[deps.HypergeometricFunctions]]
deps = ["DualNumbers", "LinearAlgebra", "SpecialFunctions", "Test"]
git-tree-sha1 = "cb7099a0109939f16a4d3b572ba8396b1f6c7c31"
uuid = "34004b35-14d8-5ef3-9330-4cdb6864b03a"
version = "0.3.10"

[[deps.IRTools]]
deps = ["InteractiveUtils", "MacroTools", "Test"]
git-tree-sha1 = "af14a478780ca78d5eb9908b263023096c2b9d64"
uuid = "7869d1d1-7146-5819-86e3-90919afe41df"
version = "0.4.6"

[[deps.IfElse]]
git-tree-sha1 = "debdd00ffef04665ccbb3e150747a77560e8fad1"
uuid = "615f187c-cbe4-4ef1-ba3b-2fcf58d6d173"
version = "0.1.1"

[[deps.Inflate]]
git-tree-sha1 = "f5fc07d4e706b84f72d54eedcc1c13d92fb0871c"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.2"

[[deps.IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.IntervalSets]]
deps = ["Dates", "EllipsisNotation", "Statistics"]
git-tree-sha1 = "bcf640979ee55b652f3b01650444eb7bbe3ea837"
uuid = "8197267c-284f-5f27-9208-e0e47529a953"
version = "0.5.4"

[[deps.InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "b3364212fb5d870f724876ffcd34dd8ec6d98918"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.7"

[[deps.IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

[[deps.IterTools]]
git-tree-sha1 = "fa6287a4469f5e048d763df38279ee729fbd44e5"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.4.0"

[[deps.IterativeSolvers]]
deps = ["LinearAlgebra", "Printf", "Random", "RecipesBase", "SparseArrays"]
git-tree-sha1 = "1169632f425f79429f245113b775a0e3d121457c"
uuid = "42fd0dbc-a981-5370-80f2-aaf504508153"
version = "0.9.2"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[deps.JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b53380851c6e6664204efb2e62cd24fa5c47e4ba"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "2.1.2+0"

[[deps.JuliaVariables]]
deps = ["MLStyle", "NameResolution"]
git-tree-sha1 = "49fb3cb53362ddadb4415e9b73926d6b40709e70"
uuid = "b14d175d-62b4-44ba-8fb7-3064adc8c3ec"
version = "0.2.4"

[[deps.JumpProcesses]]
deps = ["ArrayInterfaceCore", "DataStructures", "DiffEqBase", "DocStringExtensions", "FunctionWrappers", "Graphs", "LinearAlgebra", "Markdown", "PoissonRandom", "Random", "RandomNumbers", "RecursiveArrayTools", "Reexport", "SciMLBase", "StaticArrays", "TreeViews", "UnPack"]
git-tree-sha1 = "4aa139750616fee7216ddcb30652357c60c3683e"
uuid = "ccbc3e58-028d-4f4c-8cd5-9ae44345cda5"
version = "9.0.1"

[[deps.Juno]]
deps = ["Base64", "Logging", "Media", "Profile"]
git-tree-sha1 = "07cb43290a840908a771552911a6274bc6c072c7"
uuid = "e5e0dc1b-0480-54bc-9374-aad01c23163d"
version = "0.8.4"

[[deps.KLU]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse_jll"]
git-tree-sha1 = "cae5e3dfd89b209e01bcd65b3a25e74462c67ee0"
uuid = "ef3ab10e-7fda-4108-b977-705223b18434"
version = "0.3.0"

[[deps.Krylov]]
deps = ["LinearAlgebra", "Printf", "SparseArrays"]
git-tree-sha1 = "7f0a89bd74c30aa7ff96c4bf1bc884c39663a621"
uuid = "ba0b0d4f-ebba-5204-a429-3ac8c609bfb7"
version = "0.8.2"

[[deps.KrylovKit]]
deps = ["LinearAlgebra", "Printf"]
git-tree-sha1 = "49b0c1dd5c292870577b8f58c51072bd558febb9"
uuid = "0b1a1467-8014-51b9-945f-bf0ae24f4b77"
version = "0.5.4"

[[deps.LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[deps.LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bf36f528eec6634efc60d7ec062008f171071434"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "3.0.0+1"

[[deps.LLVM]]
deps = ["CEnum", "LLVMExtra_jll", "Libdl", "Printf", "Unicode"]
git-tree-sha1 = "e7e9184b0bf0158ac4e4aa9daf00041b5909bf1a"
uuid = "929cbde3-209d-540e-8aea-75f648917ca0"
version = "4.14.0"

[[deps.LLVMExtra_jll]]
deps = ["Artifacts", "JLLWrappers", "LazyArtifacts", "Libdl", "Pkg", "TOML"]
git-tree-sha1 = "771bfe376249626d3ca12bcd58ba243d3f961576"
uuid = "dad2f222-ce93-54a1-a47d-0025e8a3acab"
version = "0.0.16+0"

[[deps.LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[deps.LabelledArrays]]
deps = ["ArrayInterface", "ChainRulesCore", "LinearAlgebra", "MacroTools", "StaticArrays"]
git-tree-sha1 = "1cccf6d366e51fbaf80303158d49bb2171acfeee"
uuid = "2ee39098-c373-598a-b85f-a56591580800"
version = "1.9.0"

[[deps.Latexify]]
deps = ["Formatting", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "Printf", "Requires"]
git-tree-sha1 = "46a39b9c58749eefb5f2dc1178cb8fab5332b1ab"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.15.15"

[[deps.LayoutPointers]]
deps = ["ArrayInterface", "LinearAlgebra", "ManualMemory", "SIMDTypes", "Static"]
git-tree-sha1 = "9e72f9e890c46081dbc0ebeaf6ccaffe16e51626"
uuid = "10f19ff3-798f-405d-979b-55457f8fc047"
version = "0.1.8"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[deps.LazyModules]]
git-tree-sha1 = "a560dd966b386ac9ae60bdd3a3d3a326062d3c3e"
uuid = "8cdb02fc-e678-4876-92c5-9defec4f444e"
version = "0.3.1"

[[deps.LevyArea]]
deps = ["LinearAlgebra", "Random", "SpecialFunctions"]
git-tree-sha1 = "56513a09b8e0ae6485f34401ea9e2f31357958ec"
uuid = "2d8b4e74-eb68-11e8-0fb9-d5eb67b50637"
version = "1.0.0"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "0b4a5d71f3e5200a7dff793393e09dfc2d874290"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+1"

[[deps.Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll", "Pkg"]
git-tree-sha1 = "64613c82a59c120435c067c2b809fc61cf5166ae"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.7+0"

[[deps.Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "7739f837d6447403596a75d19ed01fd08d6f56bf"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.3.0+3"

[[deps.Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "42b62845d70a619f063a7da093d995ec8e15e778"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+1"

[[deps.Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c30530bf0effd46e15e0fdcf2b8636e78cbbd73"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.35.0+0"

[[deps.Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "Pkg", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "3eb79b0ca5764d4799c06699573fd8f533259713"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.4.0+0"

[[deps.Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7f3efec06033682db852f8b3bc3c1d2b0a0ab066"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.36.0+0"

[[deps.LightXML]]
deps = ["Libdl", "XML2_jll"]
git-tree-sha1 = "e129d9391168c677cd4800f5c0abb1ed8cb3794f"
uuid = "9c8b4983-aa76-5018-a973-4c85ecc9e179"
version = "0.9.0"

[[deps.LineSearches]]
deps = ["LinearAlgebra", "NLSolversBase", "NaNMath", "Parameters", "Printf"]
git-tree-sha1 = "f27132e551e959b3667d8c93eae90973225032dd"
uuid = "d3d80556-e9d4-5f37-9878-2ab0fcc64255"
version = "7.1.1"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LinearMaps]]
deps = ["LinearAlgebra", "SparseArrays", "Statistics"]
git-tree-sha1 = "d1b46faefb7c2f48fdec69e6f3cc34857769bc15"
uuid = "7a12625a-238d-50fd-b39a-03d52299707e"
version = "3.8.0"

[[deps.LinearSolve]]
deps = ["ArrayInterfaceCore", "DocStringExtensions", "GPUArraysCore", "IterativeSolvers", "KLU", "Krylov", "KrylovKit", "LinearAlgebra", "RecursiveFactorization", "Reexport", "SciMLBase", "Setfield", "SparseArrays", "SuiteSparse", "UnPack"]
git-tree-sha1 = "c08c4177cc7edbf42a92f08a04bf848dde73f0b9"
uuid = "7ed4a6bd-45f5-4d41-b270-4a48e9bafcae"
version = "1.20.0"

[[deps.LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "09e4b894ce6a976c354a69041a04748180d43637"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.15"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "5d4d2d9904227b8bd66386c1138cf4d5ffa826bf"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "0.4.9"

[[deps.LoopVectorization]]
deps = ["ArrayInterface", "CPUSummary", "ChainRulesCore", "CloseOpenIntervals", "DocStringExtensions", "ForwardDiff", "HostCPUFeatures", "IfElse", "LayoutPointers", "LinearAlgebra", "OffsetArrays", "PolyesterWeave", "SIMDDualNumbers", "SLEEFPirates", "SpecialFunctions", "Static", "ThreadingUtilities", "UnPack", "VectorizationBase"]
git-tree-sha1 = "4392c19f0203df81512b6790a0a67446650bdce0"
uuid = "bdcacae8-1622-11e9-2a5c-532679323890"
version = "0.12.110"

[[deps.MLStyle]]
git-tree-sha1 = "c4f433356372cc8838da59e3608be4b0c4c2c280"
uuid = "d8e11817-5142-5d16-987a-aa16d5891078"
version = "0.4.13"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "3d3e902b31198a27340d0bf00d6ac452866021cf"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.9"

[[deps.ManualMemory]]
git-tree-sha1 = "bcaef4fc7a0cfe2cba636d84cda54b5e4e4ca3cd"
uuid = "d125e4d3-2237-4719-b19c-fa641b8a4667"
version = "0.1.8"

[[deps.MarchingCubes]]
deps = ["StaticArrays"]
git-tree-sha1 = "3bf4baa9df7d1367168ebf60ed02b0379ea91099"
uuid = "299715c1-40a9-479a-aaf9-4a633d36f717"
version = "0.1.3"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "891d3b4e8f8415f53108b4918d0183e61e18015b"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.0"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[deps.Measures]]
git-tree-sha1 = "e498ddeee6f9fdb4551ce855a46f54dbd900245f"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.1"

[[deps.Media]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "75a54abd10709c01f1b86b84ec225d26e840ed58"
uuid = "e89f7d12-3494-54d1-8411-f7d8b9ae1f27"
version = "0.5.0"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[deps.MuladdMacro]]
git-tree-sha1 = "c6190f9a7fc5d9d5915ab29f2134421b12d24a68"
uuid = "46d2c3a1-f734-5fdb-9937-b9b9aeba4221"
version = "0.2.2"

[[deps.NLSolversBase]]
deps = ["DiffResults", "Distributed", "FiniteDiff", "ForwardDiff"]
git-tree-sha1 = "50310f934e55e5ca3912fb941dec199b49ca9b68"
uuid = "d41bc354-129a-5804-8e4c-c37616107c6c"
version = "7.8.2"

[[deps.NLsolve]]
deps = ["Distances", "LineSearches", "LinearAlgebra", "NLSolversBase", "Printf", "Reexport"]
git-tree-sha1 = "019f12e9a1a7880459d0173c182e6a99365d7ac1"
uuid = "2774e3e8-f4cf-5e23-947b-6d7e65073b56"
version = "4.5.1"

[[deps.NNlib]]
deps = ["Adapt", "ChainRulesCore", "LinearAlgebra", "Pkg", "Requires", "Statistics"]
git-tree-sha1 = "1a80840bcdb73de345230328d49767ab115be6f2"
uuid = "872c559c-99b0-510c-b3b7-b6c96a88d5cd"
version = "0.8.8"

[[deps.NNlibCUDA]]
deps = ["CUDA", "LinearAlgebra", "NNlib", "Random", "Statistics"]
git-tree-sha1 = "e161b835c6aa9e2339c1e72c3d4e39891eac7a4f"
uuid = "a00861dc-f156-4864-bf3c-e6376f28a68d"
version = "0.2.3"

[[deps.NaNMath]]
git-tree-sha1 = "b086b7ea07f8e38cf122f5016af580881ac914fe"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "0.3.7"

[[deps.NameResolution]]
deps = ["PrettyPrint"]
git-tree-sha1 = "1a0fa0e9613f46c9b8c11eee38ebb4f590013c5e"
uuid = "71a1bf82-56d0-4bbc-8a3c-48b961074391"
version = "0.1.5"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[deps.NonlinearSolve]]
deps = ["ArrayInterfaceCore", "FiniteDiff", "ForwardDiff", "IterativeSolvers", "LinearAlgebra", "RecursiveArrayTools", "RecursiveFactorization", "Reexport", "SciMLBase", "Setfield", "StaticArrays", "UnPack"]
git-tree-sha1 = "932bbdc22e6a2e0bae8dec35d32e4c8cb6c50f98"
uuid = "8913a72c-1f9b-4ce2-8d82-65094dcecaec"
version = "0.3.21"

[[deps.OffsetArrays]]
deps = ["Adapt"]
git-tree-sha1 = "1ea784113a6aa054c5ebd95945fa5e52c2f378e7"
uuid = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
version = "1.12.7"

[[deps.Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "887579a3eb005446d514ab7aeac5d1d027658b8f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+1"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e60321e3f2616584ff98f0a4f18d98ae6f89bbb3"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.17+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.Optim]]
deps = ["Compat", "FillArrays", "ForwardDiff", "LineSearches", "LinearAlgebra", "NLSolversBase", "NaNMath", "Parameters", "PositiveFactorizations", "Printf", "SparseArrays", "StatsBase"]
git-tree-sha1 = "7a28efc8e34d5df89fc87343318b0a8add2c4021"
uuid = "429524aa-4258-5aef-a3af-852621145aeb"
version = "1.7.0"

[[deps.Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[deps.OrdinaryDiffEq]]
deps = ["Adapt", "ArrayInterface", "DataStructures", "DiffEqBase", "DocStringExtensions", "ExponentialUtilities", "FastClosures", "FiniteDiff", "ForwardDiff", "LinearAlgebra", "LinearSolve", "Logging", "LoopVectorization", "MacroTools", "MuladdMacro", "NLsolve", "NonlinearSolve", "Polyester", "PreallocationTools", "RecursiveArrayTools", "Reexport", "SciMLBase", "SparseArrays", "SparseDiffTools", "StaticArrays", "UnPack"]
git-tree-sha1 = "4334050e6dbb2cd0ad6c6e1be633395134337262"
uuid = "1dea7af3-3e70-54e6-95c3-0bf5283fa5ed"
version = "6.11.2"

[[deps.PCRE_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b2a7af664e098055a7529ad1a900ded962bca488"
uuid = "2f80f16e-611a-54ab-bc61-aa92de5b98fc"
version = "8.44.0+0"

[[deps.PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "cf494dca75a69712a72b80bc48f59dcf3dea63ec"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.16"

[[deps.Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "0044b23da09b5608b4ecacb4e5e6c6332f833a7e"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.3.2"

[[deps.Pixman_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b4f5d02549a10e20780a24fce72bea96b6329e29"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.40.1+0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[deps.PlotThemes]]
deps = ["PlotUtils", "Statistics"]
git-tree-sha1 = "8162b2f8547bc23876edd0c5181b27702ae58dce"
uuid = "ccf2f8ad-2431-5c83-bf29-c5338b663b6a"
version = "3.0.0"

[[deps.PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "Printf", "Random", "Reexport", "Statistics"]
git-tree-sha1 = "9888e59493658e476d3073f1ce24348bdc086660"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.3.0"

[[deps.Plots]]
deps = ["Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "GeometryBasics", "JSON", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "Pkg", "PlotThemes", "PlotUtils", "Printf", "REPL", "Random", "RecipesBase", "RecipesPipeline", "Reexport", "Requires", "Scratch", "Showoff", "SparseArrays", "Statistics", "StatsBase", "UUIDs", "UnicodeFun", "Unzip"]
git-tree-sha1 = "b29873144e57f9fcf8d41d107138a4378e035298"
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.31.2"

[[deps.PoissonRandom]]
deps = ["Random"]
git-tree-sha1 = "9ac1bb7c15c39620685a3a7babc0651f5c64c35b"
uuid = "e409e4f3-bfea-5376-8464-e040bb5c01ab"
version = "0.4.1"

[[deps.Polyester]]
deps = ["ArrayInterface", "BitTwiddlingConvenienceFunctions", "CPUSummary", "IfElse", "ManualMemory", "PolyesterWeave", "Requires", "Static", "StrideArraysCore", "ThreadingUtilities"]
git-tree-sha1 = "bfd5fb3376bc084d202c717bbba8c94696755d87"
uuid = "f517fe37-dbe3-4b94-8317-1923a5111588"
version = "0.6.12"

[[deps.PolyesterWeave]]
deps = ["BitTwiddlingConvenienceFunctions", "CPUSummary", "IfElse", "Static", "ThreadingUtilities"]
git-tree-sha1 = "4cd738fca4d826bef1a87cbe43196b34fa205e6d"
uuid = "1d0040c9-8b98-4ee7-8388-3f51789ca0ad"
version = "0.1.6"

[[deps.PositiveFactorizations]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "17275485f373e6673f7e7f97051f703ed5b15b20"
uuid = "85a6dd25-e78a-55b7-8502-1745935b8125"
version = "0.2.4"

[[deps.PreallocationTools]]
deps = ["Adapt", "ArrayInterfaceCore", "ForwardDiff", "LabelledArrays"]
git-tree-sha1 = "77266c25ab9d48e31ef167eae936e8f6fa0e4754"
uuid = "d236fae5-4411-538c-8e31-a6e3d9e00b46"
version = "0.3.2"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[deps.PrettyPrint]]
git-tree-sha1 = "632eb4abab3449ab30c5e1afaa874f0b98b586e4"
uuid = "8162dcfd-2161-5ef2-ae6c-7681170c5f98"
version = "0.2.0"

[[deps.PrettyTables]]
deps = ["Crayons", "Formatting", "Markdown", "Reexport", "Tables"]
git-tree-sha1 = "dfb54c4e414caa595a1f2ed759b160f5a3ddcba5"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "1.3.1"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.ProgressMeter]]
deps = ["Distributed", "Printf"]
git-tree-sha1 = "d7a7aef8f8f2d537104f170139553b14dfe39fe9"
uuid = "92933f4c-e287-5a05-a399-4b506db050ca"
version = "1.7.2"

[[deps.Qt5Base_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Fontconfig_jll", "Glib_jll", "JLLWrappers", "Libdl", "Libglvnd_jll", "OpenSSL_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libxcb_jll", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_keysyms_jll", "Xorg_xcb_util_renderutil_jll", "Xorg_xcb_util_wm_jll", "Zlib_jll", "xkbcommon_jll"]
git-tree-sha1 = "c6c0f690d0cc7caddb74cef7aa847b824a16b256"
uuid = "ea2cea3b-5b76-57ae-a6ef-0a8af62496e1"
version = "5.15.3+1"

[[deps.QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "78aadffb3efd2155af139781b8a8df1ef279ea39"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.4.2"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Random123]]
deps = ["Random", "RandomNumbers"]
git-tree-sha1 = "afeacaecf4ed1649555a19cb2cad3c141bbc9474"
uuid = "74087812-796a-5b5d-8853-05524746bad3"
version = "1.5.0"

[[deps.RandomNumbers]]
deps = ["Random", "Requires"]
git-tree-sha1 = "043da614cc7e95c703498a491e2c21f58a2b8111"
uuid = "e6cf234a-135c-5ec9-84dd-332b85af5143"
version = "1.5.3"

[[deps.RealDot]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "9f0a1b71baaf7650f4fa8a1d168c7fb6ee41f0c9"
uuid = "c1ae055f-0cd5-4b69-90a6-9a35b1a98df9"
version = "0.1.0"

[[deps.RecipesBase]]
git-tree-sha1 = "6bf3f380ff52ce0832ddd3a2a7b9538ed1bcca7d"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.2.1"

[[deps.RecipesPipeline]]
deps = ["Dates", "NaNMath", "PlotUtils", "RecipesBase"]
git-tree-sha1 = "2690681814016887462cf5ac37102b51cd9ec781"
uuid = "01d81517-befc-4cb6-b9ec-a95719d0359c"
version = "0.6.2"

[[deps.RecursiveArrayTools]]
deps = ["Adapt", "ArrayInterfaceCore", "ArrayInterfaceStaticArraysCore", "ChainRulesCore", "DocStringExtensions", "FillArrays", "GPUArraysCore", "LinearAlgebra", "RecipesBase", "StaticArraysCore", "Statistics", "ZygoteRules"]
git-tree-sha1 = "7a5f08bdeb79cf3f8ce60125fe1b2a04041c1d26"
uuid = "731186ca-8d62-57ce-b412-fbd966d074cd"
version = "2.31.1"

[[deps.RecursiveFactorization]]
deps = ["LinearAlgebra", "LoopVectorization", "Polyester", "StrideArraysCore", "TriangularSolve"]
git-tree-sha1 = "3ee71214057e29a8466f5d70cfe745236aa1d9d7"
uuid = "f2c3362d-daeb-58d1-803e-2bc74f2840b4"
version = "0.2.11"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.ReinforcementLearning]]
deps = ["Reexport", "ReinforcementLearningBase", "ReinforcementLearningCore", "ReinforcementLearningEnvironments", "ReinforcementLearningZoo"]
git-tree-sha1 = "2881fad4f9d1d4c887d24d8fc1a1412955ef011b"
uuid = "158674fc-8238-5cab-b5ba-03dfc80d1318"
version = "0.10.1"

[[deps.ReinforcementLearningBase]]
deps = ["AbstractTrees", "CommonRLInterface", "Markdown", "Random", "Test"]
git-tree-sha1 = "1827f00111ea7731d632b8382031610dc98d8747"
uuid = "e575027e-6cd6-5018-9292-cdc6200d2b44"
version = "0.9.7"

[[deps.ReinforcementLearningCore]]
deps = ["AbstractTrees", "Adapt", "ArrayInterface", "CUDA", "CircularArrayBuffers", "Compat", "Dates", "Distributions", "ElasticArrays", "FillArrays", "Flux", "Functors", "GPUArrays", "LinearAlgebra", "MacroTools", "Markdown", "ProgressMeter", "Random", "ReinforcementLearningBase", "Setfield", "Statistics", "StatsBase", "UnicodePlots", "Zygote"]
git-tree-sha1 = "0aa856c34ec7c72810888f9d35ca701c025a76f4"
uuid = "de1b191a-4ae0-4afa-a27b-92d07f46b2d6"
version = "0.8.11"

[[deps.ReinforcementLearningEnvironments]]
deps = ["DelimitedFiles", "IntervalSets", "LinearAlgebra", "MacroTools", "Markdown", "Pkg", "Random", "ReinforcementLearningBase", "Requires", "SparseArrays", "StatsBase"]
git-tree-sha1 = "c47e65c7cdbc8ddaa034af2185d5bf0fc55f5a80"
uuid = "25e41dd2-4622-11e9-1641-f1adca772921"
version = "0.6.12"

[[deps.ReinforcementLearningZoo]]
deps = ["AbstractTrees", "CUDA", "CircularArrayBuffers", "DataStructures", "Dates", "Distributions", "Flux", "IntervalSets", "LinearAlgebra", "Logging", "MacroTools", "Random", "ReinforcementLearningBase", "ReinforcementLearningCore", "Setfield", "Statistics", "StatsBase", "StructArrays", "Zygote"]
git-tree-sha1 = "92c9e53ec08e8db53a92829a39a963156bd3f44a"
uuid = "d607f57d-ee1e-4ba7-bcf2-7734c1e31854"
version = "0.5.11"

[[deps.RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "22c5201127d7b243b9ee1de3b43c408879dff60f"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "0.3.0"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.ResettableStacks]]
deps = ["StaticArrays"]
git-tree-sha1 = "256eeeec186fa7f26f2801732774ccf277f05db9"
uuid = "ae5879a3-cd67-5da8-be7f-38c6eb64a37b"
version = "1.1.1"

[[deps.Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "bf3188feca147ce108c76ad82c2792c57abe7b1f"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.7.0"

[[deps.Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "68db32dff12bb6127bac73c209881191bf0efbb7"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.3.0+0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.SIMDDualNumbers]]
deps = ["ForwardDiff", "IfElse", "SLEEFPirates", "VectorizationBase"]
git-tree-sha1 = "dd4195d308df24f33fb10dde7c22103ba88887fa"
uuid = "3cdde19b-5bb0-4aaf-8931-af3e248e098b"
version = "0.1.1"

[[deps.SIMDTypes]]
git-tree-sha1 = "330289636fb8107c5f32088d2741e9fd7a061a5c"
uuid = "94e857df-77ce-4151-89e5-788b33177be4"
version = "0.1.0"

[[deps.SLEEFPirates]]
deps = ["IfElse", "Static", "VectorizationBase"]
git-tree-sha1 = "7ee0e13ac7cd77f2c0e93bff8c40c45f05c77a5a"
uuid = "476501e8-09a2-5ece-8869-fb82de89a1fa"
version = "0.6.33"

[[deps.SciMLBase]]
deps = ["ArrayInterfaceCore", "CommonSolve", "ConstructionBase", "Distributed", "DocStringExtensions", "IteratorInterfaceExtensions", "LinearAlgebra", "Logging", "Markdown", "RecipesBase", "RecursiveArrayTools", "StaticArraysCore", "Statistics", "Tables", "TreeViews"]
git-tree-sha1 = "55f38a183d472deb6893bdc3a962a13ea10c60e4"
uuid = "0bca4576-84f4-4d90-8ffe-ffa030f20462"
version = "1.42.4"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "0b4b7f1393cff97c33891da2a0bf69c6ed241fda"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.1.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "Requires"]
git-tree-sha1 = "38d88503f695eb0301479bc9b0d4320b378bafe5"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "0.8.2"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SparseDiffTools]]
deps = ["Adapt", "ArrayInterface", "Compat", "DataStructures", "FiniteDiff", "ForwardDiff", "Graphs", "LinearAlgebra", "Requires", "SparseArrays", "StaticArrays", "VertexSafeGraphs"]
git-tree-sha1 = "314a07e191ea4a5ea5a2f9d6b39f03833bde5e08"
uuid = "47a9eef4-7e08-11e9-0b38-333d64bd3804"
version = "1.21.0"

[[deps.SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "d75bda01f8c31ebb72df80a46c88b25d1c79c56d"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.1.7"

[[deps.StableRNGs]]
deps = ["Random", "Test"]
git-tree-sha1 = "3be7d49667040add7ee151fefaf1f8c04c8c8276"
uuid = "860ef19b-820b-49d6-a774-d7a799459cd3"
version = "1.0.0"

[[deps.Static]]
deps = ["IfElse"]
git-tree-sha1 = "5d2c08cef80c7a3a8ba9ca023031a85c263012c5"
uuid = "aedffcd0-7271-4cad-89d0-dc628f76c6d3"
version = "0.6.6"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "Random", "StaticArraysCore", "Statistics"]
git-tree-sha1 = "e972716025466461a3dc1588d9168334b71aafff"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.5.1"

[[deps.StaticArraysCore]]
git-tree-sha1 = "66fe9eb253f910fe8cf161953880cfdaef01cdf0"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.0.1"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "2c11d7290036fe7aac9038ff312d3b3a2a5bf89e"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.4.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "48598584bacbebf7d30e20880438ed1d24b7c7d6"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.18"

[[deps.StatsFuns]]
deps = ["ChainRulesCore", "HypergeometricFunctions", "InverseFunctions", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "5783b877201a82fc0014cbf381e7e6eb130473a4"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "1.0.1"

[[deps.SteadyStateDiffEq]]
deps = ["DiffEqBase", "DiffEqCallbacks", "LinearAlgebra", "NLsolve", "Reexport", "SciMLBase"]
git-tree-sha1 = "fa04638e98850332978467a085e58aababfa203a"
uuid = "9672c7b4-1e72-59bd-8a11-6ac3964bc41f"
version = "1.8.0"

[[deps.StochasticDiffEq]]
deps = ["Adapt", "ArrayInterface", "DataStructures", "DiffEqBase", "DiffEqNoiseProcess", "DocStringExtensions", "FillArrays", "FiniteDiff", "ForwardDiff", "JumpProcesses", "LevyArea", "LinearAlgebra", "Logging", "MuladdMacro", "NLsolve", "OrdinaryDiffEq", "Random", "RandomNumbers", "RecursiveArrayTools", "Reexport", "SciMLBase", "SparseArrays", "SparseDiffTools", "StaticArrays", "UnPack"]
git-tree-sha1 = "fbefdd80ccbabf9d7c402dbaf845afde5f4cf33d"
uuid = "789caeaf-c7a9-5a7d-9973-96adeb23e2a0"
version = "6.50.0"

[[deps.StrideArraysCore]]
deps = ["ArrayInterface", "CloseOpenIntervals", "IfElse", "LayoutPointers", "ManualMemory", "SIMDTypes", "Static", "ThreadingUtilities"]
git-tree-sha1 = "ac730bd978bf35f9fe45daa0bd1f51e493e97eb4"
uuid = "7792a7ef-975c-4747-a70f-980b88e8d1da"
version = "0.3.15"

[[deps.StructArrays]]
deps = ["Adapt", "DataAPI", "StaticArrays", "Tables"]
git-tree-sha1 = "ec47fb6069c57f1cee2f67541bf8f23415146de7"
uuid = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
version = "0.6.11"

[[deps.SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "Pkg", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"

[[deps.Sundials]]
deps = ["CEnum", "DataStructures", "DiffEqBase", "Libdl", "LinearAlgebra", "Logging", "Reexport", "SparseArrays", "Sundials_jll"]
git-tree-sha1 = "6549d3b1b5cf86446949c62616675588159ea2fb"
uuid = "c3572dad-4567-51f8-b174-8c6c989267f4"
version = "4.9.4"

[[deps.Sundials_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "OpenBLAS_jll", "Pkg", "SuiteSparse_jll"]
git-tree-sha1 = "04777432d74ec5bc91ca047c9e0e0fd7f81acdb6"
uuid = "fb77eaff-e24c-56d4-86b1-d163f2edb164"
version = "5.2.1+0"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "5ce79ce186cc678bbb5c5681ca3379d1ddae11a1"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.7.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[deps.TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.ThreadingUtilities]]
deps = ["ManualMemory"]
git-tree-sha1 = "f8629df51cab659d70d2e5618a430b4d3f37f2c3"
uuid = "8290d209-cae3-49c0-8002-c8c24d57dab5"
version = "0.5.0"

[[deps.TimerOutputs]]
deps = ["ExprTools", "Printf"]
git-tree-sha1 = "464d64b2510a25e6efe410e7edab14fffdc333df"
uuid = "a759f4b9-e2f1-59dc-863e-4aeb61b1ea8f"
version = "0.5.20"

[[deps.TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "216b95ea110b5972db65aa90f88d8d89dcb8851c"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.6"

[[deps.TreeViews]]
deps = ["Test"]
git-tree-sha1 = "8d0d7a3fe2f30d6a7f833a5f19f7c7a5b396eae6"
uuid = "a2a6695c-b41b-5b7d-aed9-dbfdeacea5d7"
version = "0.3.0"

[[deps.TriangularSolve]]
deps = ["CloseOpenIntervals", "IfElse", "LayoutPointers", "LinearAlgebra", "LoopVectorization", "Polyester", "Static", "VectorizationBase"]
git-tree-sha1 = "caf797b6fccbc0d080c44b4cb2319faf78c9d058"
uuid = "d5829a12-d9aa-46ab-831f-fb7c9ab06edf"
version = "0.1.12"

[[deps.URIs]]
git-tree-sha1 = "97bbe755a53fe859669cd907f2d96aee8d2c1355"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.3.0"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[deps.UnicodePlots]]
deps = ["ColorTypes", "Contour", "Crayons", "Dates", "FileIO", "FreeTypeAbstraction", "LazyModules", "LinearAlgebra", "MarchingCubes", "NaNMath", "Printf", "SparseArrays", "StaticArrays", "StatsBase", "Unitful"]
git-tree-sha1 = "ae67ab0505b9453655f7d5ea65183a1cd1b3cfa0"
uuid = "b8865327-cd53-5732-bb35-84acbb429228"
version = "2.12.4"

[[deps.Unitful]]
deps = ["ConstructionBase", "Dates", "LinearAlgebra", "Random"]
git-tree-sha1 = "b649200e887a487468b71821e2644382699f1b0f"
uuid = "1986cc42-f94f-5a68-af5c-568840ba703d"
version = "1.11.0"

[[deps.Unzip]]
git-tree-sha1 = "34db80951901073501137bdbc3d5a8e7bbd06670"
uuid = "41fe7b60-77ed-43a1-b4f0-825fd5a5650d"
version = "0.1.2"

[[deps.VectorizationBase]]
deps = ["ArrayInterface", "CPUSummary", "HostCPUFeatures", "IfElse", "LayoutPointers", "Libdl", "LinearAlgebra", "SIMDTypes", "Static"]
git-tree-sha1 = "c95d242ade2d67c1510ce52d107cfca7a83e0b4e"
uuid = "3d5dd08c-fd9d-11e8-17fa-ed2836048c2f"
version = "0.21.33"

[[deps.VertexSafeGraphs]]
deps = ["Graphs"]
git-tree-sha1 = "8351f8d73d7e880bfc042a8b6922684ebeafb35c"
uuid = "19fa3120-7c27-5ec5-8db8-b0b0aa330d6f"
version = "0.2.0"

[[deps.Wayland_jll]]
deps = ["Artifacts", "Expat_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "3e61f0b86f90dacb0bc0e73a0c5a83f6a8636e23"
uuid = "a2964d1f-97da-50d4-b82a-358c7fce9d89"
version = "1.19.0+0"

[[deps.Wayland_protocols_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4528479aa01ee1b3b4cd0e6faef0e04cf16466da"
uuid = "2381bf8a-dfd0-557d-9999-79630e7b1b91"
version = "1.25.0+0"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "58443b63fb7e465a8a7210828c91c08b92132dff"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.9.14+0"

[[deps.XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[deps.Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "5be649d550f3f4b95308bf0183b82e2582876527"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.6.9+4"

[[deps.Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4e490d5c960c314f33885790ed410ff3a94ce67e"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.9+4"

[[deps.Xorg_libXcursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXfixes_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "12e0eb3bc634fa2080c1c37fccf56f7c22989afd"
uuid = "935fb764-8cf2-53bf-bb30-45bb1f8bf724"
version = "1.2.0+4"

[[deps.Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fe47bd2247248125c428978740e18a681372dd4"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.3+4"

[[deps.Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[deps.Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "0e0dc7431e7a0587559f9294aeec269471c991a4"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "5.0.3+4"

[[deps.Xorg_libXi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXfixes_jll"]
git-tree-sha1 = "89b52bc2160aadc84d707093930ef0bffa641246"
uuid = "a51aa0fd-4e3c-5386-b890-e753decda492"
version = "1.7.10+4"

[[deps.Xorg_libXinerama_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll"]
git-tree-sha1 = "26be8b1c342929259317d8b9f7b53bf2bb73b123"
uuid = "d1454406-59df-5ea1-beac-c340f2130bc3"
version = "1.1.4+4"

[[deps.Xorg_libXrandr_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "34cea83cb726fb58f325887bf0612c6b3fb17631"
uuid = "ec84b674-ba8e-5d96-8ba1-2a689ba10484"
version = "1.5.2+4"

[[deps.Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[deps.Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6783737e45d3c59a4a4c4091f5f88cdcf0908cbb"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.0+3"

[[deps.Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "daf17f441228e7a3833846cd048892861cff16d6"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.13.0+3"

[[deps.Xorg_libxkbfile_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "926af861744212db0eb001d9e40b5d16292080b2"
uuid = "cc61e674-0454-545c-8b26-ed2c68acab7a"
version = "1.1.0+4"

[[deps.Xorg_xcb_util_image_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "0fab0a40349ba1cba2c1da699243396ff8e94b97"
uuid = "12413925-8142-5f55-bb0e-6d7ca50bb09b"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll"]
git-tree-sha1 = "e7fd7b2881fa2eaa72717420894d3938177862d1"
uuid = "2def613f-5ad1-5310-b15b-b15d46f528f5"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_keysyms_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "d1151e2c45a544f32441a567d1690e701ec89b00"
uuid = "975044d2-76e6-5fbe-bf08-97ce7c6574c7"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_renderutil_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "dfd7a8f38d4613b6a575253b3174dd991ca6183e"
uuid = "0d47668e-0667-5a69-a72c-f761630bfb7e"
version = "0.3.9+1"

[[deps.Xorg_xcb_util_wm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "e78d10aab01a4a154142c5006ed44fd9e8e31b67"
uuid = "c22f9ab0-d5fe-5066-847c-f4bb1cd4e361"
version = "0.4.1+1"

[[deps.Xorg_xkbcomp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxkbfile_jll"]
git-tree-sha1 = "4bcbf660f6c2e714f87e960a171b119d06ee163b"
uuid = "35661453-b289-5fab-8a00-3d9160c6a3a4"
version = "1.4.2+4"

[[deps.Xorg_xkeyboard_config_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xkbcomp_jll"]
git-tree-sha1 = "5c8424f8a67c3f2209646d4425f3d415fee5931d"
uuid = "33bec58e-1273-512f-9401-5d533626f822"
version = "2.27.0+4"

[[deps.Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "79c31e7844f6ecf779705fbc12146eb190b7d845"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.4.0+3"

[[deps.ZipFile]]
deps = ["Libdl", "Printf", "Zlib_jll"]
git-tree-sha1 = "3593e69e469d2111389a9bd06bac1f3d730ac6de"
uuid = "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"
version = "0.9.4"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[deps.Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e45044cd873ded54b6a5bac0eb5c971392cf1927"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.2+0"

[[deps.Zygote]]
deps = ["AbstractFFTs", "ChainRules", "ChainRulesCore", "DiffRules", "Distributed", "FillArrays", "ForwardDiff", "IRTools", "InteractiveUtils", "LinearAlgebra", "LogExpFunctions", "MacroTools", "NaNMath", "Random", "Requires", "SparseArrays", "SpecialFunctions", "Statistics", "ZygoteRules"]
git-tree-sha1 = "3cfdb31b517eec4173584fba2b1aa65daad46e09"
uuid = "e88e6eb3-aa80-5325-afca-941959d7151f"
version = "0.6.41"

[[deps.ZygoteRules]]
deps = ["MacroTools"]
git-tree-sha1 = "8c1a8e4dfacb1fd631745552c8db35d0deb09ea0"
uuid = "700de1a5-db45-46bc-99cf-38207098b444"
version = "0.2.2"

[[deps.libaom_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3a2ea60308f0996d26f1e5354e10c24e9ef905d4"
uuid = "a4ae2306-e953-59d6-aa16-d00cac43593b"
version = "3.4.0+0"

[[deps.libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"

[[deps.libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[deps.libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "94d180a6d2b5e55e447e2d27a29ed04fe79eb30c"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.38+0"

[[deps.libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "b910cb81ef3fe6e78bf6acee440bda86fd6ae00c"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+1"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"

[[deps.x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[deps.x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"

[[deps.xkbcommon_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll", "Wayland_protocols_jll", "Xorg_libxcb_jll", "Xorg_xkeyboard_config_jll"]
git-tree-sha1 = "ece2350174195bb31de1a63bea3a41ae1aa593b6"
uuid = "d8fb68d0-12a3-5cfd-a85a-d49703b185fd"
version = "0.9.1+5"
"""

# ╔═╡ Cell order:
# ╟─ec5ed565-26bb-43b3-bf76-d1c7bd5496d1
# ╟─fe976d47-f3f2-42f2-9315-01a5766ad01f
# ╟─c39174d0-b3a7-41fb-bd62-276d6f538111
# ╟─2a5a4798-341a-4c0b-98db-4db1cd45047c
# ╟─91101688-0f53-43a4-a7f0-10a0c60cfb36
# ╠═c233e8bb-547f-409e-a5cc-bae14b248fce
# ╠═56321ee4-55eb-4cb8-ba0c-765425b1a2e8
# ╠═cb5eb128-95a7-4a4f-ae10-12cef0114fc4
# ╠═e8de9781-51ae-4d39-98ae-d6d9d4bd4133
# ╠═af94357b-610a-4497-9e25-4be9a4e6b118
# ╟─9c6b303a-cd04-4893-a962-663458c52999
# ╠═6c11b2f8-1545-4dfd-9fd0-5d9fd51fcd29
# ╠═55254db7-522a-45f8-9885-f99ea2654dbb
# ╠═150d93ef-d17f-40eb-b81d-bf74b698c3da
# ╠═3b50e947-5af4-4ae2-8e53-01008274982b
# ╠═2cb966ab-e129-44ce-b76d-3c718a16f879
# ╠═86d70d8f-fb4a-4f7b-94d8-d5e8e8018d61
# ╠═ba227c04-8e74-4327-b1a7-6e75322192d7
# ╠═1998d403-8476-4a0e-b681-8c2252e69bed
# ╠═8fb6ec3a-67e2-4316-834a-c80f20477ed4
# ╠═6d0b546a-8536-4d6a-80f2-6596bae0c193
# ╟─d89c10e7-80cc-443e-bf5c-ef657f75903c
# ╠═5cc7cbc5-5dd5-42a1-a171-f87838e5a9b8
# ╠═f63fb266-2db3-449f-a068-a2693c7eab50
# ╠═423c0a27-7c62-421f-a12f-984d41b1d813
# ╠═d9afab58-a2a4-4c54-99a6-9cfd98d7a374
# ╠═001ec938-b9be-4c62-af16-11e63b6fb10b
# ╠═39a35b1a-2512-444f-8df7-3e2aa81c71a8
# ╠═e34303ff-4e55-4d73-858f-79db366e6ada
# ╠═dc7c2d91-2542-4df1-ba18-c671f4e42370
# ╟─210d17b4-9e6b-458b-bc85-5a6e63055890
# ╠═fd37de83-ced0-48da-b932-e017183184f5
# ╠═888b1660-de93-46a7-b246-bf98b6680bc7
# ╟─46430782-9bc0-462b-891e-c006179c792b
# ╠═a0575bec-7ac2-4288-b5f1-59b966dc9ac3
# ╠═a3199ba1-a660-468d-ac10-ec3acbe6ce86
# ╠═b0764acd-70f4-44b7-9eb6-8a6ecf9a2e78
# ╠═983a77fd-62fc-4147-a0d3-c10b32ee71cc
# ╠═8aeae588-b63a-47c2-87a6-a954f594d3cc
# ╟─2a51d9be-b6a2-4f2e-8f21-148310d6f481
# ╠═f9c195dc-676d-41bf-8b67-a5da3998d7bb
# ╟─4706b18d-64ff-40d4-b556-695684e388ab
# ╠═78a69da9-df5f-4c94-82d8-06b633c3a34a
# ╠═788e2704-1b8b-45e7-b65e-49facc64423d
# ╠═f3eb7c53-dc2f-41a7-ba10-d027713098af
# ╠═8797b80d-0baa-4e6e-857f-09058b91e969
# ╠═09579ac9-6a41-4e30-9b99-ddb6f5b387ff
# ╟─8c24dc44-019c-4fe6-a563-5dbb7896d9f0
# ╠═2833d140-487b-44a7-b91f-04e5ecf715b2
# ╠═99964a25-3f79-4716-bd10-f193ce26e555
# ╠═411866fa-1540-43f2-8d45-4a617714c2cd
# ╠═bd41bec9-3f10-4dc4-8180-c4ba90848abe
# ╠═3f36d62b-6a1b-4bd5-9054-825ac49a4631
# ╠═c596f70f-ca3b-4345-b2c4-75e1d96a75b4
# ╠═ceb871f0-a7c3-421d-8403-c24f118fdc9c
# ╠═2ff50d8d-8c0e-4e0d-af95-937770106650
# ╠═c67ec070-5621-4bbe-ac01-e8b2da875090
# ╠═851b9f62-766e-48c6-96a4-f6026535db6f
# ╠═7f7429f5-ab6e-4533-b5f8-ab52cec2bda8
# ╟─d6e4b562-7b8f-4cf9-9364-cc115346da7a
# ╠═db3889ba-2c3a-443c-9e0e-ee93090cdf49
# ╠═fe570421-def3-45d4-8c9d-53d0eb26f7a0
# ╠═8d3be9d2-eef1-4547-9abe-4eb1a4390448
# ╠═14c98b36-48c9-4d08-a28a-b52973013258
# ╠═544c96b7-e2bd-4017-a477-8cf36ebba491
# ╠═e0573f1f-067e-4b23-975a-afbec7e1f1cb
# ╠═d68003bb-e4f0-4e1a-9f56-64195bddcac1
# ╠═be6fdc11-b851-402c-8f3d-9d9b05ddb02b
# ╠═0fa50f7c-2509-448f-9538-0bc768c7e0a3
# ╠═8c93ec50-dd77-41b2-90cb-fb3247aae014
# ╠═d5555915-1144-41e3-bf09-9e2046b44a23
# ╟─b8c81229-f6de-4276-8720-aff3416bc52c
# ╠═9d290533-515d-41f3-9927-cb3b71a46375
# ╠═fc3c687e-7c80-4ddd-b341-75850792dd76
# ╠═7351db8a-6dce-423b-b137-a08a6a0d2517
# ╠═b1818829-aa28-4994-9b41-6328090e83c2
# ╠═5861b2b5-10c4-49e1-a756-63edea4cb206
# ╠═0b757ad5-48c0-470d-a20e-b13683286365
# ╠═eeb750eb-31aa-49f7-81db-f0337ae3b74d
# ╠═a26b8f74-7971-4d40-87a5-839aad126fc2
# ╠═69f0616b-0321-44ee-969e-f403812707b2
# ╠═62e65a0f-de32-4b43-b9fb-294df64ce71f
# ╠═f1c8735f-4fa9-4843-902a-e562b22f918a
# ╟─020a13eb-318b-4e4c-827c-96e599f6f891
# ╠═86a6447f-71ff-44c1-9ada-709f56a5ad2f
# ╠═744660cf-325e-44fc-8041-9a10f4df5a07
# ╠═7c548d75-8dad-4969-9e2a-f54038d055f3
# ╠═0e73ec15-5b68-4785-8a1b-2c3a71354da1
# ╠═0f36523a-ad70-4d66-b1ef-fa203ffe1a15
# ╠═98cadad1-85ff-44a4-ad5d-9d0865985753
# ╠═c0d901a4-8cad-4100-a8ea-c0333e7546aa
# ╠═0ffcc67c-fe73-4952-98c5-6f3ada1bc7fd
# ╠═a3d9c05c-0d30-41e5-8043-30602b215142
# ╟─a940c40f-5d8e-4dd8-9c39-9a2f738a6f91
# ╠═a70e9f5d-9529-4464-a9df-ee3340358479
# ╠═345dd53c-a470-4e31-aa6d-4c73d8e23ded
# ╠═b41bc759-9765-418c-bdb1-35042ccad70f
# ╠═aee1fc47-977f-4b42-8356-760e47fdc553
# ╠═4686b68d-4fba-4b90-a7d4-3292004b2b7e
# ╠═1975467a-2df8-4d19-af49-b387b1b1e0a3
# ╠═fc2a4f34-c3fb-4335-a857-9f21f7af7f2b
# ╠═7a8497d7-0bf1-48d0-904a-9485c7fee08a
# ╠═fc24737b-66eb-48f4-a5ae-5f40be19345c
# ╠═d298b997-311f-43dd-9b8c-60ae01888ecb
# ╠═ce09240d-1521-4a1d-9013-d272183ec4bf
# ╠═c48a4be4-a1c1-4cea-8c9e-c353bc637a8d
# ╟─fcbb1746-c41d-4176-a4d7-d2f8a3e82df6
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
