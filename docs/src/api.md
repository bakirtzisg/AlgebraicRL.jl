# API

### MDPAgent
```@docs
MDPAgent
solve(mdpAgent::MDPAgent, display = false)
Base.collect(mdpagent::MDPAgent) 

```

### MDPAgentMachine
```@docs
MDPAgentMachine(    env::AbstractEnv, agent::AbstractPolicy,
                        ;input_size = 1, input_function = default_input_function,
                        output_size = 1, output_function = default_output_function,
                        display = false, resetMDP = true
                        )
default_output_function(env::AbstractEnv)
default_input_function(env::AbstractEnv, internal_state::Vector)

```

#### MDPAgentMachine and AlgebraicDynamics.jl
The following relates to MDPAgentMachines and how they interact with the AlgebraicDynamics.jl interface. We are not using internal variables, which they call 'u', so we are able to simplify the function calls slightly. 

```@docs
AlgebraicDynamics.DWDDynam.eval_dynamics(f::AbstractMachine, xs=[0.0])
read_output(f::AbstractMachine)


```