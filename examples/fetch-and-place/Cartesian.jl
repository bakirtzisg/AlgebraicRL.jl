export Cartesian, CartesianDistance


# Represents a Cartesian XYZ point. Has some basic convenience functions.
mutable struct Cartesian
    x
    y
    z
end


function CartesianDistance(pos1::Cartesian, pos2::Cartesian)
    return sqrt((pos1.x-pos2.x)^2 + (pos1.y-pos2.y)^2 + (pos1.z-pos2.z)^2)
end

function Magnitude(vec::Cartesian)
    return CartesianDistance(vec, Cartesian(0,0,0))
end

function UnitVector(vec::Cartesian)
    magnitude = Magnitude(vec) + eps()
    return Cartesian(vec.x/magnitude, vec.y/magnitude, vec.z/magnitude)
end

function DotProduct(vec1::Cartesian, vec2::Cartesian)
    return vec1.x * vec2.x + vec1.y * vec2.y + vec1.z * vec2.z
end

Base.:+(vec1::Cartesian, vec2::Cartesian) = Cartesian(vec1.x + vec2.x, vec1.y + vec2.y, vec1.z + vec2.z)
Base.:-(vec1::Cartesian, vec2::Cartesian) = Cartesian(vec1.x - vec2.x, vec1.y - vec2.y, vec1.z - vec2.z)
Base.:*(vec1::Cartesian, m) = Cartesian(vec1.x * m, vec1.y * m, vec1.z * m)
Base.:(==)(vec1::Cartesian, vec2::Cartesian) =    abs(vec1.x - vec2.x) < 0.00001 && 
                                                abs(vec1.y - vec2.y) < 0.00001 && 
                                                abs(vec1.z - vec2.z) < 0.00001