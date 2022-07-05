export MDPAgent, solve

""" 
    mutable struct MDPAgent
        mdp::AbstractEnv
        agent::AbstractPolicy
    end

Defines a discrete machine that consists of an MDP and the agent capable of solving it. Running solve() will iterate through 1 episode of the MDP and return a
done signal. The MDP follows the specification from ReinforcementLearning.jl. Each MDP, of type AbstractEnv, has the following functions:
- action_space(env::YourEnv)
- state(env::YourEnv)
- state_space(env::YourEnv)
- reward(env::YourEnv)
- is_terminated(env::YourEnv)
- reset!(env::YourEnv)
- (env::YourEnv)(action) # note this function applies your action to the environment and steps forward in time.
See https://juliareinforcementlearning.org/docs/How_to_write_a_customized_environment/ for more details on how to write a custom environment. Alternatively,
see https://github.com/JuliaReinforcementLearning/ReinforcementLearning.jl/tree/master/src/ReinforcementLearningExperiments/deps/experiments/experiments for examples of used environments. 

The agent also comes from ReinforcementLearning.jl. See https://github.com/JuliaReinforcementLearning/ReinforcementLearning.jl/blob/61256bcf1c493914d5003f22e126c997332c2c39/src/ReinforcementLearningBase/src/interface.jl
for a full definition. Mainly, it defines the following functions:
- (policy::AbstractPolicy)(env) = returns an action from the policy given the environment
- update(policy::AbstractPolicy, experience) = updates the policy based on an online or offline experience

"""
mutable struct MDPAgent
    mdp::AbstractEnv
    agent::AbstractPolicy
end


# exposing some useful functions of the interface to the outside
action_space(MDPAgent::MDPAgent) = action_space(MDPAgent.mdp)
state(MDPAgent::MDPAgent) = state(MDPAgent.mdp)
state_space(MDPAgent::MDPAgent) = state_space(MDPAgent.mdp)
is_terminated(MDPAgent::MDPAgent) = RLBase.is_terminated(MDPAgent.mdp)
is_terminated(vec::Vector{MDPAgent}) = is_terminated(vec[1])

"""
    solve(mdpAgent::MDPAgent, display = false)

Runs 1 episode of the environment under the policy provided by the agent.

Arguments:
- mdpAgent - The MDPAgent you constructed, which contains an MDP following the AbstractEnv interface and an agent following the AbstractPolicy interface.
- display - Whether or not to display the environment each step. Displaying is done via calling Base.display, so overwrite Base.display(yourEnv) in order to view your environment being solved.
Returns:
- The accumulated reward over the episode as returned by the environment
"""
function solve(mdpAgent::MDPAgent, display = false)
    env, agent = mdpAgent.mdp, mdpAgent.agent
	hook = TotalRewardPerEpisode(is_display_on_exit = false)
    stop_condition = StopAfterEpisode(1; is_show_progress=false)
	_run(agent, env, stop_condition, hook, display)
    return hook.rewards
end

"""
    Base.collect(mdpagent::MDPAgent) 

Overwrites base.collect for our class since it will be used by Algebraic dynamics. Simply returns the mdpAgent since there is nothing to collect.
Note collect is usually used to return an array of elements from a collection or iterator 
"""
Base.collect(mdpagent::MDPAgent) = mdpagent 

"""
    _run(policy::AbstractPolicy, env::AbstractEnv, stop_condition, hook::AbstractHook, display=false)

Note this function is taken directly from ReinforcementLearning.jl
The only thing crucial change was removing the reset!(env) because we already do that before calling solve. See MDPAgentMAchine.
We can also set display=true, which will call Base.display(env) every step. Set the Base.display(yourEnv) to be a rendering function
and set display = true to view the machine in action. 
https://github.com/JuliaReinforcementLearning/ReinforcementLearning.jl/blob/cc04e9a3a2d68dba69932dd6e8ce0eac5a9a66c9/src/ReinforcementLearningCore/src/core/run.jl
"""
function _run(policy::AbstractPolicy, env::AbstractEnv, stop_condition, hook::AbstractHook, display=false)

    hook(PRE_EXPERIMENT_STAGE, policy, env)
    policy(PRE_EXPERIMENT_STAGE, env)
    is_stop = false
    while !is_stop
        # reset!(env)
        # policy(PRE_EPISODE_STAGE, env)
        hook(PRE_EPISODE_STAGE, policy, env)

        while !RLBase.is_terminated(env) # one episode
            action = policy(env)

            policy(PRE_ACT_STAGE, env, action)
            hook(PRE_ACT_STAGE, policy, env, action)

            env(action)

            if display
                Base.display(env)
            end

            policy(POST_ACT_STAGE, env)
            hook(POST_ACT_STAGE, policy, env)

            if stop_condition(policy, env)
                is_stop = true
                break
            end
        end # end of an episode

        if RLBase.is_terminated(env)
#             policy(POST_EPISODE_STAGE, env)  # let the policy see the last observation
            hook(POST_EPISODE_STAGE, policy, env)
        end
    end
    hook(POST_EXPERIMENT_STAGE, policy, env)
    hook
end