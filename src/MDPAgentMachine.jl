export MDPAgentMachine, read_output, default_input_function, default_output_function

"""
    default_output_function(env::AbstractEnv)

Returns the result of the mdp episode. Is it done or not? 
To do a more sophisticated readout, such as reading internal state, write your own function with 
the same arguments that returns a vector. 
Output vector length must be the same length as specified by output_size in the function call to MDPAgentMachine

Arguments: 
- `env` - A MDP following the AbstractEnv interface

Returns:
- 1.0 if the environment is terminated, 0.0 otherwise.
"""
function default_output_function(env::AbstractEnv)
    return RLBase.is_terminated(env)
end

"""
    default_input_function(env::AbstractEnv, internal_state::Vector)

Sets the internal state of the mdp to be the internal state provided. Default function does nothing. 
To customize, create your own function with the same arguments.
The internal state must be the same size as the size given by input_size in the function call to MDPAgentMachine

Arguments:
- `env` - A MDP following the AbstractEnv interface
- `internal_state` - A vector which contains the information needed to set the internal state. In the `default_input_function`, does nothing.

Returns:
- nothing
"""
function default_input_function(env::AbstractEnv, internal_state::Vector)

end


#=

Developor WARNING:

    The below function MDPAgentMachine does a bad practice (on purpose). This warning is added to explain it and hopefully easy
    debugging at a later date. 

    During development, we wanted to have our machine contain the MDP and the agent as internal variables. However, 
    AlgebraicDynamics is designed to store the internal variables of a machine outside the machine. This is the 'u' 
    in eval_dynamics(m,u,x,p,t) and readout(m,u,x,p). 

    This is a big pain for the end user. They do not care about internal variables in this case, they just want a machine.
    So we are storing the MDP and the agent inside the machine. But since we cannot modify the AlgebraicDynamics machine defintion,
    we "hackishly" added it below.

    The MDP and agent are arguments to the function MDPAgentMachine. They are used in equation_MDPAgent and readout_MDPAgent
    They are not stored inside any struct, they are stored in global namespace and the functions keep a reference to them internally.
    Thus, a given machine can access the MDP and agent used to create the machine without storing them. 

    This is bad practice because the variable should be stored in the machine but it is not. However, it greatly simplifies the 
    API for the end user, who does not care to keep track of these things on their own.

    Be careful when modifying MDPs or Agents after using them to create a machine. It has worked so far, but you may get weird results.


=#


"""
    MDPAgentMachine(    env::AbstractEnv, agent::AbstractPolicy,
                        ;input_size = 1, input_function = default_input_function,
                        output_size = 1, output_function = default_output_function,
                        display = false, resetMDP = true
                        )

This function returns a DiscreteMachine from AlgebraicDynamics

The env and agent must follow the respective interfaces from ReinforcementLearning.jl

By default, the internal workings of the machine does not use the input provided to `eval_dynamics`. This can be overwritten by using
a custom input function. Make sure the size of the vector in your input function is the same as the `input_size` you provide.

Its output is true if the MDP is terminated and false otherwise. This can also be overwritten by providing a custom output function.
Once again, make sure the size of the output vector is the same as the `output_size` you provide in this function call.

You can also reset the environment before running the machine if you wish. This is useful in some cases to make sure the environment is
in a good state, but it is bad in other cases. So, you are able to control if it is reset or not.

You can also choose to display the environment each timestep by setting display = true. It will call Base.display(env), so you
must overwrite Base.display for your environment in order to use that functionality.

Arguments:
- `env` - a MDP following the AbstractEnv interface
- `agent` - a agent/policy following the AbstractPolicy interface
- `input_size` - an int which must be equal to the size of the vector used by the input function
- `input_function` - a function which is called on the MDP before running an episode. Must have the same arguments as `default_input_function`
- `output_size` - an int which must be equal to the size of the vector returned by the output function
- `output_function` - a function which is called after the episode is terminated. Must have the same arguments as `default_input_function`. Returns a vector.
- `display` - whether or not to display the MDP every timestep. Calls Base.display(env) if true.
- `resetMDP` - whether or not to reset the MDP via reset!(env) before running an episode.
"""
function MDPAgentMachine( env::AbstractEnv, agent::AbstractPolicy,
                         ;input_size = 1, input_function = default_input_function,
                          output_size = 1, output_function = default_output_function,
                          display = false, resetMDP = true
                        )

    mdp_agent = MDPAgent(env, agent)
    number_inputs = input_size
    number_internal = 1 # Since it is just a single MDPAgent
    number_outputs = output_size 

    # u = internal state = the mdpAgent
    # x = external signal = not used
    # p = hyper parameters = not used
    # t = time = not used
    function equation_MDPAgent(u, x, p, t) 
        # in many cases we may want to reset the environment. However, sometimes we pass an in-progess MDP
        # as a state and then we dont want to reset it.
        if resetMDP
            reset!(mdp_agent.mdp)
        end

        # call input function to set state, run an episode, return
        @assert length(x) == number_inputs # if this fails, make sure the input_size = the length of inputs in the argument to your input function  
        input_function(mdp_agent.mdp, x)
        result = solve(mdp_agent, display)
        return [0.0] # AlgebraicDynamics expects a vector to be returned
    end

    function readout_MDPAgent(u,p,t)
        ret = output_function(mdp_agent.mdp)
        @assert length(ret) == number_outputs # if this fails, make sure your output_size = the number of outputs in your output function
        return ret
    end

    machine =  DiscreteMachine{Float64}(number_inputs,
                                    number_internal,
                                    number_outputs, 
                                    equation_MDPAgent, 
                                    readout_MDPAgent
                                    ) 
    return machine
end

"""
    AlgebraicDynamics.DWDDynam.eval_dynamics(f::AbstractMachine, xs=[0.0])

Runs an episode of the MDP following the policy given in the constructor for the machine. Is equilvalent to calling
eval_dynamics with zeros for the internal state variable. 

Arguments: 
- `f` - a machine created by MDPAgentMachine
- `xs` - external variables used for setting the initial state

Returns:
- a vector of zeros. IE basically nothing but AlgebraicDynamics requires a vector.
"""
AlgebraicDynamics.DWDDynam.eval_dynamics(f::AbstractMachine, xs=[0.0]) = eval_dynamics(f, zeros(nstates(f)), xs)


"""
    read_output(f::AbstractMachine)

Since we are not using internal variables via AlgebraicDynamics, we can overwrite readout
to assume zeros for those variables. This is convenient for our purposes. However, due to their API structure, we would have issues
if we tried to overwite readout(::AbstractMachine). Instead, we will simply rename the function to `read_output` for our purposes.

Arguments:
- `f` - a machine created by MDPAgentMachine

Returns:
- The result of the output_function specified in the function call to MDPAgentMachine
"""
read_output(f::AbstractMachine) = readout(f, zeros(nstates(f)))