using PyPlot
using PyCall
#mpl = pyimport("tikzplotlib")
using JLD2


T = 0.2
NT = 200
t = LinRange(0,T,NT+1)

tid = 1

@load "../Data/domain$tid.jld2" domain 
@load "../Data/domain_$(nntype)_te$(tid).jld2" domain_te 
#domain_te = domain

# close("all")
# u1 = hcat(domain.history["state"]...)
# u2 = hcat(domain_te.history["state"]...)
# u = abs.(u1 - u2)
# for i = 1:5
#     plot(t, u[i,:], label="$i")
# end
# xlabel("\$t\$")
# ylabel("\$||u_{ref}-u_{exact}||\$")
# legend()
# #mpl.save("truss1d_disp_diff$tid.tex")
# savefig("truss1d_disp_diff.pdf")

close("all")
strain = hcat(domain.history["strain"]...)
stress = hcat(domain.history["stress"]...)
i = 8
plot(strain[i,:], stress[i,:], "--", label="Reference")


strain = hcat(domain_te.history["strain"]...)
stress = hcat(domain_te.history["stress"]...)
i = 8
plot(strain[i,:], stress[i,:], ".", label="Estimated")

xlabel("Strain")
ylabel("Stress")
legend()
#mpl.save("truss1d_stress$tid.tex")
savefig("truss1d_stress$tid.pdf")