export MDPAgentMachine, read_output


# returns the result of the mdp episode. Is it done or not? 
# To do a more sophisticated readout, such as reading internal state, write your own function with 
# the same arguments that returns an array
# array length must be the same length as the array specified by output_size in MDPAgentMachine
function default_output_function(env::AbstractEnv)
    return RLBase.is_terminated(env)
end

# sets the internal state of the mdp to be the internal state provided. By defualt, does nothing
# to customize, create your own function with the same arguments
# The internal state must be the same size as the size given by input_size
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



# this function returns a DiscreteMachine from AlgebraicDynamics
# by default, its input is not used, 
# its output is true if the MDP is terminated and false otherwise
function MDPAgentMachine( env::AbstractEnv, agent::AbstractPolicy,
                         ;input_size = 1, input_function = default_input_function,
                          output_size = 1, output_function = default_output_function
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
        # reset the environment to make sure its in a good state. 
        # do this before the input function so we can still set variables
        reset!(mdp_agent.mdp)

        # call input function to set state, run an episode, return
        @assert length(x) == number_inputs # if this fails, make sure the input_size = the length of inputs in the argument to your input function  
        input_function(mdp_agent.mdp, x)
        result = solve(mdp_agent)
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

# since we are not using internal variables via AlgebraicDynamics, we can overwrite some of their functions
# (eval_dynamics and readout) to assume zeros for those variables
# AlgebraicDynamics forces readout to have internal state as an argument. As a result, I cannot overwrite it
# I can however change the name to read_output and simply call readout with zeros for the internal state.
AlgebraicDynamics.DWDDynam.eval_dynamics(f::AbstractMachine, xs=[0.0]) = eval_dynamics(f, zeros(nstates(f)), xs)
read_output(f::AbstractMachine) = readout(f, zeros(nstates(f)))