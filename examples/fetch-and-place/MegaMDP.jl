export MegaMDP, mdp_symbols

mdp_symbols = [:Box, :Fetched, :Placed]
mutable struct MegaMDP <: AbstractEnv
    box::BoxMDP
    fetched::FetchedMDP
    placed::PlacedMDP
    current_MDP::Symbol
    t
    max_t
    reward
end
MegaMDP() = MegaMDP(BoxMDP(), FetchedMDP(), PlacedMDP(), mdp_symbols[1], 0, 1000, 0)

# This MDP combines the 3 subprocess MDPs into 1. Therefore to solve this MDP, and agent must solve all of the 3 sub process MDPs. 


# State space and action space are same as total simulation
RLBase.state_space(env::MegaMDP) = RLBase.state_space(env.box.super_env)
RLBase.action_space(env::MegaMDP) = RLBase.action_space(env.box) 

# state space depends on which goal we are currently trying to solve
function RLBase.state(env::MegaMDP)
    if env.current_MDP == mdp_symbols[1]
        return RLBase.state(env.box)
    elseif env.current_MDP == mdp_symbols[2]
        return RLBase.state(env.fetched)
    else
        return RLBase.state(env.placed)
    end
end


function RLBase.reward(env::MegaMDP)
    return env.reward
end

function RLBase.reset!(env::MegaMDP)  # arm and object take random position within box
    # want to fetch the rng, and keep the same instance, so we dont keep reusing the same random numbers
    rng = env.current_MDP == mdp_symbols[1] ? env.box.super_env.rng : 
          env.current_MDP == mdp_symbols[2] ? env.fetched.super_env.rng : 
                                              env.placed.super_env.rng
    env.box = BoxMDP()
    env.box.super_env.rng = rng
    env.fetched = FetchedMDP()
    env.placed = PlacedMDP()
    env.current_MDP = mdp_symbols[1]
    reset!(env.box)
    reset!(env.fetched)
    reset!(env.placed)
    env.fetched.t = -Inf
    env.t = 0
    env.reward = 0

end


function (env::MegaMDP)(action)
    # apply action to current MDP. Also record reward
    if env.current_MDP == mdp_symbols[1]
        env.box(action)
        env.reward = RLBase.reward(env.box)

    elseif env.current_MDP == mdp_symbols[2]
        env.fetched(action[1:3])
        env.reward = RLBase.reward(env.fetched)

    else
        env.placed(action)
        env.reward = RLBase.reward(env.placed)
    end

    # transition if needed
    if env.current_MDP == mdp_symbols[1] && RLBase.is_terminated(env.box)
        #println("Transition 1 to 2, t = ", env.t)
        env.fetched.super_env = env.box.super_env
        env.current_MDP = mdp_symbols[2]

    elseif env.current_MDP == mdp_symbols[2] && RLBase.is_terminated(env.fetched)
        #println("Transition 2 to 3, t = ", env.t)
        env.placed.super_env = env.fetched.super_env
        env.current_MDP = mdp_symbols[3]
    end
    # no need to transition away from last one, it will return terminated and will be reset
    env.t += 1

end

# this is how we specify this environment is different. it has an end condition
function RLBase.is_terminated(env::MegaMDP)
    return (env.current_MDP == mdp_symbols[3] && RLBase.is_terminated(env.placed)) || env.t > env.max_t
end

 
function GR.plot(env::MegaMDP)
    # render based on active mdp
    if env.current_MDP == mdp_symbols[1]
        GR.plot(env.box)
    elseif env.current_MDP == mdp_symbols[2]
        GR.plot(env.fetched)
    else
        GR.plot(env.placed)
    end

end