##################
# Pull up BCA functions
#####################
#include("../BCAq.jl") #Mac
include("..\\BCAq.jl") #windows
 

###################################
# Australia data, parameters, and estimates
##################################
ausparams = [1.0144^(1/4)-1;1.0208^(1/4)-1;0.975^(1/4);1.-(1.-0.05)^(1/4);2.5;1.000001;1./3.]
ausdata_raw = reshape(readdlm("ausdata.txt"),140,7)
ausdata = ausdata_raw[:,1:end]


#ausdata = reshape(data,6,140)'
x = [
   0.1;
   0.1;
  -0.1;
  -1.0;
   0.995;
   0.01;
  -0.01;
   0.01;
   0.01;
   0.995;
  -0.01;
  -0.01;
   0.01;
   0.01;
   0.995;
  -0.01;
   0.01;
   0.01;
  -0.01;
   0.90;
   0.01;
   0.001;
  -0.001;
   0.001;
   0.001;
  -0.001;
   0.001;
   0.001;
   0.001;
    0.001]

#=
it = 50
XX = zeros(30,it)
FF = zeros(it)

@show mlestar = Optim.optimize(t->mleq(t,ausparams,ausdata)[1], x, NelderMead(),
    Optim.Options(g_tol = 1e-6,iterations = 30000,show_trace = true))
XX[:,1],FF[1] = Optim.minimizer(mlestar),Optim.minimum(mlestar)
x1 = Optim.minimizer(mlestar)

@show mlestar = Optim.optimize(t->mleq(t,ausparams,ausdata)[1], x1, NelderMead(),
    Optim.Options(g_tol = 1e-6,iterations = 30000,show_trace = true))
XX[:,2],FF[2] = Optim.minimizer(mlestar),Optim.minimum(mlestar)
x1 = Optim.minimizer(mlestar)

#Move away to see if we get some improvement:
for i = 3:it
    @show mlestar = Optim.optimize(t->mleq(t,ausparams,ausdata)[1], 0.99*x1, NelderMead(),
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
####From the time consuming exercise above, I save the file in text
ausest = readdlm("ausestJP.txt")[:,1]

###############################################################
###############################################################
#
#     Printing US wedges
#
#############################################################
###years for plotting
years = collect(2008.25:0.25:2015)
_,_,_,loutput,wedges =  log_lin_wedges(ausest,1,ausparams,ausdata) ## 1 implies steady state at period 1959q1
start_T = 113
final_T = 140
#plott = plot(fmt = :png)
plot(years,100*(exp.(wedges[start_T:final_T,1])/exp.(wedges[start_T,1])).^(1.- 1.0/3.0), label="productivity wedge")
plot!(years,100*(1.0 + wedges[start_T,3])*(1 ./ (1.0+wedges[start_T:final_T,3])), label="investment wedge")
plot!(years,100*(1.0 - wedges[start_T:final_T,2])./(1.0 - wedges[start_T,2]), label="labor wedge")
plot!(years,100*exp.(loutput[start_T:final_T])./exp.(loutput[start_T]), label="output")
plot!(years,100*exp.(wedges[start_T:final_T,4])/exp.(wedges[start_T,4]), label = "government wedge")
plot!(legend=:topright)
savefig("wedges.png")


