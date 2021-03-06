using Calculus
using QuantEcon
import QuantEcon.simulate
using Calculus 
using Interpolations
using Plots
using BenchmarkTools
using Parameters

#################################################################
#
# Lucas & Stokey 1983 
#
#################################################################

"""
Given the utility:
u = log(c) + ψ*log(n)

Solve the following system of equations

feasibility: c(s) + g(s) = l(s)
mris:        -un/uc = 1

inputs:
1. model parameters
2. convergence parameters (tol, maxit)

output:
1. c: consumption
2. n: labor
3. xi: lagrange multiplier of feasibility - marginal utility wrt consumption
"""
function find_FB(
                 parameters::amss_params{R,I},
                 maxn::I=50,
                 tol::T=1e-6) where{R <: Real,I <: Integer,T <:AbstractFloat}

    @unpack β,ψ,α,γ,Π,G,P,nS,A = parameters
    
    z = 0.3*ones(2*nS) #c and n
    xi = zeros(nS)
    res = zeros(2*nS)
    dres = zeros(2*nS,2*nS)
    for i = 1:100
        c = z[1:nS]
        n = z[nS+1:2*nS]
        for s = 1:nS
            uc   = c[s]^(-α)
            ucc  = -α*c[s]^(-1.-α)
            un   = -ψ*n[s]^γ
            unn  = -ψ*γ*n[s]^(γ-1.)
            #=uc = 1.0/c[s]
            un = -ψ/(1. -n[s])
            ucc = -c[s]^(-2)
            unn = -ψ/(1. -n[s])^2 
            uc = 1.0
            un = -ψ/(1. -n[s])
            ucc = 0.0
            unn = -ψ/(1. -n[s])^2=#
            
            ##residual
            res[s] = uc + un
            res[s+2] = n[s] - c[s] - G[s]
            
            ##jacobian
            dres[s,s] = ucc
            dres[s,s+nS] = unn
            dres[nS+s,s] = -1.
            dres[nS+s,nS+s] = 1.
        end
        step = -dres \ res
        z += step
        if norm(step)<tol
            break
        end
    end
    
    c = z[1:nS]
    n = z[nS+1:2*nS]
    
    for s =1:nS
        xi[s] = c[s]^(-α)
    end
    
    return [c;n;xi] 
end


"""
Given the utility:
u = log(c) + ψ*log(n)
Household problem for t ≧ 1 for a household entering with "bonds" x at state s 

V(x,s) = max_{c,n,x'} u(c,1-n) + β∑π(s'|s)V(x',s')
s.t. 
x = uc(s)*c(s) - ul(s)*n(s) + β∑π(s'|s)x'(s')    :μ
c(s) + g(s) = n(s)                               :ξ(s)

This leads to finding the root of the following system

1. feasibility: c(s) + g(s) = n(s)
2. FOC wrt c:   uc - μ*(ucc(s)*c(s) + uc(s)) - ξ(s)
3. FOC wrt n:   un - μ*(unn(s)*n(s) + un(s)) + ξ(s)

inputs:
1. model parameters
2. convergence parameters (tol, maxit)

output:
1. c: consumption
2. n: labor
3. xi: lagrange multiplier of feasibility - marginal utility wrt consumption
"""
function time1_allocation(μ::R,
                          parameters::amss_params{R,I},
                          maxn::I = 50,
                          tol::T = 1e-6) where{R <: Real,I <: Integer,T <:AbstractFloat}
    @unpack β,ψ,α,γ,Π,G,P,nS,A = parameters
    
    z = find_FB(parameters)
    
    dres = zeros(3*nS,3*nS)
    res = zeros(3*nS)
    for i = 1:20
        c = z[1:nS]
        n = z[nS+1:2*nS]
        xi = z[2*nS+1:3*nS]
        for s = 1:nS
            uc   = c[s]^(-α)
            ucc  = -α*c[s]^(-1.-α)
            uccc = -α*(-α-1.)*c[s]^(-α-1.-1.)
            un   = -ψ*n[s]^(γ)
            unn  = -ψ*γ*n[s]^(γ-1)
            unnn = -ψ*γ*(γ-1.)*n[s]^(γ-1.-1.) 
            #=uc = 1.0/c[s]
            un = -ψ/(1. -n[s])
            ucc = -c[s]^(-2)
            uccc = 2.*c[s]^(-3)
            unn = -ψ/(1. -n[s])^2
            unnn = -2.*ψ/(1. -n[s])^3
            uc = 1.0
            un = -ψ/(1. -n[s])
            ucc = 0.0
            uccc = 0.0
            unn = -ψ/(1. -n[s])^2
            unnn = -2.*ψ/(1. -n[s])^3=#
            
            ##Residual
            res[s] = uc - μ*(ucc*c[s] + uc) - xi[s]
            res[nS+s] = un - μ*(unn*n[s] + un) + xi[s]
            res[2*nS+s] = n[s] - c[s] - G[s]
            
            ##Jacobian
            #first equations
            dres[s,s] = ucc - μ*(uccc*c[s] + ucc + ucc)
            dres[s,nS+s] = 0.0
            dres[s,2*nS+s] = -1.0
            #second equations
            dres[nS+s,s] = 0.0 
            dres[nS+s,nS+s] = unn - μ*(unnn*n[s] + unn + unn)
            dres[nS+s,2*nS+s] = 1.0
            #third equations
            dres[2*nS+s,s] = -1.0
            dres[2*nS+s,nS+s] = 1.0
            dres[2*nS+s,2*nS+s] = 0.0
        end
        step = -dres \ res
        z +=  step
        residual = norm(step)
        #println("residual at iteration ",i,": ",residual)
        if residual<tol
            break
        end
    end
        
    c = z[1:nS]
    n = z[nS+1:2*nS]
    xi = z[2*nS+1:3*nS]
    
    uc  = c.^(-α)
    un = -ψ*n.^(γ)
    LHS = uc.*c + un.*n
    x = A \ LHS
    
    
    return c,n,x,xi
