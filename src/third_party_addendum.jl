function rotate{N, T}(x::Mat{3, N, T}, q::Quaternion{T})
    return Mat(rotationmatrix(q)) * x
end

function rotate{T}(x::Vec{3, T}, q::Quaternion{T})
    qret = q * Quaternion(0, x[1], x[2], x[3]) * inv(q)
    return Vec(qret.v1, qret.v2, qret.v3)
end

function isapprox_tol{FSA <: FixedArray, A <: Union{Array, FixedArray}}(a::FSA, b::A; atol::Real = 0)
    for i=1:length(a)
        !isapprox(a[i], b[i]; atol = atol) && return false
    end
    true
end

angle_axis_proper(q::Quaternion) = angle_proper(q), axis_proper(q)

angle_proper(q::Quaternion) = 2 * acos(real(Quaternions.normalize(q)))

function axis_proper(q::Quaternion)
    q = Quaternions.normalize(q)
    s = sin(angle(q) / 2)
        abs(s) > 0 ?
        [q.v1, q.v2, q.v3] / s :
        [1.0, 0.0, 0.0]
end

function rotationmatrix_normalized_fsa{T}(q::Quaternion{T})
    sx, sy, sz = 2q.s*q.v1, 2q.s*q.v2, 2q.s*q.v3
    xx, xy, xz = 2q.v1^2, 2q.v1*q.v2, 2q.v1*q.v3
    yy, yz, zz = 2q.v2^2, 2q.v2*q.v3, 2q.v3^2
    return Mat{3, 3, T}((1-(yy+zz), xy+sz, xz-sy), (xy-sz, 1-(xx+zz), yz+sx), (xz+sy, yz-sx, 1-(xx+yy)))
end
