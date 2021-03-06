using LinearAlgebra
using Parameters
using IterativeSolvers
using Plots
using FastGaussQuadrature
using BenchmarkTools
using ForwardDiff
using DelimitedFiles
################################### Model types #########################

struct ModelParameters{R <: Real}
    β::R
    d::R
    A::R
    B_::R
    γc::R
    γl::R
    α::R
    T::R
    ζ::R
end

struct ModelFiniteElement{R <: Real,I <: Integer}
    nodes::Array{R,1}
    na::I
    m::I
    wx::Array{R,1}
    ax::Array{R,1}
end

struct ModelMarkovChain{R <: Real,I <: Integer}
    states::Array{R,1}
    ns::I
    stateID::Array{I,1}
    Π::Array{R,2}
end

struct ModelDistribution{R <: Real,I <: Integer}
    DistributionSize::I
    DistributionAssetGrid::Array{R,1}
end

struct AyiagariMarkovianFiniteElement{R <: Real,I <: Integer}
    Guess::Array{R,1}
    wage::R
    Parameters::ModelParameters{R}
    FiniteElement::ModelFiniteElement{R,I}
    MarkovChain::ModelMarkovChain{R,I}
    Distribution::ModelDistribution{R,I}
end

"""
Construct and Ayiagari model instace of all parts needed to solve the model
"""
function AyiagariModel(
    InterestRate::R,
    LaborSupply::R,
    β = 0.96,
    d = 0.025,
    A = 1.0,
    B_ = 0.0,
    γc = 1.5,
    γl = 1.0,
    α = 0.36,
    T = 1.0,
    ζ = 100000000.0,
    GridSize = 30,
    GridMax = 30.0,
    IndividualStates = [0.2;1.0],
    NumberOfQuadratureNodesPerElement = 2
) where{R <: Real}

    ################## Finite Element pieces
    function grid_fun(a_min,a_max,na, pexp)
        x = range(a_min,step=0.5,length=na)
        grid = a_min .+ (a_max-a_min)*(x.^pexp/maximum(x.^pexp))
        return grid
    end
    nodes = grid_fun(0.0,GridMax,GridSize,4.5)
    QuadratureAbscissas,QuadratureWeights = gausslegendre(NumberOfQuadratureNodesPerElement)
    NumberOfNodes = GridSize    
    NumberOfElements = NumberOfNodes-1
    NumberOfVertices = 2 
    FiniteElement = ModelFiniteElement(nodes,NumberOfNodes,NumberOfQuadratureNodesPerElement,QuadratureWeights,QuadratureAbscissas)

    ################### Distribution pieces
    NumberOfHouseholds = 200
    DistributionAssetGrid = collect(range(nodes[1],stop = nodes[end],length = NumberOfHouseholds))
    Distribution = ModelDistribution(NumberOfHouseholds,DistributionAssetGrid)

    ###Exogenous states and Markov chain
    NumberOfIndividualStates = size(IndividualStates,1)
    TransitionMatrix = [0.4 0.6; 0.1 0.9]
    MarkovChain = ModelMarkovChain(IndividualStates,NumberOfIndividualStates,[1;2],TransitionMatrix)
    ################### Final model pieces
    r = InterestRate
    H = LaborSupply
    #@show w = (1.0 - α)/H
    w = (1-α)*T*((T*α)/(r+d))^(α/(1-α))
    Guess = zeros(NumberOfNodes*NumberOfIndividualStates)
    for j=1:NumberOfIndividualStates
        for i=1:NumberOfNodes
            n = (j-1)*NumberOfNodes + i
            assets = (1.0 + r)*nodes[i] + w*IndividualStates[j]*0.5 - 0.6 
            assets > 0.0 ? Guess[n] = 7.0/8.0 * assets : Guess[n] = 1.0/4.0 * assets 
        end
    end
    GuessMatrix = reshape(Guess,NumberOfNodes,NumberOfIndividualStates)
        
    ################## Maybe elements and element indices
    ElementVertexIndices = ones(Integer,NumberOfVertices,NumberOfElements) #element indices
    ElementVertices = zeros(NumberOfVertices,NumberOfElements)
    for i = 1:NumberOfElements
        ElementVertexIndices[1,i],ElementVertexIndices[2,i] = i,i+1     
        ElementVertices[1,i],ElementVertices[2,i] = nodes[i],nodes[i+1]
    end

    Parameters = ModelParameters(β,d,A,B_,γc,γl,α,T,ζ)
    
    AyiagariMarkovianFiniteElement(Guess,w,Parameters,FiniteElement,MarkovChain,Distribution)
