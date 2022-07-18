export BoxMDP

mutable struct BoxMDP <: AbstractEnv
    super_env::FetchAndPlaceMDP
    last_action
end
BoxMDP() = BoxMDP(FetchAndPlaceMDP(Cartesian(0,0,0), Cartesian(0,0,0), Random.MersenneTwister(123)), (Cartesian(1,1,1), Cartesian(1,1,1)))

# This is a subprocess of the simulation. Follows the same state space, action space, transition, etc
# however, this mdp terminates when the arm becomes within 1 manhattan distance of the object
# at this point, the arm "picks up" the object, and the MDP is finished

RLBase.action_space(env::BoxMDP) = RLBase.action_space(env.super_env) 
RLBase.state(env::BoxMDP) = RLBase.state(env.super_env) 
RLBase.state_space(env::BoxMDP) = Space(
    ClosedInterval{Float64}[
        (0.0)..(10.0),
        (0.0)..(10.0),
        (0.0)..(10.0),
        (0.0)..(10.0),
        (0.0)..(10.0),
        (0.0)..(10.0),
    ],
)
function RLBase.reward(env::BoxMDP)
    directionToDestination = env.super_env.obj_position - env.super_env.arm_position # points from arm to obj
    action_arm = env.last_action[1]
    action_obj = env.last_action[2]
    arm_correct = DotProduct(directionToDestination, action_arm) / (Magnitude(directionToDestination) * Magnitude(action_arm) )
    obj_correct = DotProduct(directionToDestination * -1, action_obj) / (Magnitude(directionToDestination) * Magnitude(action_obj) )

    if isnan(arm_correct) || isnan(obj_correct )
        return -1
    end 

    return (arm_correct + obj_correct - 2)/4


end
function RLBase.reset!(env::BoxMDP)  # arm and object take random position within box
    new_state = map(x -> rand(env.super_env.rng, x), RLBase.state_space(env))
    env.super_env.arm_position.x = new_state[1]
    env.super_env.arm_position.y = new_state[2]
    env.super_env.arm_position.z = new_state[3]
    env.super_env.obj_position.x = new_state[4]
    env.super_env.obj_position.y = new_state[5]
    env.super_env.obj_position.z = new_state[6]
end
function (env::BoxMDP)(action)
    env.super_env(action)
    env.super_env.obj_position.x = clamp(env.super_env.obj_position.x, 0.0, 10.0)
    env.super_env.obj_position.y = clamp(env.super_env.obj_position.y, 0.0, 10.0)
    env.super_env.obj_position.z = clamp(env.super_env.obj_position.z, 0.0, 10.0)
    env.super_env.arm_position.x = clamp(env.super_env.arm_position.x, 0.0, 10.0)
    env.super_env.arm_position.y = clamp(env.super_env.arm_position.y, 0.0, 10.0)
    env.super_env.arm_position.z = clamp(env.super_env.arm_position.z, 0.0, 10.0)
    env.last_action = (Cartesian(action[1], action[2], action[3]), Cartesian(action[4], action[5], action[6]))
end
# this is how we specify this environment is different. it has an end condition
RLBase.is_terminated(env::BoxMDP) = CartesianDistance(env.super_env.obj_position, env.super_env.arm_position) < 1.0

function GR.plot(env::BoxMDP)
    
    # render the mode
    text(0.01, 0.95, "Box MDP")
    if RLBase.is_terminated(env)
        text(0.01, 0.90, "Task completed")
    end
    
    # render the arm and object
    render_circle(1.0, env.super_env.arm_position.x, env.super_env.arm_position.y,  env.super_env.arm_position.z,2, "Arm")
    render_circle(1.0, env.super_env.obj_position.x, env.super_env.obj_position.y,  env.super_env.obj_position.z,4, "Object")


    # render the box
    render_polygon([0,0,10,10], [0,10,10,0], 0, 0, 1)

    # do the normal rendering
    GR.plot(env.super_env)


end

