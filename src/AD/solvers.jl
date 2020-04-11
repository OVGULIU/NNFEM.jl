export ExplicitSolver, ExplicitSolverTime, GeneralizedAlphaSolver, GeneralizedAlphaSolverTime


@doc raw"""
    ExplicitSolverTime(Δt::Float64, NT::Int64)

Returns the times for explicit solver. Boundary conditions and external forces should be given at these times.
"""
function ExplicitSolverTime(Δt::Float64, NT::Int64)
    U = zeros(NT)
    for i = 1:NT 
        U[i] = (i-0.5)*Δt
    end
    U 
end

@doc raw"""
    ExplicitSolver(globdat::GlobalData, domain::Domain,
        d0::Union{Array{Float64, 1}, PyObject}, 
        v0::Union{Array{Float64, 1}, PyObject}, 
        a0::Union{Array{Float64, 1}, PyObject}, 
        Δt::Float64, NT::Int64, 
        H::Union{Array{Float64, 3}, Array{Float64, 2}, PyObject},
        Fext::Union{Array{Float64, 2}, PyObject, Missing}=missing,
        ubd::Union{Array{Float64, 2}, PyObject, Missing}=missing,
        abd::Union{Array{Float64, 2}, PyObject, Missing}=missing)

Differentiable Explicit Solver. 

- `d0`, `v0`, `a0`: initial **full** displacement, velocity, and acceleration. 

- `Δt`: time step 

- `Hs`: linear elasticity matrix at each Gauss point 

- `Fext`: external force, $\mathrm{NT}\times n$, where $n$ is the active dof. 

- `ubd`, `abd`: boundary displacementt and acceleration, $\mathrm{NT}\times m$, where $m$ is boundary DOF. 
"""
function ExplicitSolver(globdat::GlobalData, domain::Domain,
    d0::Union{Array{Float64, 1}, PyObject}, 
    v0::Union{Array{Float64, 1}, PyObject}, 
    a0::Union{Array{Float64, 1}, PyObject}, 
    Δt::Float64, NT::Int64, 
    H::Union{Array{Float64, 3}, Array{Float64, 2}, PyObject},
    Fext::Union{Array{Float64, 2}, PyObject, Missing}=missing,
    ubd::Union{Array{Float64, 2}, PyObject, Missing}=missing,
    abd::Union{Array{Float64, 2}, PyObject, Missing}=missing)

    init_nnfem(domain)
    M = factorize(constant(globdat.M))
    bddof = findall(domain.EBC[:] .== -2)

    Fext, ubd, abd, H = convert_to_tensor([Fext, ubd, abd, H], [Float64, Float64, Float64, Float64])

    function condition(i, tas...)
        i<=NT
    end
    function body(i, tas...)
        d_arr, v_arr, a_arr = tas
        u, ∂u, ∂∂u = read(d_arr, i), read(v_arr, i), read(a_arr, i)

        u +=  Δt*∂u + 0.5*Δt*Δt*∂∂u
        ∂u += 0.5*Δt * ∂∂u

        if !ismissing(abd)
            u = scatter_update(u, bddof, ubd[i])
        end

        ε = s_eval_strain_on_gauss_points(u, domain)
        if length(size(H))==2
            σ = tf.matmul(ε, H)
        else
            σ = batch_matmul(H, ε)
        end 
        fint  = s_compute_internal_force_term(σ, domain)
        if ismissing(Fext)
            fext = zeros(length(fint))
        else
            fext = Fext[i]
        end
        ∂∂up = vector(findall(domain.dof_to_eq), M\(fext - fint), domain.nnodes*2)
        
        if !ismissing(abd)
            ∂∂up = scatter_update(∂∂up, bddof, abd[i])
        end

        ∂u += 0.5 * Δt * ∂∂up

        i+1, write(d_arr, i+1, u), write(v_arr, i+1, ∂u), write(a_arr, i+1, ∂∂u)
    end

    arr_d = TensorArray(NT+1); arr_d = write(arr_d, 1, d0)
    arr_v = TensorArray(NT+1); arr_v = write(arr_v, 1, v0)
    arr_a = TensorArray(NT+1); arr_a = write(arr_a, 1, a0)
    i = constant(1, dtype=Int32)
    tas = [arr_d, arr_v, arr_a]
    _, d, v, a = while_loop(condition, body, [i, tas...])
    d, v, a = stack(d), stack(v), stack(a)
    sp = (NT+1, 2domain.nnodes)
    set_shape(d, sp), set_shape(v, sp), set_shape(a, sp)
end