end




"""
Inputs:
nodes: grid on assets
prices: interest rate
Π: transition probability

Output:
θ: solution to the finite element method after imposing boundary conditions

Description:
The main loop has 2 steps:
In the first step, if computes the FEM solution without any boundary conditions
In the second step, we use the 'kink' array of indices to impose the boundary conditions

The weighted residual equation and its jacobian

inputs:
m: quad nodes for integration
ns: number of stochastic states
na: grid size on assets

"""
function WeightedResidual(
    θ::Array{R,1},
    InterestRate::F,
    FiniteElementObj::AyiagariMarkovianFiniteElement{F,I}) where{R <: Real,F<:Real,I <: Integer}
    
    #Model parameters
    @unpack β,d,A,B_,γc,γl,α,T,ζ = FiniteElementObj.Parameters  
    @unpack nodes,na,m,wx,ax = FiniteElementObj.FiniteElement  
    @unpack states,ns,stateID,Π = FiniteElementObj.MarkovChain  
    ne = na-1
    nx = na*ns
    
    #model FiniteElementObj.Parameters
    r = InterestRate
    w = (1.0-α)*T*((T*α)/(r+d))^(α/(1.0-α))
    l,c,uc,ucc,ul,ull,∂c∂a,∂c∂l,∂l∂ai,∂c∂ai,∂l∂aj,∂c∂aj = 0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    lp,cp,ucp,uccp,ulp,ullp,∂cp∂ap = 0.0,0.0,0.0,0.0,0.0,0.0,0.0
    
    dResidual = zeros(R,nx,nx)
    Residual = zeros(R,nx)
    np = 0    
    for s = 1:ns
        ϵ = states[s]
        for n=1:ne
            a1,a2 = nodes[n],nodes[n+1]
            s1 = (s-1)*na + n
            s2 = (s-1)*na + n + 1
            for i=1:m
                #transforming k according to Legendre's rule
                x = (a1 + a2)/2.0 + (a2 - a1)/2.0 * ax[i]
                v = (a2-a1)/2.0*wx[i]

                #Form basis for piecewise function
                basis1 = (a2 - x)/(a2 - a1)
                basis2 = (x - a1)/(a2 - a1)

                #Policy functions
                a = θ[s1]*basis1 + θ[s2]*basis2

                #penalty function
                pen = min(a-B_,0.0)^2
                dpen = 2*min(a-B_,0.0)
                
                l = 0.3
                for j = 1:100
                    c = (1.0 + r)*x + ϵ*w*(1.0 - l) - a
                    ∂c∂l = -ϵ*w
                    ∂c∂a = -1.0
                    ul = A*l^(-γl)
                    ull = -γl*A*l^(-γl - 1.0)
                    uc = c^(-γc)
                    ucc = -γc*c^(-γc - 1.0)                    
                    mrs = -ul + w*ϵ*uc + ζ*min(1.0 - l,0.0)^2
                    dmrs = -ull + w*ϵ*ucc*∂c∂l - 2.0*ζ*min(1.0 - l,0.0)
                    l += -1.0* mrs/dmrs
                    #println(j,": ",abs(mrs/dmrs))
                    if abs(mrs/dmrs) < 1e-8
                        #println(s," ",n," Converged: l = ",l)
                        break
                    end
                    if j == 100
                        println("did not converge")
                    end
                end
                ∂l∂ai = -w*ϵ*ucc/(2.0*ζ*min(1.0 - l,0.0) + ull + (w*ϵ)^2*ucc)
                ∂c∂ai = -ϵ*w*∂l∂ai - 1.0
                
                np = searchsortedlast(nodes,a)

                ##Adjust indices if assets fall out of bounds
                (np > 0 && np < na) ? np = np : 
                    (np == na) ? np = na-1 : 
                        np = 1 

                ap1,ap2 = nodes[np],nodes[np+1]
                basisp1 = (ap2 - a)/(ap2 - ap1)
                basisp2 = (a - ap1)/(ap2 - ap1)

                ####### Store derivatives###############
                dbasisp1 = -1.0/(ap2 - ap1)
                dbasisp2 = -dbasisp1                
                
                tsai = 0.0
                sum1 = 0.0
                for sp = 1:ns
                    sp1 = (sp-1)*na + np
                    sp2 = (sp-1)*na + np + 1
                    ϵp = states[sp]

                    #Policy functions
                    ap = θ[sp1]*basisp1 + θ[sp2]*basisp2

                    lp = 0.5
                    for j = 1:100
                        cp = (1.0 + r)*a + ϵp*w*(1.0 - lp) - ap
                        ∂cp∂lp = -ϵp*w
                        ∂cp∂ap = 1.0
                        ulp = A*lp^(-γl)
                        ullp = -γl*A*lp^(-γl - 1.0)
                        ucp = cp^(-γc)
                        uccp = -γc*cp^(-γc - 1.0)                    
                        mrsp = ulp - w*ϵp*ucp - ζ*min(1.0 - lp,0.0)^2
                        dmrsp = ullp - w*ϵp*uccp*∂cp∂lp + 2.0*ζ*min(1.0 - lp,0.0)
                        lp += -1.0* mrsp/dmrsp
                        if abs(mrsp/dmrsp) < 1e-10
                            break
                        end
                    end
                    cp = (1.0 + r)*a + ϵp*w*(1.0 - lp) - ap
                    
                    #Need ∂cp∂ai and ∂cp∂aj
                    ∂ap∂ai = θ[sp1]*dbasisp1 + θ[sp2]*dbasisp2
                    ∂lp∂ai = (1.0 + r - ∂ap∂ai)*uccp*w*ϵp/(ullp + uccp*(w*ϵp)^2 + 2.0*ζ*min(1.0 - lp,0.0))
                    ∂cp∂ai = (1.0 + r) - ϵp*w*∂lp∂ai - ∂ap∂ai
                    ∂lp∂aj = -uccp*w*ϵp/(ullp + uccp*(w*ϵp)^2 + 2.0*ζ*min(1.0 - lp,0.0))
                    ∂cp∂aj = -ϵp*w*∂lp∂aj - 1.0

                    sum1 += β*(Π[s,sp]*(1.0 + r)*ucp + ζ*pen) 
                    
                    #summing derivatives with respect to θs_i associated with c(s)
                    tsai += β*(Π[s,sp]*(1.0 + r)*uccp*∂cp∂ai + ζ*dpen)
                    tsaj = β*Π[s,sp]*(1.0 + r)*uccp*∂cp∂aj

                    dResidual[s1,sp1] +=  basis1 * v * tsaj * basisp1
                    dResidual[s1,sp2] +=  basis1 * v * tsaj * basisp2
                    dResidual[s2,sp1] +=  basis2 * v * tsaj * basisp1
                    dResidual[s2,sp2] +=  basis2 * v * tsaj * basisp2 
                end
                ##add the LHS and RHS of euler for each s wrt to θi
                dres =  tsai - ucc*∂c∂ai
                
                dResidual[s1,s1] +=  basis1 * v * dres * basis1
                dResidual[s1,s2] +=  basis1 * v * dres * basis2
                dResidual[s2,s1] +=  basis2 * v * dres * basis1
                dResidual[s2,s2] +=  basis2 * v * dres * basis2

                res = sum1 - uc
                Residual[s1] += basis1*v*res
                Residual[s2] += basis2*v*res
            end
        end
    end 
    Residual,dResidual 
