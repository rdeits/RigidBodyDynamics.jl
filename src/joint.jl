abstract JointType

immutable Joint
    name::ASCIIString
    frameBefore::CartesianFrame3D
    frameAfter::CartesianFrame3D
    jointType::JointType

    Joint(name::ASCIIString, jointType::JointType) = new(name, CartesianFrame3D(string("before_", name)), CartesianFrame3D(string("after_", name)), jointType)
end
show(io::IO, joint::Joint) = print(io, "Joint \"$(joint.name)\": $(joint.jointType)")
showcompact(io::IO, joint::Joint) = print(io, "$(joint.name)")

immutable QuaternionFloating <: JointType
    motionSubspace::Array{Float64, 2}
    function QuaternionFloating()
        new(eye(6))
    end
end
show(io::IO, jt::QuaternionFloating) = print(io, "Quaternion floating joint")
rand(::Type{QuaternionFloating}) = QuaternionFloating()

function joint_transform{T<:Real}(j::Joint, q::Vector{T}, jt::QuaternionFloating = j.jointType)
    rot = Quaternion(q[1], q[2 : 4])
    Quaternions.normalize(rot)
    trans = Vec(q[5], q[6], q[7])
    return Transform3D{T}(j.frameAfter, j.frameBefore, rot, trans)
end

function motion_subspace{T<:Real}(j::Joint, q::Vector{T}, jt::QuaternionFloating = j.jointType)
    return GeometricJacobian(j.frameAfter, j.frameBefore, j.frameAfter, copy(jt.motionSubspace))
end

num_positions(j::Joint, jt::QuaternionFloating = j.jointType) = 7::Int64
num_velocities(j::Joint, jt::QuaternionFloating = j.jointType) = 6::Int64
has_fixed_motion_subspace(j::Joint, jt::QuaternionFloating = j.jointType) = true
bias_acceleration{T<:Real}(j::Joint, q::Vector{T}, v::Vector{T}, jt::QuaternionFloating = j.jointType) = zero(SpatialAcceleration{T}, j.frameAfter, j.frameBefore, j.frameAfter)

function configuration_derivative_to_velocity(j::Joint, q::Vector, q̇::Vector, jt::QuaternionFloating = j.jointType)
    quat = Quaternion(q[1], q[2 : 4])
    Quaternions.normalize(quat)
    quatdot = Quaternion(q̇[1], q̇[2 : 4])
    posdot = Vec(q̇[5], q̇[6], q̇[7])
    linear = rotate(posdot, inv(quat))
    angularQuat = 2 * inv(quat) * quatdot
    return [angularQuat.v1; angularQuat.v2; angularQuat.v3; linear...]
end

function velocity_to_configuration_derivative(j::Joint, q::Vector, v::Vector, jt::QuaternionFloating = j.jointType)
    quat = Quaternion(q[1], q[2 : 4])
    Quaternions.normalize(quat)
    ωQuat = Quaternion(0, v[1], v[2], v[3])
    linear = Vec(v[4], v[5], v[6])
    quatdot = 1/2 * quat * ωQuat
    posdot = rotate(linear, quat)
    return [quatdot.s; quatdot.v1; quatdot.v2; quatdot.v3; posdot...]
end

function zero_configuration{T<:Real}(j::Joint, ::Type{T}, jt::QuaternionFloating = j.jointType)
    return [one(T); zeros(T, 6)]
end
function rand_configuration{T<:Real}(j::Joint, ::Type{T}, jt::QuaternionFloating = j.jointType)
    quat = nquatrand() # TODO: only works when T == Float64
    return [quat.s; quat.v1; quat.v2; quat.v3; rand(T, 3)]
end

function joint_twist{T<:Real}(j::Joint, q::Vector{T}, v::Vector{T}, jt::QuaternionFloating = j.jointType)
    return Twist(j.frameAfter, j.frameBefore, j.frameAfter, Vec(v[1 : 3]), Vec(v[4 : 6]))
end

abstract OneDegreeOfFreedomFixedAxis <: JointType

immutable Prismatic{T<:Real} <: OneDegreeOfFreedomFixedAxis
    translation_axis::Vec{3, T}
    motionSubspace::Vector{Float64}
    Prismatic(translation_axis::Vec{3, T}) = new(translation_axis, [zeros(3); Array(translation_axis)])