end


function time0_allocation(b_::R,
                          s0::I,
                          parameters::amss_params{R,I},
                          maxn::I = 5000,
                          tol::T = 1e-5) where{R <: Real,I <: Integer,T <:AbstractFloat}

    @unpack β,ψ,α,γ,Π,G,P,nS,A = parameters
    
    #Get FB
    FB = find_FB(parameters)
    c_FB = FB[1:nS]
    n_FB = FB[nS+1:2*nS]
    xi_FB = FB[2*nS+1:3*nS]
    
    #Initial guess from FB
    z = [0.0;c_FB[1];n_FB[1];xi_FB[1]]
    
    dres = zeros(4,4)
    res = zeros(4)
    for i = 1:maxn
        μ,c0,n0,xi0 = z[1],z[2],z[3],z[4]
        xp = time1_allocation(μ)[3]
        uc0 = 1.0/c0
        un0 = -ψ/(1.0 - n0)
        ucc0 = -c0^(-2.)
        uccc0 = 2.0*c0^(-3.)
        unn0 = -ψ/(1.0 - n0)^2.
        unnn0 = -2.*ψ/(1.0 - n0)^3.

        ##Residual
        res[1] = uc0*(c0-b_) + un0*n0 + β*dot(Π[s0,:],xp)
        res[2] = uc0 - μ*(ucc0*(c0-b_) + uc0) - xi0
        res[3] = un0 - μ*(unn0*n0 + un0) + xi0
        res[4] = n0 - c0 - G[s0]

        ##Jacobian
        #first equation
        dres[1,1],dres[1,2] = 0.0, ucc0*(c0-b_) + uc0
        dres[1,3],dres[1,4] = unn0*n0 + un0, 0.0  
        #second equation       
        dres[2,1],dres[2,2] = -(ucc0*(c0-b_) + uc0), ucc0 - μ*(uccc0*(c0-b_) + ucc0 + ucc0)  
        dres[2,3],dres[2,4] = 0.0, -1.0
        #third equation       
        dres[3,1],dres[3,2] = -(unn0*n0 + un0), 0.0
        dres[3,3],dres[3,4] = unn0 - μ*(unnn0*n0 + unn0 + unn0), 1.0
        #fourth equation        
        dres[4,1],dres[4,2] = 0.0, -1.0 
        dres[4,3],dres[4,4] = 1.0, 0.0  
        
        #newton step
        step = -dres \ res
        
        #update
        z  +=  1/100*step
        residual = norm(step)
        println(residual)
        if residual<tol
            println("Converged in ",i," steps")
            break
        end
    end
    
    return z
