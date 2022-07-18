export PlacedMDP

mutable struct PlacedMDP <: AbstractEnv
    super_env::FetchAndPlaceMDP
end
PlacedMDP() = PlacedMDP(FetchAndPlaceMDP(Cartesian(0,0,0), Cartesian(0,0,0), Random.MersenneTwister(123)))

# This is a subprocess of the simulation. Follows the same state space, action space, transition, etc
# however, this mdp terminates when the arm and object are sufficiently far away. This simulates putting the object down, and moving
# away to show that the object is down

RLBase.action_space(env::PlacedMDP) = RLBase.action_space(env.super_env) 
RLBase.state(env::PlacedMDP) = RLBase.state(env.super_env) 
RLBase.state_space(env::PlacedMDP) = RLBase.state_space(env.super_env)
RLBase.reward(env::PlacedMDP) = -1 + CartesianDistance(env.super_env.obj_position, env.super_env.arm_position)/3
function RLBase.reset!(env::PlacedMDP) 
    env.super_env.arm_position.x = rand(env.super_env.rng, 0.0..30.0)
    env.super_env.arm_position.y = rand(env.super_env.rng, 0.0..30.0)
    env.super_env.arm_position.z = rand(env.super_env.rng, 0.0..30.0)
    env.super_env.obj_position.x = env.super_env.arm_position.x
    env.super_env.obj_position.y = env.super_env.arm_position.y
    env.super_env.obj_position.z = env.super_env.arm_position.z
end
(env::PlacedMDP)(action) = env.super_env(action)

# this is how we specify this environment is different. it has an end condition
RLBase.is_terminated(env::PlacedMDP) =  CartesianDistance(env.super_env.arm_position, env.super_env.obj_position) >= 3.0


function GR.plot(env::PlacedMDP)
    
    # render the mode
    text(0.01, 0.95, "Placed MDP")
    if RLBase.is_terminated(env)
        text(0.01, 0.90, "Task completed")
    end

    # render the arm and object
    render_circle(1.0, env.super_env.arm_position.x, env.super_env.arm_position.y,  env.super_env.arm_position.z,2, "Arm")
    render_circle(1.0, env.super_env.obj_position.x, env.super_env.obj_position.y,  env.super_env.obj_position.z,4, "Object")

    # do the normal rendering
    GR.plot(env.super_env)


end