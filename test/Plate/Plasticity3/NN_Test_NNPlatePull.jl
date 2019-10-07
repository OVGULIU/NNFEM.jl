stress_scale = 1.0e+5
strain_scale = 1

# tid = parse(Int64, ARGS[1])
force_scale = 5.0
tid = 200
# if Sys.MACHINE=="x86_64-pc-linux-gnu"
#    global tid = parse(Int64, ARGS[1])
#    global force_scale = parse(Float64, ARGS[2])
# end
printstyled("tid=$tid\n", color=:green)

include("CommonFuncs.jl")

testtype = "NeuralNetwork2D"
nntype = "piecewise"
include("../Plasticity2/nnutil.jl")


H0 = [1.04167e6  2.08333e5  0.0      
      2.08333e5  1.04167e6  0.0      
      0.0        0.0        4.16667e5]/stress_scale

#s = ae_to_code("Data/order2/learned_nn_5.0_1.mat", "piecewise")
s = ae_to_code("Data/nn_train0_1.mat", "piecewise")

eval(Meta.parse(s))
# density 4.5*(1 - 0.25) + 3.2*0.25
#fiber_fraction = 0.25
#todo
prop = Dict("name"=> testtype, "rho"=> 4.5, "nn"=>post_nn)

T = 0.1
NT = 200

# nx_f, ny_f = 12, 4
# homogenized computaional domain
# number of elements in each directions
nx, ny = 10, 5

porder = 2

nodes, EBC, g, gt, FBC, fext, ft = BoundaryCondition(tid, nx, ny,porder)

ndofs=2
elements = []
for j = 1:ny
    for i = 1:nx 
        n = (nx*porder+1)*(j-1)*porder + (i-1)porder+1
        #element (i,j)
        if porder == 1
            #   4 ---- 3
            #
            #   1 ---- 2

            elnodes = [n, n + 1, n + 1 + (nx + 1), n + (nx + 1)]
        elseif porder == 2
            #   4 --7-- 3
            #   8   9   6 
            #   1 --5-- 2
            elnodes = [n, n + 2, n + 2 + 2*(2*nx+1),  n + 2*(2*nx+1), n+1, n + 2 + (2*nx+1), n + 1 + 2*(2*nx+1), n + (2*nx+1), n+1+(2*nx+1)]
        else
            error("polynomial order error, porder= ", porder)
        end
        coords = nodes[elnodes,:]
        push!(elements,SmallStrainContinuum(coords,elnodes, prop, 3))
    end
end



domain = Domain(nodes, elements, ndofs, EBC, g, FBC, fext)
state = zeros(domain.neqs)
∂u = zeros(domain.neqs)
globdat = GlobalData(state,zeros(domain.neqs)
, zeros(domain.neqs),∂u, domain.neqs, gt, ft)

assembleMassMatrix!(globdat, domain)
updateStates!(domain, globdat)


ts = LinRange(0, T, NT+1)
adaptive_solver_args = Dict("Newmark_rho"=> 0.0, 
                          "Newton_maxiter"=>10, 
                          "Newton_Abs_Err"=>1e-4, 
                          "Newton_Rel_Err"=>1e-6, 
                          "damped_Newton_eta" => 1.0)

globdat, domain, ts = AdaptiveSolver("NewmarkSolver", globdat, domain, T, NT, adaptive_solver_args)


# Δt = T/NT



# ρ_oo = 0.0
# αm = (2*ρ_oo - 1)/(ρ_oo + 1)
# αf = ρ_oo/(ρ_oo + 1)
# for i = 1:NT
#     @info i, "/" , NT
#     solver = NewmarkSolver(Δt, globdat, domain, αm, αf, 1e-4, 1e-6, 100)
#     # error()
#     # close("all")
#     # visσ(domain,-1.5e9, 4.5e9)
#     # savefig("Debug/$i.png")
#     # error()
#     # if i==100
#     #     close("all")
#     #     visσ(domain)
#     #     # visσ(domain,-1.5e9, 4.5e9)
#     #     savefig("Debug/test$(tid)i=75.png")
#     #     # break
#     # end
# end

# plot
close("all")
visσ(domain)
savefig("Debug/test$tid.png")

close("all")
visσ(domain)
axis("equal")
savefig("Debug/order$porder/test_stress$(tid)_$force_scale.png")

close("all")
ux = [reshape(domain.history["state"][i][1:(nx*porder+1)*(ny*porder+1)], ny*porder+1, nx*porder+1)[1,end] for i = 1:length(domain.history["state"])]
plot(ts, ux)
savefig("Debug/order$porder/test_ux$(tid)_$force_scale.png")

close("all")
uy = [reshape(domain.history["state"][i][(nx*porder+1)*(ny*porder+1)+1:end], ny*porder+1, nx*porder+1)[1,end] for i = 1:length(domain.history["state"])]
plot(ts, uy)
savefig("Debug/order$porder/test_uy$(tid)_$force_scale.png")

