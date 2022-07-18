export  FetchAndPlaceMDP, render

# defines a simulation for a robot picking up an object. In this very simple simulation, we only know about the arm's x,y,z position and 
# the object's x,y,z position. The state space consists of those values. The action spaces consists of those same values, but both the arm and the object 
# can only move up to 1 unit in each direction at a time

mutable struct FetchAndPlaceMDP <: AbstractEnv
    arm_position::Cartesian
    obj_position::Cartesian

    rng::AbstractRNG
end

RLBase.action_space(env::FetchAndPlaceMDP) = Space(
    ClosedInterval{Float64}[
        (-1.0)..(1.0),
        (-1.0)..(1.0),
        (-1.0)..(1.0),
        (-1.0)..(1.0),
        (-1.0)..(1.0),
        (-1.0)..(1.0),
    ],
)
RLBase.state(env::FetchAndPlaceMDP) = [env.arm_position.x, env.arm_position.y, env.arm_position.z, env.obj_position.x, env.obj_position.y, env.obj_position.z]
RLBase.state_space(env::FetchAndPlaceMDP) = Space(
    ClosedInterval{Float64}[
        (0)..(30),
        (0)..(30),
        (0)..(30),
        (0)..(30),
        (0)..(30),
        (0)..(30),
    ],
)
RLBase.reward(env::FetchAndPlaceMDP) = 0
RLBase.is_terminated(env::FetchAndPlaceMDP) = false
RLBase.reset!(env::FetchAndPlaceMDP) = 0 # does nothing, no need in simulation
function (env::FetchAndPlaceMDP)(action)
    @assert action in RLBase.action_space(env)
    env.arm_position.x = clamp(env.arm_position.x + action[1], 0.0, 30.0)
    env.arm_position.y = clamp(env.arm_position.y + action[2], 0.0, 30.0)
    env.arm_position.z = clamp(env.arm_position.z + action[3], 0.0, 30.0)
    env.obj_position.x = clamp(env.obj_position.x + action[4], 0.0, 30.0)
    env.obj_position.y = clamp(env.obj_position.y + action[5], 0.0, 30.0)
    env.obj_position.z = clamp(env.obj_position.z + action[6], 0.0, 30.0)

end


rotate(xs, ys, θ) = xs*cos(θ) - ys*sin(θ), ys*cos(θ) + xs*sin(θ)
translate(xs, ys, t) = xs .+ t[1], ys .+ t[2]
function GR.plot(env::FetchAndPlaceMDP)
    
    # makes window
    setviewport(0, 1, 0, 1)
    setwindow(  0.0, 30.0, 
                0.0, 30.0)
    
    # update window, display, sleep, reset
    updatews()
    # savefig("/tmp/render.gif") # for some reason this automatically opens the window????????
    # GR.show()
    sleep(0.1)
    clearws()


end


# 1 = black, 2 = red, 3 = green, 4 = blue, 5 = teal, 6 = yellow, 7 = purple, 8-10 blues
function render_circle(radius, x, y, z, color::Integer, txt)
        # make circle
        xs = radius .* cos.(LinRange(0, 2pi, 100))
        ys = radius .* sin.(LinRange(0, 2pi, 100))
        xs, ys = translate(xs, ys, [x, y])
        setfillintstyle(1)
        setfillcolorind(color) 
        fillarea(xs, ys)

        # make text
        str = "x=$(@sprintf("%.2f", x)), y=$(@sprintf("%.2f", y)), z=$(@sprintf("%.2f", z))"
        setcharheight(0.03)
        text((x + radius)/30.0, (y+radius/2)/30.0, txt)
        text((x + radius)/30.0, (y-radius/2)/30.0, str)
end    

function render_line(min_x, min_y, max_x, max_y)
    # makes line
    xs = LinRange(min_x, max_x, 100)
    ys = LinRange(min_y, max_y, 100)
    polyline(xs, ys)
end

function render_polygon(xs, ys, offset_x, offset_y, color)
    # make box
    # xs = [-0.1, -0.1, 0.1, 0.1]
    # ys = [0, 0.1, 0.1, 0]
    xs, ys = translate(xs, ys, [offset_x, offset_y])
    setfillintstyle(0) # just boundrary
    setfillcolorind(color) 
    fillarea(xs, ys)
end