end
Prismatic{T}(rotation_axis::Vec{3, T}) = Prismatic{T}(rotation_axis)
show(io::IO, jt::Prismatic) = print(io, "Prismatic joint with axis $(jt.translation_axis)")
rand{T}(::Type{Prismatic{T}}) = Prismatic(FixedSizeArrays.normalize(rand(Vec{3, T})))

joint_transform{T1<:Real, T2}(j::Joint, q::Vector{T1}, jt::Prismatic{T2} = j.jointType) = Transform3D(j.frameAfter, j.frameBefore, q[1] * jt.translation_axis)

function joint_twist{T<:Real}(j::Joint, q::Vector{T}, v::Vector{T}, jt::Prismatic = j.jointType)
    return Twist(j.frameAfter, j.frameBefore, j.frameAfter, zero(Vec{3, T}), jt.translation_axis * v[1])
end

function motion_subspace{T<:Real}(j::Joint, q::Vector{T}, jt::Prismatic = j.jointType)
    return GeometricJacobian(j.frameAfter, j.frameBefore, j.frameAfter, copy(jt.motionSubspace))
end

immutable Revolute{T<:Real} <: OneDegreeOfFreedomFixedAxis
    rotation_axis::Vec{3, T}
    motionSubspace::Vector{Float64}
    Revolute(rotation_axis::Vec{3, T}) = new(rotation_axis, [Array(rotation_axis); zeros(3)])
end
Revolute{T}(rotation_axis::Vec{3, T}) = Revolute{T}(rotation_axis)
show(io::IO, jt::Revolute) = print(io, "Revolute joint with axis $(jt.rotation_axis)")
rand{T}(::Type{Revolute{T}}) = Revolute(FixedSizeArrays.normalize(rand(Vec{3, T})))

function joint_transform{T1, T2}(j::Joint, q::Vector{T1}, jt::Revolute{T2} = j.jointType)
    T = promote_type(T1, T2)
    Transform3D(j.frameAfter, j.frameBefore, qrotation(convert(Vector{T}, Array(jt.rotation_axis)), convert(T, q[1]))) # TODO: notify Quaternions maintainer
end

function joint_twist{T<:Real}(j::Joint, q::Vector{T}, v::Vector{T}, jt::Revolute = j.jointType)
    return Twist(j.frameAfter, j.frameBefore, j.frameAfter, jt.rotation_axis * v[1], zero(Vec{3, T}))
end

function motion_subspace{T<:Real}(j::Joint, q::Vector{T}, jt::Revolute = j.jointType)
    return GeometricJacobian(j.frameAfter, j.frameBefore, j.frameAfter, copy(jt.motionSubspace))
end

num_positions(j::Joint, jt::OneDegreeOfFreedomFixedAxis = j.jointType) = 1::Int64
num_velocities(j::Joint, jt::OneDegreeOfFreedomFixedAxis = j.jointType) = 1::Int64
zero_configuration{T<:Real}(j::Joint, ::Type{T}, jt::OneDegreeOfFreedomFixedAxis = j.jointType) = [zero(T)]
rand_configuration{T<:Real}(j::Joint, ::Type{T}, jt::OneDegreeOfFreedomFixedAxis = j.jointType) = [rand(T)]
has_fixed_motion_subspace(j::Joint, jt::OneDegreeOfFreedomFixedAxis = j.jointType) = true
bias_acceleration{T<:Real}(j::Joint, q::Vector{T}, v::Vector{T}, jt::OneDegreeOfFreedomFixedAxis = j.jointType) = zero(SpatialAcceleration{T}, j.frameAfter, j.frameBefore, j.frameAfter)
configuration_derivative_to_velocity(j::Joint, q::Vector, q̇::Vector, jt::OneDegreeOfFreedomFixedAxis = j.jointType) = q̇
velocity_to_configuration_derivative(j::Joint, q::Vector, v::Vector, jt::OneDegreeOfFreedomFixedAxis = j.jointType) = v

num_positions(itr) = reduce((val, joint) -> val + num_positions(joint), 0, itr)
num_velocities(itr) = reduce((val, joint) -> val + num_velocities(joint), 0, itr)
