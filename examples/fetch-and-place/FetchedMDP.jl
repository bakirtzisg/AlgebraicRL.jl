export FetchedMDP

mutable struct FetchedMDP <: AbstractEnv
    super_env::FetchAndPlaceMDP
    destination::Cartesian
    t
    last_action
end
FetchedMDP() = FetchedMDP(FetchAndPlaceMDP(Cartesian(0,0,0), Cartesian(0,0,0), Random.MersenneTwister(123)), Cartesian(20,20, 20), 0, Cartesian(1,1,1))

# This is a subprocess of the simulation. Follows the same state space, action space, transition, etc
# however, this mdp terminates when the arm becomes within 1 manhattan distance of the object
# at this point, the arm "picks up" the object, and the MDP is finished

# note this env has a modified state space, action space, state, and action because we know the position of the arm = position of the object

RLBase.action_space(env::FetchedMDP) = Space(RLBase.action_space(env.super_env)[1:3]) 
RLBase.state(env::FetchedMDP) = vcat(RLBase.state(env.super_env)[1:3], [env.destination.x, env.destination.y, env.destination.z])
RLBase.state_space(env::FetchedMDP) = RLBase.state_space(env.super_env)
function RLBase.reward(env::FetchedMDP)
    directionToDestination = env.destination - env.super_env.arm_position
    correct = DotProduct(directionToDestination, env.last_action) / (Magnitude(directionToDestination) * Magnitude(env.last_action))
    if isnan(correct) 
        return -1
    end 
    return (correct - 1) / 2
end

function RLBase.reset!(env::FetchedMDP)
    # arm/object is random position, destiatnion is random position within some limits to make it fast
    env.super_env.arm_position.x = rand(env.super_env.rng, 0.0..30.0)
    env.super_env.arm_position.y = rand(env.super_env.rng, 0.0..30.0)
    env.super_env.arm_position.z = rand(env.super_env.rng, 0.0..30.0)
    env.super_env.obj_position.x = env.super_env.arm_position.x
    env.super_env.obj_position.y = env.super_env.arm_position.y
    env.super_env.obj_position.z = env.super_env.arm_position.z
    # relative_destination = UnitVector(Cartesian(rand(0.0..10.0), rand(0.0..10.0),rand(0.0..10.0))) * 10.0
    env.destination.x = rand(env.super_env.rng, 0.0..30.0)#env.super_env.arm_position.x + relative_destination.x
    env.destination.y = rand(env.super_env.rng, 0.0..30.0)#env.super_env.arm_position.y + relative_destination.y
    env.destination.z = rand(env.super_env.rng, 0.0..30.0)#env.super_env.arm_position.z + relative_destination.z
    env.t = 0
end
function (env::FetchedMDP)(action)
    env.super_env(vcat(action, action)) # action we apply changes position of both arm and object since they are attached
    env.super_env.obj_position.x = clamp(env.super_env.obj_position.x, 0.0, 30.0)
    env.super_env.obj_position.y = clamp(env.super_env.obj_position.y, 0.0, 30.0)
    env.super_env.obj_position.z = clamp(env.super_env.obj_position.z, 0.0, 30.0)
    env.super_env.arm_position.x = clamp(env.super_env.arm_position.x, 0.0, 30.0)
    env.super_env.arm_position.y = clamp(env.super_env.arm_position.y, 0.0, 30.0)
    env.super_env.arm_position.z = clamp(env.super_env.arm_position.z, 0.0, 30.0)
    env.t += 1
    env.last_action = Cartesian(action[1], action[2], action[3])
end
# this is how we specify this environment is different. it has an end condition
function RLBase.is_terminated(env::FetchedMDP)
    #if  CartesianDistance(env.destination, env.super_env.arm_position) < 1.0 # || env.t > 200
    #    println("Distance")
    #end
    return CartesianDistance(env.destination, env.super_env.arm_position) < 1.0 || env.t > 200
end

function GR.plot(env::FetchedMDP)
    
    # render the mode
    text(0.01, 0.95, "Fetched MDP")
    if RLBase.is_terminated(env)
        text(0.01, 0.90, "Task completed")
    end

    # render the arm and object
    render_circle(1.0, env.super_env.arm_position.x, env.super_env.arm_position.y,  env.super_env.arm_position.z, 7, "Arm + Object")
    render_circle(1.0, env.destination.x, env.destination.y,  env.destination.z, 3, "Destination")

    # do the normal rendering
    GR.plot(env.super_env)


end