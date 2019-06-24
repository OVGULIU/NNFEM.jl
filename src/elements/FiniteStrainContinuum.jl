export FiniteStrainContinuum
mutable struct FiniteStrainContinuum
    mat  # constitutive law
    elnodes::Array{Int64}   # the node indices in this finite element
    props::Dict{String, Any}
    coords::Array{Float64}
    dhdx::Array{Array{Float64}}  # 4nPointsx2 matrix
    weights::Array{Float64} 
    hs::Array{Array{Float64}}
end

function FiniteStrainContinuum(coords::Array{Float64}, elnodes::Array{Int64}, props::Dict{String, Any})
    name = props["name"]
    if name=="PlaneStrain"
        mat = PlaneStrain(props)
    else
        error("Not implemented yet: $name")
    end
    dhdx, weights, hs = getElemShapeData( coords, 2 )
    FiniteStrainContinuum(mat, elnodes, props, coords, dhdx, weights, hs)
end

function getTangentStiffness(self::FiniteStrainContinuum, state::Array{Float64}, Dstate::Array{Float64})
    ndofs = dofCount(self); 
    nnodes = length(self.elnodes)
    stiff = zeros(ndofs,ndofs)
    out = Array{Float64}[]
    u = state[1:nnodes]; v = state[nnodes:2*nnodes]
    for k = 1:length(self.weights)
        g1 = self.dhdx[k][:,1]; g2 = self.dhdx[k][:,2]
        ux = u'*g1; uy = u'*g2; vx = v'*g1; vy = v'*g2 
        ∂E∂u = [ux*g1 uy*g2 g2*ux+g1*uy;
                vx*g1 vy*g2 g1*vy+g2*vx;] # 8x3
        F = [u';v']*self.dhdx[k]; 
        E = 0.5*(F'*F-UniformScaling(1.0))
        ε = [E[1,1];E[2,2];2E[1,2]]
        σ, dσ_dε = getStress(self.mat,ε)
        σ∂∂E∂∂u = [g1'*g1*σ[1] +  g2'*g2*σ[2]  + g1'*g2*σ[3] + g2'*g1*σ[3]; zeros(nnodes, nnodes)
                  zeros(nnodes, nnodes); g1'*g1*σ[1] +  g2'*g2*σ[2]  + g1'*g2*σ[3] + g2'*g1*σ[3]]
        stiff += (∂E∂u * dσ_dε * ∂E∂u' + σ∂∂E∂∂u)*self.weights[k] # 1x8
    end
    return stiff
end

function getInternalForce(self::FiniteStrainContinuum, state::Array{Float64}, Dstate::Array{Float64})
    n = dofCount(self)
    fint = zeros(n)
    out = Array{Float64}[]
    u = state[1:4]; v = state[5:8]
    for k = 1:length(self.weights)
        g1 = self.dhdx[k][:,1]; g2 = self.dhdx[k][:,2]
        ux = u'*g1; uy = u'*g2; vx = v'*g1; vy = v'*g2 
        ∂E∂u = [ux*g1 uy*g2 g2*ux+g1*uy;
                vx*g1 vy*g2 g1*vy+g2*vx;] # 8x3
        F = [u';v']*self.dhdx[k]; E = 0.5*(F'*F-UniformScaling(1.0))
        ε = [E[1,1];E[2,2];2E[1,2]]
        σ,_ = getStress(self.mat,ε)
        fint += ∂E∂u * σ * self.weights[k] # 1x8
    end
    return fint
end

function getMassMatrix(self::FiniteStrainContinuum)
    n = dofCount(self)
    rho = self.mat.ρ
    mass = zeros(n,n)
    for k = 1:length(self.weights)
        N = zeros(2, 2length(self.hs[k]))
        for (i,a) in enumerate(self.hs[k])
            N[1,2(i-1)+1] = a; N[2,2i] = a
        end
        mass += N' * N  * rho * self.weights[k]
    end
    lumped = sum(mass, dims=2)

    return mass, lumped
end


function getNodes(self::FiniteStrainContinuum)
    return self.elnodes
end

function dofCount(self::FiniteStrainContinuum)
    return 2length(self.elnodes)
end

