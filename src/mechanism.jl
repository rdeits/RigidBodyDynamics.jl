type Mechanism{T<:Real}
    toposortedTree::Vector{TreeVertex{RigidBody{T}, Joint}}
    bodyFixedFrameDefinitions::OrderedDict{RigidBody{T}, Set{Transform3D{T}}}
    bodyFixedFrameToBody::OrderedDict{CartesianFrame3D, RigidBody{T}}
    jointToJointTransforms::Dict{Joint, Transform3D{T}}
    gravity::Vec{3, T}

    function Mechanism(rootname::ASCIIString; gravity::Vec{3, T} = Vec(zero(T), zero(T), T(-9.81)))
        rootBody = RigidBody{T}(rootname)
        tree = Tree{RigidBody{T}, Joint}(rootBody)
        bodyFixedFrameDefinitions = OrderedDict{RigidBody{T}, Set{Transform3D{T}}}(rootBody => Set([Transform3D(T, rootBody.frame)]))
        bodyFixedFrameToBody = OrderedDict{CartesianFrame3D, RigidBody{T}}(rootBody.frame => rootBody)
        jointToJointTransforms = Dict{Joint, Transform3D{T}}()
        new(toposort(tree), bodyFixedFrameDefinitions, bodyFixedFrameToBody, jointToJointTransforms, gravity)
    end
end
root_vertex(m::Mechanism) = m.toposortedTree[1]
tree(m::Mechanism) = m.toposortedTree[1]
root_body(m::Mechanism) = root_vertex(m).vertexData
root_frame(m::Mechanism) = root_body(m).frame
path(m::Mechanism, from::RigidBody, to::RigidBody) = path(findfirst(tree(m), from), findfirst(tree(m), to))
show(io::IO, m::Mechanism) = print(io, m.toposortedTree[1])
is_fixed_to_body{M}(m::Mechanism{M}, frame::CartesianFrame3D, body::RigidBody{M}) = body.frame == frame || any((t) -> t.from == frame, bodyFixedFrameDefinitions[body])
isinertial(m::Mechanism, frame::CartesianFrame3D) = is_fixed_to_body(m, frame, root_body(m))
isroot{T}(m::Mechanism{T}, b::RigidBody{T}) = b == root_body(m)

function add_body_fixed_frame!{T}(m::Mechanism{T}, body::RigidBody{T}, transform::Transform3D{T})
    fixedFrameDefinitions = m.bodyFixedFrameDefinitions[body]
    any((t) -> t.from == transform.from, fixedFrameDefinitions) && error("frame was already defined")
    bodyVertex = findfirst(tree(m), body)
    default_frame = isroot(bodyVertex) ? body.frame : bodyVertex.edgeToParentData.frameAfter
    if transform.to != default_frame
        found = false
        for t in fixedFrameDefinitions
            if t.from == transform.to
                found = true
                transform = t * transform
                break
            end
        end
        !found && error("failed to add frame because transform doesn't connect to any known transforms")
    end
    push!(fixedFrameDefinitions, transform)
    m.bodyFixedFrameToBody[transform.from] = body
    return transform
end

function attach!{T}(m::Mechanism{T}, parentBody::RigidBody{T}, joint::Joint, jointToParent::Transform3D{T}, childBody::RigidBody{T}, childToJoint::Transform3D{T} = Transform3D{T}(childBody.frame, joint.frameAfter))
    insert!(tree(m), childBody, joint, parentBody)
    m.jointToJointTransforms[joint] = add_body_fixed_frame!(m, parentBody, jointToParent)
    @assert childToJoint.from == childBody.frame
    @assert childToJoint.to == joint.frameAfter
    m.bodyFixedFrameDefinitions[childBody] = Set([Transform3D(T, joint.frameAfter)])
    m.bodyFixedFrameToBody[joint.frameAfter] = childBody
    if childToJoint.from != childToJoint.to
        push!(m.bodyFixedFrameDefinitions[childBody], childToJoint)
        m.bodyFixedFrameToBody[childToJoint.from] = childBody
    end
    m.toposortedTree = toposort(tree(m))
    return m
end

joints(m::Mechanism) = keys(m.jointToJointTransforms) # note: unsorted
bodies(m::Mechanism) = keys(m.bodyFixedFrameDefinitions)
default_frame(m::Mechanism, body::RigidBody) = first(m.bodyFixedFrameDefinitions[body]).to # allows standardization on a frame to reduce number of transformations required

num_positions(m::Mechanism) = num_positions(joints(m))
num_velocities(m::Mechanism) = num_velocities(joints(m))

function rand_mechanism{T}(::Type{T}, parentSelector::Function, jointTypes...)
    m = Mechanism{T}("world")
    parentBody = root_body(m)
    for i = 1 : length(jointTypes)
        @assert jointTypes[i] <: JointType
        joint = Joint("joint$i", rand(jointTypes[i]))
        jointToParentBody = rand(Transform3D{T}, joint.frameBefore, parentBody.frame)
        body = RigidBody(rand(SpatialInertia{T}, CartesianFrame3D("body$i")))
        bodyToJoint = Transform3D{Float64}(body.frame, joint.frameAfter) #rand(Transform3D{Float64}, body.frame, joint.frameAfter)
        attach!(m, parentBody, joint, jointToParentBody, body, bodyToJoint)
        parentBody = parentSelector(m)
    end
    return m
end

rand_chain_mechanism{T}(t::Type{T}, jointTypes...) = rand_mechanism(t, (m::Mechanism{T}) -> m.toposortedTree[end].vertexData, jointTypes...)
rand_tree_mechanism{T}(t::Type{T}, jointTypes...) = rand_mechanism(t, (m::Mechanism{T}) -> rand(collect(bodies(m))), jointTypes...)

function configuration_derivative_to_velocity{Q, V}(q::OrderedDict{Joint, Vector{Q}}, q̇::OrderedDict{Joint, Vector{V}})
    T = promote_type(Q, V)
    return OrderedDict([j::Joint => configuration_derivative_to_velocity(j, q[j], q̇[j])::Vector{T} for j in keys(q)])
end

function velocity_to_configuration_derivative{Q, V}(q::OrderedDict{Joint, Vector{Q}}, v::OrderedDict{Joint, Vector{V}})
    T = promote_type(Q, V)
    return OrderedDict([j::Joint => velocity_to_configuration_derivative(j, q[j], v[j])::Vector{T} for j in keys(q)])
end
