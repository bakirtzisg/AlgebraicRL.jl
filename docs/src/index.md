# AlgebraicRL Documentation

```@docs
MDPAgent
solve(mdpAgent::MDPAgent, display = false)
Base.collect(mdpagent::MDPAgent) 
default_output_function(env::AbstractEnv)
default_input_function(env::AbstractEnv, internal_state::Vector)
MDPAgentMachine(    env::AbstractEnv, agent::AbstractPolicy,
                        ;input_size = 1, input_function = default_input_function,
                        output_size = 1, output_function = default_output_function,
                        display = false, resetMDP = true
                        )
AlgebraicDynamics.DWDDynam.eval_dynamics(f::AbstractMachine, xs=[0.0])
read_output(f::AbstractMachine)


```