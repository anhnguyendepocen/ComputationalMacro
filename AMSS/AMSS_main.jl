#### Include AMSS functions
struct amss_params{R <: Real,I <: Integer}
β::R
ψ::R
α::R
γ::R
Π::Array{R,2}
G::Array{R,1}
P::Array{R,1}
nS::I
A::Array{R,2}
end

#####################
### Paremeters
######################
β = 0.9
ψ = 1.00
α = 0.00
γ = 1.0
Π = [0.5 0.5;0.5 0.5]
μGrid = collect(linspace(-0.7,0.01,50))
G = [0.1;0.2]
P = [1.0;1.0]
nS = length(G)
A = eye(nS)
for s = 1:nS
    for sp = 1:nS
        if ~(s == sp)
            A[s,sp] = -β*Π[s,sp]
        else
            A[s,sp] = 1.-β*Π[s,sp]
        end
    end
end
parameters = amss_params(β,ψ,α,γ,Π,G,P,nS,A)



#########################
### Solve model
########################

##load functions that solve the model
include("AMSS.jl")

##Solve
Bp_pol,c_pol,n_pol,μ_pol,ξ_pol,B_pol = iteration_B(μGrid,parameters)



#########################
### Simulate time series
########################

### Simulate series of shocks
mc = MarkovChain(Π, [1, 2])
sseries = simulate(mc,5000,init=1)


### Simulate response based on model solution and initial (μ_,s_)
μ_,s_ = -0.1,1

### get series of aggregates
cc,ll,tt,μμ,bb,gg = time_series(μ_,s_,sseries,c_pol,n_pol,ξ_pol,μ_pol,Bp_pol,μGrid,parameters)


#########################
### Plot series (linear in consumption)
########################
figl = plot(ll,title = "labor")
figc = plot(cc,title = "consumption")
figb = plot(bb,title = "bonds")
figt = plot(tt,title = "taxes")
figμ = plot(μμ,title = "l multiplier")
figg = plot(gg,title = "government")
plot(figl,figc,figb,figt,figμ,figg, layout=(3,2),legend = false)
savefig("debt_timeseries_linear.png")


###make it log utility
α2 = 1.000001
parameters2 = amss_params(β,ψ,α2,γ,Π,G,P,nS,A)

##Solve model again
Bp_pol,c_pol,n_pol,μ_pol,ξ_pol,B_pol = iteration_B(μGrid,parameters2)

##Use same initial conditions

##get series of aggregates
cc,ll,tt,μμ,bb,gg = time_series(μ_,s_,sseries,c_pol,n_pol,ξ_pol,μ_pol,Bp_pol,μGrid,parameters2)

#########################
### Plot series
########################
figl = plot(ll,title = "labor")
figc = plot(cc,title = "consumption")
figb = plot(bb,title = "bonds")
figt = plot(tt,title = "taxes")
figμ = plot(μμ,title = "l multiplier")
figg = plot(gg,title = "government")
plot(figl,figc,figb,figt,figμ,figg, layout=(3,2),legend = false)
savefig("debt_timeseries_concave.png")
