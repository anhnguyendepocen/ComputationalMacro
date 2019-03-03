#using QuantEcon

#Include ayiagari functions and types
include("ayiagari.jl")



r0 = 0.001
MM = AyiagariModel(r0,1.0,0.96,0.025,1.0,0.0,1.5,1.0,0.36,1.0,100000000000.0,30,30.0,[0.2,1.0],2)
na,ns = MM.FiniteElement.na,MM.MarkovChain.ns
nodes = MM.FiniteElement.nodes
@unpack DistributionSize, DistributionAssetGrid = MM.Distribution

ResidualSize = na*ns
NumberOfHouseholds = DistributionSize

#####################################
##############Jacobian tests
######################################
#jacobian = zeros(ResidualSize,ResidualSize)
#jacobian = WeightedResidual(MarkovElement.Guess,0.025,MarkovElement)[2]
#jacobian2 =  ForwardDiff.jacobian(x -> WeightedResidual(x,0.025,MarkovElement)[1],MarkovElement.Guess)
#@show LinearAlgebra.norm(jacobian - jacobian2)
#show(IOContext(STDOUT, limit=true,displaysize = (400,100)), "text/plain", jacobian - jacobian2)

#arkovElement

#thetastar = SolveFiniteElement(r0,MarkovElement.Guess,MarkovElement)
@time thetastar,w,r,L,K,polc,poll,gap,eqdist = equilibrium(MM)
println("---------- Equilibrium achieved ---------------")
println("wage = ",w," interest rate = ",r, " aggregate capital = ",K," aggregate labor = ",L)

#θeq,w,r,L,K
pol = reshape(thetastar,na,ns)

###Plot the policy

pa = plot(DistributionAssetGrid,gap[:,1], label = "unemployed")
pa = plot!(DistributionAssetGrid,gap[:,2], label = "employed")
pa = plot!(DistributionAssetGrid,DistributionAssetGrid, line = :dot ,label = "45 degree line")
pa = plot!(xlims = (0.0,20.0),ylims=(0.0,20.0))
pa = plot!(title="Assets")

pl = plot(DistributionAssetGrid,poll[:,1], label = "unemployed")
pl = plot!(DistributionAssetGrid,poll[:,2], label = "employed")
pl = plot!(title="hours")

pc = plot(DistributionAssetGrid,polc[:,1], label = "unemployed")
pc = plot!(DistributionAssetGrid,polc[:,2], label = "employed")
pc = plot!(title="Consumption")
###Plot the Distribution
p1 = plot(DistributionAssetGrid,eqdist[1:NumberOfHouseholds],label="unemployed")
p1 = plot!(DistributionAssetGrid,eqdist[NumberOfHouseholds+1:2*NumberOfHouseholds],label="employed")
p1 = plot!(xlims = (0.0,20.0))
p1 = plot!(title="Distribution of Assets")
p = plot(pa,pl,pc,p1, layout=(2,2))
p = plot!(legendfont = font(4,"courier"))
p = plot!(titlefont = font(6,"courier"))
p = plot!(xaxis = font(4,"courier"))
p = plot!(yaxis = font(4,"courier"))
savefig(p,"Solution.pdf")


MM = AyiagariModel(r0,1.0,0.96,0.025,1.0,0.0,1.0,1.0,0.36,1.0,100000000000.0,30,30.0,[0.2,1.0],2)

@time thetastar,w,r,L,K,polc,poll,gap,eqdist = equilibrium(MM)
println("---------- Equilibrium achieved ---------------")
println("wage = ",w," interest rate = ",r, " aggregate capital = ",K," aggregate labor = ",L)

#θeq,w,r,L,K
pol = reshape(thetastar,na,ns)

###Plot the policy

pa = plot(DistributionAssetGrid,gap[:,1], label = "unemployed")
pa = plot!(DistributionAssetGrid,gap[:,2], label = "employed")
pa = plot!(DistributionAssetGrid,DistributionAssetGrid, line = :dot ,label = "45 degree line")
pa = plot!(xlims = (0.0,20.0),ylims=(0.0,20.0))
pa = plot!(title="Assets")

pl = plot(DistributionAssetGrid,poll[:,1], label = "unemployed")
pl = plot!(DistributionAssetGrid,poll[:,2], label = "employed")
pl = plot!(title="hours")

pc = plot(DistributionAssetGrid,polc[:,1], label = "unemployed")
pc = plot!(DistributionAssetGrid,polc[:,2], label = "employed")
pc = plot!(title="Consumption")
###Plot the Distribution
p1 = plot(DistributionAssetGrid,eqdist[1:NumberOfHouseholds],label="unemployed")
p1 = plot!(DistributionAssetGrid,eqdist[NumberOfHouseholds+1:2*NumberOfHouseholds],label="employed")
p1 = plot!(xlims = (0.0,20.0))
p1 = plot!(title="Distribution of Assets")
p = plot(pa,pl,pc,p1, layout=(2,2))
p = plot!(legendfont = font(4,"courier"))
p = plot!(titlefont = font(6,"courier"))
p = plot!(xaxis = font(4,"courier"))
p = plot!(yaxis = font(4,"courier"))
savefig(p,"Solution2.pdf")




MM = AyiagariModel(r0,1.0,0.93,0.025,1.0,0.0,1.0,1.0,0.36,1.0,100000000000.0,30,30.0,[0.2,1.0],2)

@time thetastar,w,r,L,K,polc,poll,gap,eqdist = equilibrium(MM)
println("---------- Equilibrium achieved ---------------")
println("wage = ",w," interest rate = ",r, " aggregate capital = ",K," aggregate labor = ",L)

#θeq,w,r,L,K
pol = reshape(thetastar,na,ns)

###Plot the policy

pa = plot(DistributionAssetGrid,gap[:,1], label = "unemployed")
pa = plot!(DistributionAssetGrid,gap[:,2], label = "employed")
pa = plot!(DistributionAssetGrid,DistributionAssetGrid, line = :dot ,label = "45 degree line")
pa = plot!(xlims = (0.0,20.0),ylims=(0.0,20.0))
pa = plot!(title="Assets")

pl = plot(DistributionAssetGrid,poll[:,1], label = "unemployed")
pl = plot!(DistributionAssetGrid,poll[:,2], label = "employed")
pl = plot!(title="hours")

pc = plot(DistributionAssetGrid,polc[:,1], label = "unemployed")
pc = plot!(DistributionAssetGrid,polc[:,2], label = "employed")
pc = plot!(title="Consumption")
###Plot the Distribution
p1 = plot(DistributionAssetGrid,eqdist[1:NumberOfHouseholds],label="unemployed")
p1 = plot!(DistributionAssetGrid,eqdist[NumberOfHouseholds+1:2*NumberOfHouseholds],label="employed")
p1 = plot!(xlims = (0.0,20.0))
p1 = plot!(title="Distribution of Assets")
p = plot(pa,pl,pc,p1, layout=(2,2))
p = plot!(legendfont = font(4,"courier"))
p = plot!(titlefont = font(6,"courier"))
p = plot!(xaxis = font(4,"courier"))
p = plot!(yaxis = font(4,"courier"))
p = plot!(xlims=(0.0,20.0))
savefig(p,"Solution3.pdf")