@doc raw"""
    GeneralizedAlphaSolverTime(Δt::Float64, NT::Int64;ρ::Float64 = 0.0)

Returns the times for the generalized $\alpha$ solver. Boundary conditions and external forces should be given at these times.
"""
function GeneralizedAlphaSolverTime(Δt::Float64, NT::Int64;ρ::Float64 = 0.0)
    U = zeros(NT)
    @assert 0<=ρ<=1
    αm = (2ρ-1)/(1+ρ)
    αf = ρ/(1+ρ)    
    β2 = 0.5*(1 - αm + αf)^2
    γ = 0.5 - αm + αf
    t = 0
    for i = 1:NT 
        t += (1 - αf)*Δt 
        U[i] = t
    end
    U 
end


@doc raw"""
    GeneralizedAlphaSolver(globdat::GlobalData, domain::Domain,
        d0::Union{Array{Float64, 1}, PyObject}, 
        v0::Union{Array{Float64, 1}, PyObject}, 
        a0::Union{Array{Float64, 1}, PyObject}, 
        Δt::Float64, NT::Int64, 
        Hs::Union{Array{Float64, 3}, Array{Float64, 2}, PyObject},
        Fext::Union{Array{Float64, 2}, PyObject, Missing}=missing,
        ubd::Union{Array{Float64, 2}, PyObject, Missing}=missing,
        abd::Union{Array{Float64, 2}, PyObject, Missing}=missing; ρ::Float64 = 0.0)

Differentiable Generalized $\alpha$ scheme. This is an extension of [`αscheme`](https://kailaix.github.io/ADCME.jl/dev/alphascheme/)
provided in ADCME. This function does not support damping and variable time step (for efficiency). 

- `d0`, `v0`, `a0`: initial **full** displacement, velocity, and acceleration. 

- `Δt`: time step 

- `Hs`: linear elasticity matrix at each Gauss point 

- `Fext`: external force, $\mathrm{NT}\times n$, where $n$ is the active dof. 

- `ubd`, `abd`: boundary displacementt and acceleration, $\mathrm{NT}\times m$, where $m$ is boundary DOF. 
"""
function GeneralizedAlphaSolver(globdat::GlobalData, domain::Domain,
    d0::Union{Array{Float64, 1}, PyObject}, 
    v0::Union{Array{Float64, 1}, PyObject}, 
    a0::Union{Array{Float64, 1}, PyObject}, 
    Δt::Float64, NT::Int64, 
    Hs::Union{Array{Float64, 3}, Array{Float64, 2}, PyObject},
    Fext::Union{Array{Float64, 2}, PyObject, Missing}=missing,
    ubd::Union{Array{Float64, 2}, PyObject, Missing}=missing,
    abd::Union{Array{Float64, 2}, PyObject, Missing}=missing; ρ::Float64 = 0.0)
    @assert 0<=ρ<=1
    αm = (2ρ-1)/(1+ρ)
    αf = ρ/(1+ρ)    
    β2 = 0.5*(1 - αm + αf)^2
    γ = 0.5 - αm + αf

    Fext, ubd, abd, Hs = convert_to_tensor([Fext, ubd, abd, Hs], [Float64, Float64, Float64, Float64])
    M = constant(globdat.M)
    stiff = s_compute_stiffness_matrix(Hs, domain)
    A = M*(1 - αm) + (1 - αf) * 0.5 * β2 * Δt^2 * stiff
    A = factorize(A)
    bddof = findall(domain.EBC[:] .== -2)
    nbddof = findall(domain.dof_to_eq)

    function condition(i, tas...)
        i<=NT
    end
    function body(i, tas...)
        d_arr, v_arr, a_arr = tas 
        u, ∂u, ∂∂u = read(d_arr, i), read(v_arr, i), read(a_arr, i)
        if ismissing(Fext)
            fext = zeros(length(fint))
        else
            fext = Fext[i]
        end
        ∂∂up = ∂∂u
        up =  (1 - αf)*(u + Δt*∂u + 0.5 * Δt * Δt * ((1 - β2)*∂∂u + β2*∂∂up)) + αf*u
        if !ismissing(abd)
            up = scatter_update(up, bddof, ubd[i])
        end
        ε = s_eval_strain_on_gauss_points(up, domain)
        if length(size(Hs))==2
            σ = tf.matmul(ε, Hs)
        else
            # @info Hs, ε
            σ = batch_matmul(Hs, ε)
        end 
        fint  = s_compute_internal_force_term(σ, domain)
        if ismissing(Fext)
            fext = zeros(length(fint))
        else
            fext = Fext[i]
        end
        res = M * (∂∂up[nbddof] *(1 - αm) + αm*∂∂u[nbddof])  + fint - fext
        Δ = -(A\res)
        ∂∂up= scatter_add(∂∂up, nbddof, Δ)
        if !ismissing(abd)
            ∂∂up = scatter_update(∂∂up, bddof, abd[i])
        end

        # updaet 
        u += Δt * ∂u + Δt^2/2 * ((1 - β2) * ∂∂u + β2 * ∂∂up)
        ∂u += Δt * ((1 - γ) * ∂∂u + γ * ∂∂up)

        i+1, write(d_arr, i+1, u), write(v_arr, i+1, ∂u), write(a_arr, i+1, ∂∂up)
    end

    arr_d = TensorArray(NT+1); arr_d = write(arr_d, 1, d0)
    arr_v = TensorArray(NT+1); arr_v = write(arr_v, 1, v0)
    arr_a = TensorArray(NT+1); arr_a = write(arr_a, 1, a0)
    i = constant(1, dtype=Int32)
    tas = [arr_d, arr_v, arr_a]
    _, d, v, a = while_loop(condition, body, [i, tas...])
    d, v, a = stack(d), stack(v), stack(a)
    sp = (NT+1, 2domain.nnodes)
    set_shape(d, sp), set_shape(v, sp), set_shape(a, sp)