end


function SolveFiniteElement(
    InterestRate::R,
    guess::Array{R,1},
    FiniteElementObj::AyiagariMarkovianFiniteElement{R,I},
    maxn::Int64 = 500,
    tol = 1e-9
) where{R <: Real,I <: Integer}

    θ = guess
    #Newton Iteration
    for i = 1:maxn
        Res,dRes = WeightedResidual(θ,InterestRate,FiniteElementObj)
        step = - dRes \ Res
        if LinearAlgebra.norm(step) >1.0
            θ += 1.0/100.0*step
        else
            θ += 1.0/1.0*step
        end
        #@show LinearAlgebra.norm(step)
        if LinearAlgebra.norm(step) < tol
            #println("number of newton steps: ",i)
            return θ
            break
        end
    end
        
    return println("Did not converge")
end


function StationaryDistribution(
    InterestRate::R,
    θ::Array{R,1},
    FiniteElementObj::AyiagariMarkovianFiniteElement{R,I}
) where{R <: Real,I <: Integer}

    @unpack β,d,A,B_,γc,γl,α,T,ζ = FiniteElementObj.Parameters  
    @unpack nodes,na,m,wx,ax = FiniteElementObj.FiniteElement  
    @unpack states,ns,stateID,Π = FiniteElementObj.MarkovChain
    @unpack DistributionSize, DistributionAssetGrid = FiniteElementObj.Distribution
    
    res = DistributionAssetGrid
    nf = ns*DistributionSize
    r = InterestRate
    w = (1.0-α)*T*((T*α)/(r+d))^(α/(1.0-α))
    θ = reshape(θ,na,ns)
    
    ##initialize
    pdf1 = zeros(NumberOfHouseholds*ns)
    Qa = zeros(nf,nf)
    c,ap =zeros(NumberOfHouseholds,ns),zeros(NumberOfHouseholds,ns)

    for s=1:ns
        for i=1:NumberOfHouseholds
            x = res[i] 
            
            ######
            # find each k in dist grid in nodes to use FEM solution
            ######
            n = searchsortedlast(nodes,x)
            (n > 0 && n < na) ? n = n : 
                (n == na) ? n = na-1 : 
                    n = 1 
            x1,x2 = nodes[n],nodes[n+1]
            basis1 = (x2 - x)/(x2 - x1)
            basis2 = (x - x1)/(x2 - x1)
            ap[i,s]  = basis1*θ[n,s] + basis2*θ[n+1,s]
            #c[i,s] = (1.0+r)*x + w*states[s] - ap[i,s] 
            #z[i,s] = (1.0+r)*x + w*states[s]
            
            
            ######
            # Find in dist grid where policy function is
            ######            
            n = searchsortedlast(res,ap[i,s])
            
            ######
            # Build histogram
            ######            
            for si = 1:ns
                aa = (s-1)*NumberOfHouseholds + i
                ss = (si-1)*NumberOfHouseholds + n
                if n > 0 && n < NumberOfHouseholds
                    ω = (ap[i,s] - res[n])/(res[n+1] - res[n])
                    Qa[aa,ss+1] += Π[s,si]*ω
                    Qa[aa,ss]  += Π[s,si]*(1.0 - ω)
                elseif n == 0
                    ω = 1.0
                    Qa[aa,ss+1] += Π[s,si]*ω
                else
                    ω = 1.0
                    Qa[aa,ss] += Π[s,si]*ω
                end
            end
        end
    end

    for i = 1:nf
        for j = 1:nf
            (Qa[i,j] == 0.0) ? Qa[i,j] = 0.00000000000001 : Qa[i,j] = Qa[i,j]
        end
    end   
    
    #Get the eigen vector of unity eigenvalue by power method
    λ, x = powm!(transpose(Qa), rand(nf), maxiter = 1000,tol = 1e-10)
    #@show λ
    #renormalize eigen vector so it adds up to one by state
    for i = 1:nf
        pdf1[i] = 1.0/sum(x) * x[i]
    end

    EA = 0.0
    for s = 1:ns
        for ki = 1:NumberOfHouseholds
            i = (s-1)*NumberOfHouseholds + ki
            EA += pdf1[i]*res[ki]            
        end
    end

    res,EA,pdf1
