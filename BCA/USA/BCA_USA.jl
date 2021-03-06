##################
# Pull up BCA functions
#####################
include("../BCAq.jl") #mac and linux
#include("..\\BCAq.jl") #windows

##################
# US data, parameters, and estimates
#####################
usdata = readdlm("usdata.txt")
usparams = [1.015^(1/4)-1.;1.016^(1/4)-1.;0.9722^(1/4);1.-(1.-0.0464)^(1/4);2.24;1.000001;0.35]

x = [
   -0.1;
   0.1;
   0.1;
  -1.0;
   0.95;
   0.01;
   0.01;
   0.01;
   0.01;
   0.95;
   0.01;
   0.01;
   0.01;
   0.01;
   0.95;
   0.01;
   0.01;
   0.01;
   0.01;
   0.95;
   0.01;
   0.001;
   0.001;
   0.001;
   0.001;
   0.001;
   0.001;
   0.001;
   0.001;
   0.001] 

#############################################
#
#This writes the text file (usestJP.txt) in this folder
#
#############################################
#=
it = 50
XX = zeros(30,it)
FF = zeros(it)

@show mlestar = Optim.optimize(t->mleq(t,usparams,usdata)[1], x, NelderMead(),
    Optim.Options(g_tol = 1e-6,iterations = 30000,show_trace = true))
XX[:,1],FF[1] = Optim.minimizer(mlestar),Optim.minimum(mlestar)
x1 = Optim.minimizer(mlestar)

@show mlestar = Optim.optimize(t->mleq(t,usparams,usdata)[1], x1, NelderMead(),
    Optim.Options(g_tol = 1e-6,iterations = 30000,show_trace = true))
XX[:,2],FF[2] = Optim.minimizer(mlestar),Optim.minimum(mlestar)
x1 = Optim.minimizer(mlestar)

#Move away to see if we get some improvement:
for i = 3:it
    @show mlestar = Optim.optimize(t->mleq(t,usparams,usdata)[1], 0.99*x1, NelderMead(),
        Optim.Options(g_tol = 1e-6,iterations = 30000,show_trace = false))
    x1 =  Optim.minimizer(mlestar)
    XX[:,i],FF[i] = x1, Optim.minimum(mlestar)
    if norm(FF[i] - FF[i-1]) < 1e-10
        break
    end
end
id = findfirst(FF,minimum(FF))
writedlm("usestJP.txt",XX[:,id])
=#

usest = readdlm("usestJP.txt")[:,1]


###############################################################
###############################################################
#
#     Printing US wedges
#
##############################################################
years = collect(1979.25:0.25:1985)
_,_,_,loutput,wedges =  log_lin_wedges(usest,1,usparams,usdata) ## 1 implies steady state at period 1959q1
start_T = 81
final_T = 81+27
#plott = plot(fmt = :png)
plot(years,100*(exp.(wedges[start_T:final_T,1])/exp.(wedges[start_T,1])).^0.65, label="productivity wedge")
plot!(years,100*(1.0 + wedges[start_T,3])*(1 ./ (1.0+wedges[start_T:final_T,3])), label="investment wedge")
plot!(years,100*(1.0 - wedges[start_T:final_T,2])./(1.0 - wedges[start_T,2]), label="labor wedge")
plot!(years,100*exp.(loutput[start_T:final_T])./exp.(loutput[start_T]), label="output")
plot!(years,100*exp.(wedges[start_T:final_T,4])/exp.(wedges[start_T,4]), label = "government wedge")
plot!(legend=:topleft)
savefig("us_wedges.png")

@show length(wedges[start_T:final_T,1])
@show length(years)