end


############################# NN based constitutive models #############################


@doc raw"""
    ExplicitSolver(globdat::GlobalData, domain::Domain,
        d0::Union{Array{Float64, 1}, PyObject}, 
        v0::Union{Array{Float64, 1}, PyObject}, 
        a0::Union{Array{Float64, 1}, PyObject}, 
        Δt::Float64, NT::Int64, 
        nn::Function,
        Fext::Union{Array{Float64, 2}, PyObject, Missing}=missing,
        ubd::Union{Array{Float64, 2}, PyObject, Missing}=missing,
        abd::Union{Array{Float64, 2}, PyObject, Missing}=missing)

Similar to [`ExplicitSolver`](@ref); however, the constituve relation from $\epsilon$ to $\sigma$ must be provided by 
the function `nn`.
"""
function ExplicitSolver(globdat::GlobalData, domain::Domain,
    d0::Union{Array{Float64, 1}, PyObject}, 
    v0::Union{Array{Float64, 1}, PyObject}, 
    a0::Union{Array{Float64, 1}, PyObject}, 
    Δt::Float64, NT::Int64, 
    nn::Function,
    Fext::Union{Array{Float64, 2}, PyObject, Missing}=missing,
    ubd::Union{Array{Float64, 2}, PyObject, Missing}=missing,
    abd::Union{Array{Float64, 2}, PyObject, Missing}=missing)

    init_nnfem(domain)
    M = factorize(constant(globdat.M))
    bddof = findall(domain.EBC[:] .== -2)

    Fext, ubd, abd = convert_to_tensor([Fext, ubd, abd], [Float64, Float64, Float64])

    function condition(i, tas...)
        i<=NT
    end
    function body(i, tas...)
        d_arr, v_arr, a_arr = tas
        u, ∂u, ∂∂u = read(d_arr, i), read(v_arr, i), read(a_arr, i)

        u +=  Δt*∂u + 0.5*Δt*Δt*∂∂u
        ∂u += 0.5*Δt * ∂∂u

        if !ismissing(abd)
            u = scatter_update(u, bddof, ubd[i])
        end

        ε = s_eval_strain_on_gauss_points(u, domain)
        σ = nn(ε)
        fint  = s_compute_internal_force_term(σ, domain)
        if ismissing(Fext)
            fext = zeros(length(fint))
        else
            fext = Fext[i]
        end
        ∂∂up = vector(findall(domain.dof_to_eq), M\(fext - fint), domain.nnodes*2)
        
        if !ismissing(abd)
            ∂∂up = scatter_update(∂∂up, bddof, abd[i])
        end

        ∂u += 0.5 * Δt * ∂∂up

        i+1, write(d_arr, i+1, u), write(v_arr, i+1, ∂u), write(a_arr, i+1, ∂∂u)
    end

    arr_d = TensorArray(NT+1); arr_d = write(arr_d, 1, d0)
    arr_v = TensorArray(NT+1); arr_v = write(arr_v, 1, v0)
    arr_a = TensorArray(NT+1); arr_a = write(arr_a, 1, a0)
    i = constant(1, dtype=Int32)
    tas = [arr_d, arr_v, arr_a]
    _, d, v, a = while_loop(condition, body, [i, tas...])
    d, v, a = stack(d), stack(v), stack(a)
    sp = (NT+1, 2domain.nnodes)
    set_shape(d, sp), set_shape(v, sp), set_shape(a, sp)
end