end




"""
Use Lucas & Stokey 1983 as guess for AMSS

Retrieve complete markets solution for
continuation problem given a μ_
"""
function guess(_μ::R,
               _s::I,
               μGrid::Array{R,1},
               parameters::amss_params{R,I}) where{R <: Real,I <: Integer}
    
    @unpack β,ψ,α,γ,Π,G,P,nS,A = parameters
    #β,ψ,α,γ,Π,G,P,nS,A = parameters.β,parameters.ψ,parameters.α,parameters.γ,parameters.Π,parameters.G,parameters.P,parameters.nS,parameters.A
    μ = zeros(nS)
    c,n,xp,ξ = time1_allocation(_μ,parameters) ####guess from complete markets
    uc,ucc,uccc = zeros(nS),zeros(nS),zeros(nS)
    un,unn,unnn = zeros(nS),zeros(nS),zeros(nS)
    
    for s = 1:nS
        uc[s]   = c[s]^(-α)
        ucc[s]  = -α*c[s]^(-1.-α)
        uccc[s] = -α*(-α-1.)*c[s]^(-α-1.-1.)
        un[s]   = -ψ*n[s]^(γ)
        unn[s]  = -ψ*γ*n[s]^(γ-1.)
        unnn[s] = -ψ*γ*(γ-1.)*n[s]^(γ-1.-1.)
    end 
    #=for s = 1:nS
        uc[s] = 1.0/c[s]
        un[s] = -ψ/(1. -n[s])
        ucc[s] = -c[s]^(-2)
        uccc[s] = 2.*c[s]^(-3)
        unn[s] = -ψ/(1. -n[s])^2
        unnn[s] = -2.*ψ/(1. -n[s])^3
    end 
    for s = 1:nS
        uc[s] = 1.0
        un[s] = -ψ/(1. -n[s])
        ucc[s] = 0.0
        uccc[s] = 0.0
        unn[s] = -ψ/(1. -n[s])^2
        unnn[s] = -2.*ψ/(1. -n[s])^3
    end =#


    
    #Guess for the state variable Bs
    B_s = zeros(length(μGrid),nS)    
    for μi = 1:length(μGrid)
        _,_,xp_,_ = time1_allocation(μGrid[μi],parameters)
        for s = 1:nS 
            B_s[μi,s] = xp_[s]
        end
    end
    knots = (μGrid,)
    Bitp = interpolate(knots,B_s[:,_s], Gridded(Linear())) 

    #Pre-allocating expectations 
    βexp_uc = 0.0
    expx = 0.0
    for s = 1:nS
        βexp_uc += β*Π[_s,s]*uc[s]
        expx += Π[_s,s]*xp[s]
    end
    #x = expx
    x = xp[_s]
    #x = zeros(nS)
    #x = xp
    
    μ = _μ*ones(nS)
    #Π[s_,s]*μ[s]*uc[s]/βexp_uc
    for s = 1:nS
        #if s != _s
        #    μ[s] = βexp_uc*(_μ - Π[_s,_s]*μ[_s]*uc[_s]/βexp_uc)/(Π[_s,s]*uc[s])
        #end
        #@show x[s] = βexp_uc*(Bitp[μ[s]] + uc*c[s] + un*n[s] )/uc
        μ[s] = 0.95*_μ #(un[s] + ξ[s])/(unn[s]*n[s] + un[s]) 
    end
    #μtil = min.(μGrid[end],max.(μ,μGrid[1])) 
    #μtil = [0.4;0.4]
    z = [c;n;μ;ξ;x]
    
    
    B_s,z
end