end






function equilibrium(
    FiniteElementObj::AyiagariMarkovianFiniteElement{R,I},
    tol = 1e-10,maxn = 100
) where{R <: Real,I <: Integer}

    @unpack β,d,A,B_,γc,γl,α,T,ζ = FiniteElementObj.Parameters  
    @unpack nodes,na,m,wx,ax = FiniteElementObj.FiniteElement  
    @unpack states,ns,stateID,Π = FiniteElementObj.MarkovChain
    @unpack DistributionSize, DistributionAssetGrid = FiniteElementObj.Distribution
    ull,ucc,uc,∂l∂L = 0.0,0.0,0.0,0.0
    
    #@unpack β,α,δ,μ,σ,ρ,ζ = FiniteElementObj.Parameters
    #nodes = FiniteElementObj.Nodes
    #Π = FiniteElementObj.TransitionMatrix
    #states = FiniteElementObj.IndividualStates
    #na = FiniteElementObj.NumberOfNodes
    #ns = FiniteElementObj.NumberOfIndividualStates
    #nx,ns = 20,FiniteElementObj.NumberOfIndividualStates
    
    #Bisection method for equilibrium
    #cm_ir =  #complete markets interest rate

    cpol = zeros(R,DistributionSize,ns)
    lpol = zeros(R,DistributionSize,ns)
    appol = zeros(R,DistributionSize,ns)
    AssetDistribution = zeros(DistributionSize*ns)
    #Demand = zeros(nx)
    #Supply = zeros(nx)
    #θeq = zeros(ns*na) 
    capeq = 0.0
    EA = 0.0
    #_,EA,_ = StationaryDistribution(r0,θ_eq,DistributionSize)
    #Residual, dResidual = zeros(na*ns), zeros(na*ns,na*ns)
    
    ###Start Bisection
    L = 0.25  #labor demand guess
    K = 0.0
    θeq = FiniteElementObj.Guess
    #uir,lir = (1.0/β-1.0), 0.001
    #r0 = lir
    
    
    for lit = 1:maxn
        uir,lir = (1.0/β-1.0), 0.001
        r0 = lir
        for kit = 1:maxn
            println("r0: ",r0," L: ",L)
            θeq = SolveFiniteElement(r0,θeq,FiniteElementObj)
            _,EA,AssetDistribution = StationaryDistribution(r0,θeq,FiniteElementObj)

            ### Implicit interest rate
            rd = α*T*EA^(α - 1.0)*L^(1.0-α) - d


            ### narrow interval by updating upper and lower bounds on 
            ### interval to search new root
            if (rd > r0)
                 r = 1.0/2.0*(min(uir,rd) + max(lir,r0))
                 uir = min(uir,rd)
                 lir = max(lir,r0)
            else
                 r = 1.0/2.0*(min(uir,r0) + max(lir,rd))
                 lir = max(lir,rd)
                 uir = min(uir,r0)
            end

            #println("irtest: ",r0," impliedir: ",rd)
            if abs(r - r0) < 0.0000000000001
                println("irtest: ",r0," impliedir: ",rd)
                K = EA
                r0 = r
                break
            end
            r0 = r
        end
        r = r0
        w = (1.0-α)*T*((T*α)/(r+d))^(α/(1.0-α))
        ∂r∂L = α*(1.0-α)*T*K^(α-1.0)*L^(-α)
        ∂w∂L = (1.0-α)*(-α)*T*K^α*L^(-α-1.0)
        ∂Ls∂L = 0.0
        Ls,f,df = 0.0,0.0,0.0
        θ = reshape(θeq,na,ns)
        for s=1:ns
            ϵ = states[s]
            for i=1:NumberOfHouseholds
                x = DistributionAssetGrid[i]

                ######
                # find each k in dist grid in nodes to use FEM solution
                ######
                n = searchsortedlast(nodes,x)
                (n > 0 && n < na) ? n = n : 
                    (n == na) ? n = na-1 : 
                        n = 1 
                x1,x2 = nodes[n],nodes[n+1]
                basis1 = (x2 - x)/(x2 - x1)
                basis2 = (x - x1)/(x2 - x1)
                ap  = basis1*θ[n,s] + basis2*θ[n+1,s]
                l,c = 0.5,0.0
                for j = 1:100
                    c = (1.0 + r)*x + ϵ*w*(1.0 - l) - ap
                    ∂c∂l = -ϵ*w
                    ∂c∂a = 1.0
                    ul = A*l^(-γl)
                    ull = -γl*A*l^(-γl - 1.0)
                    uc = c^(-γc)
                    ucc = -γc*c^(-γc - 1.0)                    
                    mrs = ul - w*ϵ*uc - ζ*min(1.0 - l,0.0)^2
                    dmrs = ull - w*ϵ*ucc*∂c∂l + 2.0*ζ*min(1.0 - l,0.0)
                    l += -1.0 * mrs/dmrs
                    if abs(mrs/dmrs) < 1e-10
                        break
                    end
                end
                cpol[i,s] = c 
                lpol[i,s] = 1.0-l
                appol[i,s] = ap

                ## find root of f(L) = ∑P(i)(1-l)ϵ[s] - L = Ls - L
                Ls += AssetDistribution[NumberOfHouseholds*(s-1)+i]*(1.0-l)*ϵ
                ∂l∂L = (∂w∂L*ϵ*uc + w*ϵ*ucc*((1.0-l)*ϵ*∂w∂L + ∂r∂L*x))/(ull + (w*ϵ)^2.0*ucc + 2.0*ζ*min(1.0 - l,0.0))
                ∂Ls∂L += -AssetDistribution[NumberOfHouseholds*(s-1)+i]*ϵ*∂l∂L
            end
        end
        df = ∂Ls∂L - 1.0
        @show f = Ls - L
        step = -f/df
        L += step
        if abs(step)< 1e-5
            return θeq,w,r,L,K,cpol,lpol,appol,AssetDistribution
            break
        end
    end
    
    return println("Markets did not clear")
end 

function PlotEquilibrium(
    EquilibriumIR::R,
    FiniteElementObj::AyiagariMarkovianFiniteElement{R,I}
) where{R <: Real,I <: Integer}

    @unpack β,α,δ,μ,σ,ρ,ζ = FiniteElementObj.Parameters
    nx = 30
    Supply = zeros(nx)
    Demand = zeros(nx)
    θ0 = FiniteElementObj.Guess
    #Get a sequence of asset demand and supply for display
    ir  = collect(range(0.7*EquilibriumIR,stop=1.3*EquilibriumIR,length=nx))
    for i = 1:nx
        r = ir[i]
        θ0 =  SolveFiniteElement(r,θ0,FiniteElementObj)
        _,EA,_ = StationaryDistribution(r,θ0,FiniteElementObj)
        Supply[i] = EA
        Demand[i] = ((r + δ)/α)^(1.0/(α - 1.0))
    end

    return Demand,Supply
end
    

