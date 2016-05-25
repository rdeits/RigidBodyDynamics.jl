function rotate{N, T}(x::Mat{3, N, T}, q::Quaternion{T})
    return Mat(rotationmatrix(q)) * x
end

function rotate{T1, T2}(x::Vec{3, T1}, q::Quaternion{T2})
    qret = q * Quaternion(0, x[1], x[2], x[3]) * inv(q)
    return Vec{3, promote_type(T1, T2)}(qret.v1, qret.v2, qret.v3)
end

function isapprox_tol{FSA <: FixedArray, A <: Union{Array, FixedArray}}(a::FSA, b::A; atol::Real = 0)
    for i=1:length(a)
        !isapprox(a[i], b[i]; atol = atol) && return false
    end
    true
end