function IM_time1_system(z::Array{R,1},
                         μ_::R,
                         s_::I,
                         μGrid::Array{R,1},
                         Bguess::Array{R,2},
                         parameters::amss_params{R,I},
                         maxn::I = 50,
                         tol::T = 1e-6) where{R <: Real,I <: Integer,T <:AbstractFloat}
    
    @unpack β,ψ,α,γ,Π,G,P,nS,A = parameters
    c = z[1:nS]
    n = z[nS+1:2*nS]
    μ = z[2*nS+1:3*nS]
    #μ = min.(μGrid[end],max.(z[2*nS+1:3*nS] ,μGrid[1])) 
    ξ = z[3*nS+1:4*nS]
    x = z[4*nS+1]

    
    #A = ones(length(μGrid))*xp[s_]
    knots = (μGrid,)
    Bitp = interpolate(knots,Bguess[:,s_], Gridded(Linear())) 
    
    
    uc,ucc,uccc = zeros(nS),zeros(nS),zeros(nS)
    un,unn,unnn = zeros(nS),zeros(nS),zeros(nS)
    
    #=for s = 1:nS
        uc[s] = 1.0/c[s]
        un[s] = -ψ/(1. -n[s])
        ucc[s] = -c[s]^(-2)
        uccc[s] = 2.*c[s]^(-3)
        unn[s] = -ψ/(1. -n[s])^2
        unnn[s] = -2.*ψ/(1. -n[s])^3
    end 
    for s = 1:nS
        uc[s] = 1.0
        un[s] = -ψ/(1. -n[s])
        ucc[s] = 0.0
        uccc[s] = 0.0
        unn[s] = -ψ/(1. -n[s])^2
        unnn[s] = -2.*ψ/(1. -n[s])^3
    end =#
    for s = 1:nS
        uc[s]   = c[s]^(-α)
        ucc[s]  = -α*c[s]^(-1.-α)
        uccc[s] = -α*(-α-1.)*c[s]^(-α-1.-1.)
        un[s]   = -ψ*n[s]^(γ)
        unn[s]  = -ψ*γ*n[s]^(γ-1)
        unnn[s] = -ψ*γ*(γ-1.)*n[s]^(γ-1.-1.)
    end
    
    
    
    βexp_uc = 0.0
    for s = 1:nS
        βexp_uc += β*Π[s_,s]*uc[s]
    end

    res = zeros(4*nS+1)
    
    #First 4 sets of functions that depend on s, build residual and jacobian of residual
    for s = 1:nS
        ##Residual
        Bitp = interpolate(knots,Bguess[:,s], Gridded(Linear()))
        res[s] = n[s] - c[s] - G[s]
        res[nS+s] = Bitp[μ[s]] + uc[s]*c[s] + un[s]*n[s] - uc[s]*x/βexp_uc   
        res[2*nS+s] = uc[s] - μ[s]*(ucc[s]*c[s] + uc[s]) + (μ[s] - μ_)*ucc[s]*x/βexp_uc - ξ[s]
        res[3*nS+s] = un[s] - μ[s]*(unn[s]*n[s] + un[s]) + ξ[s]
    end

    
    #last equation which does not depend on s
    rhs = 0.0
    for s = 1:nS
        rhs += β*Π[s_,s]*μ[s]*uc[s]/βexp_uc
    end
    res[4*nS+1] = μ_ - rhs
                
    return res,z
end 


function iteration_B(μGrid::Array{R,1},
                     parameters::amss_params{R,I},
                     maxn::I = 300,
                     tol::T = 1e-5) where{R <: Real,I <: Integer,T <:AbstractFloat}
    
    @unpack β,ψ,α,γ,Π,G,P,nS,A = parameters
    nμ = length(μGrid)
    
    #Initialize jacobian matrix
    num_der = zeros(4*nS+1,4*nS+1)
    c_pol = zeros(nS,nS,nμ) #s_,s,μ dimension
    n_pol = zeros(nS,nS,nμ) #s_,s,μ dimension
    μ_pol = zeros(nS,nS,nμ) #s_,s,μ dimension
    ξ_pol = zeros(nS,nS,nμ) #s_,s,μ dimension
    B_pol = zeros(nS,nS,nμ) #s_,s,μ dimension
    
    
    #Guess initial bond holdings 
    B_,z_ = guess(0.0,1,μGrid,parameters)
    
    #Initialize update for initial bond holdings
    #Bp = copy(B_)
    for n = 1:maxn
        #Bp = 0.0
        Bp = copy(B_)
        for si = 1:nS
            for μi = 1:nμ
                #initial multiplier
                μ_ = μGrid[μi]

                #Take a guess from the complete markets case
                _,z_ = guess(μ_,si,μGrid,parameters)


                #Start Newton's algorithm

                for ite = 1:50
                    #compute jacobian
                    for i = 1:4*nS+1
                         num_der[i,:] = Calculus.gradient(t -> IM_time1_system(t,μ_,si,μGrid,B_,parameters)[1][i],z_)
                    end
                    #num_der = ForwardDiff.jacobian(system!,num_der,z_)
                    
                    step = -num_der \ IM_time1_system(z_,μ_,si,μGrid,B_,parameters)[1]
                    #@show num_der
                    #@show μ_
                    z_ += step
                    #@show μi
                    #@show norm(step)
                    if norm(step) < 1e-10
                        #println("converged")
                        Bp[μi,si] = z_[4*nS+1]
                        c_pol[si,:,μi] = z_[1:nS] #s_,s,μ
                        n_pol[si,:,μi] = z_[nS+1:2*nS] #s_,s,μ
                        μ_pol[si,:,μi] = z_[2*nS+1:3*nS] #s_,s,μ
                        ξ_pol[si,:,μi] = z_[3*nS+1:4*nS] #s_,s,μ
                        B_pol[si,:,μi] = z_[4*nS+1] #s_,s,μ     
                        break
                    end
                end
            end
        end
        @show norm(Bp - B_)
        if norm(Bp - B_) < tol
            println("bonds function converged")
            return Bp,c_pol,n_pol,μ_pol,ξ_pol,B_pol
            break
        end
        B_ = Bp
    end
end


function time_series(μ0::R,
                     s0::I,
                     state_series::Array{I,1},
                     c_policy::Array{R,3},
                     l_policy::Array{R,3},
                     ξ_policy::Array{R,3},
                     μ_policy::Array{R,3},
                     B_policy::Array{R,2},
                     μ_Grid::Array{R,1},
                     parameters::amss_params{R,I}) where{R <: Real,I <: Integer}
    
    # Inputs
    #   - state_series     : times series of state indicators
    #   - μ0               : initial multiplier, μ_
    #   - s0               : initial state, s_
    #   - T                : number of time periods

    @unpack β,ψ,α,γ,Π,G,P,nS,A = parameters
    #β,ψ,α,γ,Π,G,P,nS,A = parameters.β,parameters.ψ,parameters.α,parameters.γ,parameters.Π,parameters.G,parameters.P,parameters.nS,parameters.A
    T = length(state_series)
    Grid = μ_Grid
    nμ = length(Grid)
    
    knots = (Grid,)
    #@show Citp = interpolate(knots,c_policy[1,1,:], Gridded(Linear())) 
    #@show 0.0
    
    # (B) - Initializations 
    C = zeros(T)                  # Consumption
    L = zeros(T)                  # Labor
    Bondsp = zeros(T)             # Bonds
    Tax = zeros(T)                # Tax rate
    LTR = zeros(T)                # Labor tax revenue
    gexp = zeros(T)               # Government Spending
    μ_state = zeros(T)            # μ_policy
    
    # (C) - Construct time series for variables 
    for t = 1:T
        
        # Select current state μ_
        if t==1
            μ_ = μ0
            #@show iμ_ = searchsortedlast(Grid,μ_) 
        else
            μ_ = μ_state[t-1] 
            #@show iμ_ = searchsortedlast(Grid,μ_) 
        end
        
        # Select past exogenous state s_
        if t==1
            s_ = s0
            #s_ = convert(Int64, s_)
        else
            s_ = state_series[t-1]
            #s_ = convert(Int64, s_)
        end
        
        # Select current state + exogenous variables
        s = state_series[t]
        Citp = interpolate(knots,c_policy[s_,s,:], Gridded(Linear())) 
        Litp = interpolate(knots,l_policy[s_,s,:], Gridded(Linear())) 
        μitp = interpolate(knots,μ_policy[s_,s,:], Gridded(Linear())) 
        Bitp = interpolate(knots,B_policy[:,s], Gridded(Linear())) 

        #Shock
        g = G[s]

        ##policies
        c,l,μ = Citp[μ_],Litp[μ_],μitp[μ_]

        #taxes
        uc,un = c^(-α) , -ψ*l^γ
        

        #debt
        b = c*Bitp[μ]

        ##Updating
        C[t],L[t],μ_state[t] = c,l,μ
        Bondsp[t],Tax[t],gexp[t] = b, 1.0 + un/uc,g
    end
    
    return C,L,Tax,μ_state,Bondsp,gexp
    
end
