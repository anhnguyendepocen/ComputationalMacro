using LinearAlgebra
using Parameters
using IterativeSolvers
using Plots
using BenchmarkTools
using FastGaussQuadrature
using BenchmarkTools
using ForwardDiff
using QuantEcon
using GLM

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
    homeY::R
    hfix::R
end

struct ModelFiniteElement{R <: Real,I <: Integer}
    elements::Array{R,2}
    elementsID::Array{I,2}
    kGrid::Array{R,1}
    KGrid::Array{R,1}
    m::I
    wx::Array{R,1}
    ax::Array{R,1}
    nk::I
    nK::I
    ne::I
end

struct ModelMarkovChain{R <: Real,I <: Integer}
    states::Array{R,2}
    statesID::Array{I,2}
    aggstatesID::Array{I,1}
    ns::I #number of states
    nis::I #number of individual states
    nas::I #number of aggregate state
    πz::Array{R,2} #aggregate transition
    Π::Array{R,2}
    IndStates::Array{R,1}
    AggStates::Array{R,1}
    LoML::Array{R,1}
end

struct ModelDistribution{R <: Real,I <: Integer}
    DistributionSize::I
    DistributionAssetGrid::Array{R,1}
    InitialDistribution::Array{R,2}
    AggShocks::Array{I,1}
    TimePeriods::I
    P00::Array{R,2}
    P01::Array{R,2}
    P10::Array{R,2}
    P11::Array{R,2}
end


struct KSMarkovianFiniteElement{R <: Real,I <: Integer}
    Guess::Array{R,1}
    GuessM::Array{R,2}
    LoMK::Array{R,2}    
    Parameters::ModelParameters{R}
    FiniteElement::ModelFiniteElement{R,I}
    MarkovChain::ModelMarkovChain{R,I}
    Distribution::ModelDistribution{R,I}
end

"""
Construct and Ayiagari model instace of all parts needed to solve the model
"""
function KSModel(
    UnempDurG::R = 1.5,
    UnempDurB::R = 2.5,
    Corr::R = 0.25,
    UnempG::R = 0.04,
    UnempB::R = 0.1,
    DurZG::R = 8.0,
    DurZB::R = 8.0,
    nk::I = 30, #asset grid size
    kMax::R = 100.0, #uppper bound on capital
    nK::I = 5, #aggregate capital grid size
    KMax::R = 12.5, #upper bound on aggregate capital
    KMin::R = 10.5,
    gZ::R = 1.01,
    bZ::R = 0.99,
    empS::R = 1.0,
    unempS::R = 0.0,
    β::R = 0.99,
    d::R = 0.025,
    A::R = 1.0,
    γc::R = 1.0,
    γl::R = 1.0,
    α::R = 0.36,
    T::R = 1.0,
    ζ::R = 10000000000.0,
    homeY::R = 0.07,
    hfix::R = 0.3271,
    B_::R = 0.0,
    Kg1::R =0.09,
    Kg2::R =0.96,
    Kb1::R =0.08,
    Kb2::R =0.96,
    NumberOfHouseholds::I = 700,
    TimePeriods::I = 8000,
    DistributionUL::R = 100.0,
    NumberOfQuadratureNodesPerElement::I = 2
) where{R <: Real,I <: Integer}

    ###################################################
    ################   Stochastic process #############
    ###################################################
    # unemployment rates depend only on the aggregate productivity shock
    Unemp = [UnempG;UnempB]
    
    # probability of remaining in 'Good/High' productivity state
    πzg = 1.0 - 1.0/DurZG
    
    # probability of remaining in the 'Bad/Low' productivity state
    πzb = 1.0 - 1.0/DurZB
    
    # matrix of transition probabilities for aggregate state
    πz = [πzg 1.0-πzg;
          1.0-πzb πzb]
    
    # transition probabilities between employment states when aggregate productivity is high
    p22 = 1.0 - 1.0 / UnempDurG
    p21 = 1.0 - p22
    p11 = (((1.0 - UnempG) - UnempG * p21) / (1.0 - UnempG))
    #       e    u   for good to good
    P11 = [p11 1.0-p11; 
           p21 p22]
    
    # transition probabilities between employment states when aggregate productivity is low
    p22 = 1.0 - 1.0 / UnempDurB
    p21 = 1.0 - p22
    p11 = (((1.0 - UnempB) - UnempB * p21) / (1.0 - UnempB))
    #       e    u   for bad to bad
    P00 = [p11 1.0-p11; 
           p21 p22] 
    
    # transition probabilities between employment states when aggregate productivity is high
    p22 = (1.0 + Corr) * p22
    p21 = 1.0 - p22
    p11 = (((1.0 - UnempB) - UnempG * p21) / 
           (1.0 - UnempG))
    #       e    u   for good to bad
    P10 = [p11 1.0-p11; 
           p21 p22]

    p22 = (1.0 - Corr) * (1.0 - 1.0 / UnempDurG)
    p21 = 1.0 - p22
    p11 = (((1.0 - UnempG) - UnempB * p21) / 
           (1.0 - UnempB))
    #       e    u   for bad to good
    P01 = [p11 1.0-p11; 
           p21 p22]

    P = [πz[1,1]*P11 πz[1,2]*P10;
         πz[2,1]*P01 πz[2,2]*P00]
    
    #states = [1.01 1.0;1.01 0.1;0.99 1.0;0.99 0.1]
    states = [gZ empS;gZ unempS;bZ empS;bZ unempS] #krusell
    statesID = [1 1;1 2;2 1; 2 2]
    aggstatesID = [1;1;2;2]
    ns = size(states,1)

    LoMK = [Kg1 Kg2;
            Kb1 Kb2]
    #aggL = [0.3271*(1.0-UnempG);0.3271*(1.0-UnempB)]
    LoML = [hfix*(1.0-UnempG);
            hfix*(1.0-UnempB)]
    nis,nas = 2,2
    KSMarkovChain = ModelMarkovChain(states,statesID,aggstatesID,ns,nis,nas,πz,P,[empS;unempS],[gZ;bZ],LoML)
    

    ##########################################################
    ############### Mesh generation ##########################
    ##########################################################
    function grid_fun(a_min,a_max,na, pexp)
        x = range(a_min,step=0.5,length=na)
        grid = a_min .+ (a_max-a_min)*(x.^pexp/maximum(x.^pexp))
        return grid
    end
    kGrid = grid_fun(0.0,kMax,nk,5.0)
    #kGrid = collect(range(0.0,stop = KMax,length=nk))
    KGrid = collect(range(KMin,stop = KMax,length=nK))
    #LGrid = range(LMin,stop = LMax,length=nL)
    nkK = nk*nK

    ne = (nk-1)*(nK-1)               #number of elements
    nv = 4                                  #number of values by element (k1,k2,K1,K2,L1,L2)
    
    ElementsID = zeros(I,ne,nv) #element indices
    Elements = zeros(R,ne,nv) #elements

    for ki = 1:nk-1 #across ind k
        for Ki = 1:nK-1 #across agg L
            n = (ki-1)*(nK-1) + Ki  
            ElementsID[n,1],ElementsID[n,2] = ki,ki+1
            ElementsID[n,3],ElementsID[n,4] = Ki,Ki+1
            Elements[n,1],Elements[n,2] = kGrid[ki],kGrid[ki+1]
            Elements[n,3],Elements[n,4] = KGrid[Ki],KGrid[Ki+1]
        end
    end
    QuadratureAbscissas,QuadratureWeights = gausslegendre(NumberOfQuadratureNodesPerElement)

    KSFiniteElement = ModelFiniteElement(Elements,ElementsID,kGrid,KGrid,NumberOfQuadratureNodesPerElement,QuadratureWeights,QuadratureAbscissas,nk,nK,ne)

    #return KSMC, Elements, ElementID
    Guess = zeros(R,nkK*ns)    
    for s=1:ns
        z,ϵ = states[s,1],states[s,2]
        L = LoML[aggstatesID[s]] 
        for (ki,k) in enumerate(kGrid) #ind k
            for (Ki,K) in enumerate(KGrid) #agg k
                ##forecast labor
                #L = exp(Lb0 + Lb1*log(K))
                #println("ki: ",ki," Ki: ",Ki," Li: ",Li)
                n = (s-1)*nkK + (ki-1)*nK + Ki
                r = α*z*T*K^(α-1.0)*L^(1.0-α) - d
                w = (1.0-α)*T*z*K^(α)*L^(-α)
                kp = (1.0 + r)*k + w*ϵ*hfix + (1.0 -ϵ)*homeY  - 0.5
                kp > 0.0 ? Guess[n] = 15.0/16.0*kp : Guess[n] =  1.0/2.0*kp 
            end
        end
    end
    GuessM = reshape(Guess,nkK,ns)

    ################### Distribution pieces
    #Grid on distribution
    DistributionAssetGrid = collect(range(kGrid[1],stop = DistributionUL,length = NumberOfHouseholds))

    #choose uniform distribution

    InitialDistribution = rand(nis*NumberOfHouseholds)
    InitialDistribution = InitialDistribution/sum(InitialDistribution)
    InitialDistribution = reshape(InitialDistribution,NumberOfHouseholds,nis)

    #simulate time series
    mc = MarkovChain(πz, [1, 2])
    AggShocks = simulate(mc,TimePeriods,init=1)

    #Define KS distribution object
    KSDistribution = ModelDistribution(NumberOfHouseholds,DistributionAssetGrid,InitialDistribution,AggShocks,TimePeriods,P00,P01,P10,P11)

    KSParameters = ModelParameters(β,d,A,B_,γc,γl,α,T,ζ,homeY,hfix)
    
    KSMarkovianFiniteElement(Guess,GuessM,LoMK,KSParameters,KSFiniteElement,KSMarkovChain,KSDistribution)
end



function WeightedResidual(
    θ::Array{F,1},
    LoMK::Array{R,2},
    FiniteElementObj::KSMarkovianFiniteElement{R,I}) where{R <: Real,I <: Integer,F <: Real}

    @unpack β,d,A,B_,γc,γl,α,T,ζ,homeY,hfix = FiniteElementObj.Parameters  
    @unpack elements,elementsID,kGrid,KGrid,m,wx,ax,nk,nK,ne = FiniteElementObj.FiniteElement  
    @unpack states,IndStates,AggStates,statesID,aggstatesID,ns,nis,nas,πz,Π,LoML = FiniteElementObj.MarkovChain  
    l,c,uc,ucc,ul,ull,∂c∂a,∂c∂l,∂l∂ai,∂c∂ai,∂l∂aj,∂c∂aj = 0.5,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    lp,cp,ucp,uccp,ulp,ullp,∂cp∂ap = 0.5,0.0,0.0,0.0,0.0,0.0,0.0
    
    nkp = 0
    np = 0    
    
    #Dimension of the problem
    nkK = nk*nK
    nx = ns*nkK
    mk,mK = m,m
    Res  = zeros(F,nx) 
    dr = zeros(F,nx,nx)
    for s = 1:ns #for each state in the state space
        z,ϵ = states[s,1],states[s,2]
        L = LoML[aggstatesID[s]] 
        Kb0,Kb1 = LoMK[aggstatesID[s],1], LoMK[aggstatesID[s],2] 
        for n=1:ne #for each element in the finite element mesh
            k1,k2 = elements[n,1],elements[n,2]
            K1,K2 = elements[n,3],elements[n,4]
            ki,Ki = elementsID[n,1],elementsID[n,3] #indices of endog states for policy

            ### NOTE: these indices keep track of which elements solution depends on
            s1,s4 = (s-1)*nkK + (ki-1)*nK + Ki, (s-1)*nkK + (ki-1)*nK + Ki + 1
            s2,s3 = (s-1)*nkK + ki*nK + Ki, (s-1)*nkK + ki*nK + Ki + 1
            for mki = 1:mk #integrate across k
                k = (k1 + k2)/2.0 + (k2 - k1)/2.0 * ax[mki] #use Legendre's rule
                kv = (k2-k1)/2.0*wx[mki]
                for mKi = 1:mK #integrate across k̄
                    K = (K1 + K2)/2.0 + (K2 - K1)/2.0 * ax[mKi] #use Legendre's rule
                    Kv = (K2-K1)/2.0*wx[mKi]

                    #Get functions of agg variables
                    r = α*z*T*(K/L)^(α-1.0) - d 
                    w = (1.0-α)*z*T*(K/L)^α

                    #Form basis for piecewise function
                    basis1 = (k2 - k)/(k2 - k1) * (K2 - K)/(K2 - K1)
                    basis2 = (k - k1)/(k2 - k1) * (K2 - K)/(K2 - K1)
                    basis3 = (k - k1)/(k2 - k1) * (K - K1)/(K2 - K1)
                    basis4 = (k2 - k)/(k2 - k1) * (K - K1)/(K2 - K1)
                  
                    #Policy functions 
                    kp = θ[s1]*basis1 + θ[s2]*basis2 + 
                             θ[s3]*basis3 + θ[s4]*basis4
                    
                    c = (1.0 + r)*k + ϵ*w*hfix + (1.0 - ϵ)*homeY  - kp
                    pen = ζ*min(kp,0.0)^2
                    dpen = 2.0*ζ*min(kp,0.0)                    

                    uc = c^(-γc)
                    ucc = -γc*c^(-γc - 1.0)                    
                    ∂c∂ki = -1.0

                    #LOM for agg capital 
                    Kp = exp(Kb0 + Kb1*log(K))

                    #Find the element it belongs to
                    for i = 1:ne
                        if (kp>=elements[i,1] && kp<=elements[i,2]) 
                            nkp = i     
                            break
                        elseif kp<elements[1,1]
                            nkp = 1
                            break
                        else
                            nkp = ne-nk
                        end
                    end
                    # Find the aggregate state and adjust if it falls outside the grid
                    for j = nkp:nkp+nK-2
                        if (Kp >= elements[j,3] && Kp <= elements[j,4]) 
                            np = j     
                            break
                        elseif Kp < elements[nkp,3]
                            np = nkp
                            break
                        else
                            np = nkp+nK-2
                        end
                    end
                    
                    kp1,kp2 = elements[np,1],elements[np,2]
                    Kp1,Kp2 = elements[np,3],elements[np,4]
                    kpi,Kpi = elementsID[np,1],elementsID[np,3] #indices of endog states for policy

                    basisp1 = (kp2 - kp)/(kp2 - kp1) * (Kp2 - Kp)/(Kp2 - Kp1)
                    basisp2 = (kp - kp1)/(kp2 - kp1) * (Kp2 - Kp)/(Kp2 - Kp1)
                    basisp3 = (kp - kp1)/(kp2 - kp1) * (Kp - Kp1)/(Kp2 - Kp1)
                    basisp4 = (kp2 - kp)/(kp2 - kp1) * (Kp - Kp1)/(Kp2 - Kp1)

                    ####### Store derivatives###############
                    dbasisp1 = -1.0/(kp2 - kp1) * (Kp2 - Kp)/(Kp2 - Kp1) 
                    dbasisp2 =  1.0/(kp2 - kp1) * (Kp2 - Kp)/(Kp2 - Kp1)
                    dbasisp3 =  1.0/(kp2 - kp1) * (Kp - Kp1)/(Kp2 - Kp1)
                    dbasisp4 = -1.0/(kp2 - kp1) * (Kp - Kp1)/(Kp2 - Kp1)

                    tsai = 0.0
                    sum1 = 0.0 
                    for sp = 1:ns 
                        sp1,sp4 = (sp-1)*nkK + (kpi-1)*nK + Kpi, (sp-1)*nkK + (kpi-1)*nK + Kpi + 1
                        sp2,sp3 = (sp-1)*nkK + kpi*nK + Kpi, (sp-1)*nkK + kpi*nK + Kpi + 1
                        zp,ϵp = states[sp,1],states[sp,2]

                        Lp = LoML[aggstatesID[sp]]
                        
                        #Get functions of agg variables
                        rp = α*zp*T*(Kp/Lp)^(α-1.0) - d
                        wp = (1.0-α)*zp*T*(Kp/Lp)^α

                        #Policy functions
                        kpp = θ[sp1]*basisp1 + θ[sp2]*basisp2 + 
                                  θ[sp3]*basisp3 + θ[sp4]*basisp4

                        cp = (1.0 + rp)*kp + ϵp*wp*hfix + (1.0 - ϵp)*homeY - kpp

                        ucp = cp^(-γc)
                        uccp = -γc*cp^(-γc - 1.0)                    

                        ∂kpp∂ki = θ[sp1]*dbasisp1 + θ[sp2]*dbasisp2 +
                            θ[sp3]*dbasisp3 + θ[sp4]*dbasisp4
                        ∂cp∂ki = (1.0 + rp) - ∂kpp∂ki 
                        ∂cp∂kj = -1.0
                        sum1 += β*Π[s,sp]*((1.0 + rp)*ucp + pen) 

                        #derivatives of kp have θi associated with kp
                        tsai += β*Π[s,sp]*((1.0 + rp)*uccp*∂cp∂ki + dpen)
                        
                        #derivatives of kpp wrt kp have θj associated with kpp
                        tsaj = β*Π[s,sp]*(1.0 + rp)*uccp*∂cp∂kj 

                        dr[s1,sp1] +=  basis1 * kv * Kv * tsaj * basisp1
                        dr[s1,sp2] +=  basis1 * kv * Kv * tsaj * basisp2
                        dr[s1,sp3] +=  basis1 * kv * Kv * tsaj * basisp3
                        dr[s1,sp4] +=  basis1 * kv * Kv * tsaj * basisp4
                        dr[s2,sp1] +=  basis2 * kv * Kv * tsaj * basisp1
                        dr[s2,sp2] +=  basis2 * kv * Kv * tsaj * basisp2
                        dr[s2,sp3] +=  basis2 * kv * Kv * tsaj * basisp3
                        dr[s2,sp4] +=  basis2 * kv * Kv * tsaj * basisp4
                        dr[s3,sp1] +=  basis3 * kv * Kv * tsaj * basisp1
                        dr[s3,sp2] +=  basis3 * kv * Kv * tsaj * basisp2
                        dr[s3,sp3] +=  basis3 * kv * Kv * tsaj * basisp3
                        dr[s3,sp4] +=  basis3 * kv * Kv * tsaj * basisp4
                        dr[s4,sp1] +=  basis4 * kv * Kv * tsaj * basisp1
                        dr[s4,sp2] +=  basis4 * kv * Kv * tsaj * basisp2
                        dr[s4,sp3] +=  basis4 * kv * Kv * tsaj * basisp3
                        dr[s4,sp4] +=  basis4 * kv * Kv * tsaj * basisp4

                    end
                    #add the LHS and RHS of euler for each s wrt to θi
                    dres =  tsai - ucc*∂c∂ki 

                    dr[s1,s1] +=  basis1 * kv * Kv * dres * basis1
                    dr[s1,s2] +=  basis1 * kv * Kv * dres * basis2
                    dr[s1,s3] +=  basis1 * kv * Kv * dres * basis3
                    dr[s1,s4] +=  basis1 * kv * Kv * dres * basis4
                    dr[s2,s1] +=  basis2 * kv * Kv * dres * basis1
                    dr[s2,s2] +=  basis2 * kv * Kv * dres * basis2
                    dr[s2,s3] +=  basis2 * kv * Kv * dres * basis3
                    dr[s2,s4] +=  basis2 * kv * Kv * dres * basis4
                    dr[s3,s1] +=  basis3 * kv * Kv * dres * basis1
                    dr[s3,s2] +=  basis3 * kv * Kv * dres * basis2
                    dr[s3,s3] +=  basis3 * kv * Kv * dres * basis3
                    dr[s3,s4] +=  basis3 * kv * Kv * dres * basis4
                    dr[s4,s1] +=  basis4 * kv * Kv * dres * basis1
                    dr[s4,s2] +=  basis4 * kv * Kv * dres * basis2
                    dr[s4,s3] +=  basis4 * kv * Kv * dres * basis3
                    dr[s4,s4] +=  basis4 * kv * Kv * dres * basis4

                    res = sum1 - uc
                    Res[s1] += basis1 * kv * Kv * res
                    Res[s2] += basis2 * kv * Kv * res  
                    Res[s3] += basis3 * kv * Kv * res 
                    Res[s4] += basis4 * kv * Kv * res 
                end
            end
        end
    end
   Res,dr
end


function SolveFiniteElement(
    guess::Array{R,1},
    LoMK::Array{R,2},
    FiniteElementObj::KSMarkovianFiniteElement{R,I},
    maxn::Int64 = 400,
    tol = 1e-10
) where{R <: Real,I <: Integer}

    nk =  FiniteElementObj.FiniteElement.nk
    nK = FiniteElementObj.FiniteElement.nK
    ns = FiniteElementObj.MarkovChain.ns
    nx = nk*nK*ns
    θ = guess
    #Newton Iteration
    for i = 1:maxn
        Res,dRes = WeightedResidual(θ,LoMK,FiniteElementObj)
        #dRes = ForwardDiff.jacobian(t -> WeightedResidual(t,LoMK,FiniteElementObj)[1],θ)
        step = - dRes \ Res
        if LinearAlgebra.norm(step) > 1.0
            θ += 1.0/10.0*step
        else
            θ += 1.0/1.0*step
        end
        LinearAlgebra.norm(step)
        if LinearAlgebra.norm(step) < tol
            return θ
            break
        end
    end
    return println("Individual policy Did not converge")
end


function NextPeriodDistribution(
    Φ::Array{R,2},
    LoMK::Array{R,2},
    AggStateToday::I,
    AggStateTomorrow::I,
    θ::Array{F,1},
    FiniteElementObj::KSMarkovianFiniteElement{R,I}) where{R <: Real,I <: Integer,F <: Real}

    @unpack elements,elementsID,nk,nK,ne = FiniteElementObj.FiniteElement  
    @unpack states,IndStates,AggStates,statesID,aggstatesID,ns,nis,nas,Π =FiniteElementObj.MarkovChain 
    @unpack DistributionSize,DistributionAssetGrid,TimePeriods = FiniteElementObj.Distribution

    #some helpful parameters
    nkK = nk*nK
    
    K = sum(Φ[:,1] .* DistributionAssetGrid) + sum(Φ[:,2] .* DistributionAssetGrid)
    L = LoML[AggStateToday]
    z  = ifelse(AggStateToday == 1, [1,2], [3,4])
    zp = ifelse(AggStateTomorrow == 1, [1,2], [3,4])
    Πz = Π[z,zp]
    nki=0
    n=0

    Φp = fill(0.0,size(Φ))
    for (is,ϵ) = enumerate(IndStates)
        (is == 1 && AggStateToday == 1) ? s = 1 :
            (is == 2 && AggStateToday == 1) ? s = 2 :
                (is == 1 && AggStateToday == 2) ? s = 3 : s = 4
        for (ki,k) in enumerate(DistributionAssetGrid)
            #Find the element it belongs to
            for i = 1:ne
                if (k>=elements[i,1] && k<=elements[i,2]) 
                    nki = i     
                    break
                elseif k<elements[1,1]
                    nki = 1
                    break
                else
                    nki = ne-nk
                end
            end
            # Find the aggregate state and adjust if it falls outside the grid
            for j = nki:nki+nK-2
                if (K >= elements[j,3] && K <= elements[j,4]) 
                    n = j     
                    break
                elseif K < elements[nki,3]
                    n = nki
                    break
                else
                    n = nki+nK-2
                end
            end
            k1,k2 = elements[n,1],elements[n,2]
            K1,K2 = elements[n,3],elements[n,4]
            kii,Ki = elementsID[n,1],elementsID[n,3] #indices of endog states for policy
            s1,s4 = (s-1)*nkK + (kii-1)*nK + Ki, (s-1)*nkK + (kii-1)*nK + Ki + 1
            s2,s3 = (s-1)*nkK + kii*nK + Ki, (s-1)*nkK + kii*nK + Ki + 1

            basis1 = (k2 - k)/(k2 - k1) * (K2 - K)/(K2 - K1)
            basis2 = (k - k1)/(k2 - k1) * (K2 - K)/(K2 - K1)
            basis3 = (k - k1)/(k2 - k1) * (K - K1)/(K2 - K1)
            basis4 = (k2 - k)/(k2 - k1) * (K - K1)/(K2 - K1)

            #Policy functions 
            kp = θ[s1]*basis1 + θ[s2]*basis2 + θ[s3]*basis3 + θ[s4]*basis4
            np = searchsortedlast(DistributionAssetGrid,kp)
            if (np > 0) && (np < DistributionSize)
                h1 = DistributionAssetGrid[np]
                h2 = DistributionAssetGrid[np+1]
            end

            
            Πtot = Πz[is,1]+Πz[is,2]
            if np == 0
                Φp[np+1,1] += (Πz[is,1]/Πtot)*Φ[ki,is]  ##1st employed agent 
                Φp[np+1,2] += (Πz[is,2]/Πtot)*Φ[ki,is] #1st unemployed agent
            elseif np == DistributionSize
                Φp[np,1] += (Πz[is,1]/Πtot)*Φ[ki,is]
                Φp[np,2] += (Πz[is,2]/Πtot)*Φ[ki,is]
            else
                # status is kp, employed
                ω = 1.0 - (kp-h1)/(h2-h1)
                Φp[np,1] += (Πz[is,1]/Πtot)*ω*Φ[ki,is]
                Φp[np+1,1] += (Πz[is,1]/Πtot)*(1.0 - ω)*Φ[ki,is]
                # status is kp, unemployed
                Φp[np,2] += (Πz[is,2]/Πtot)*ω*Φ[ki,is]
                Φp[np + 1,2] += (Πz[is,2]/Πtot)*(1.0 - ω)*Φ[ki,is]
            end
        end
    end
    return Φp
end


function KSEquilibrium(FiniteElementObj::KSMarkovianFiniteElement{R,I}) where{R <: Real,I <: Integer,F <: Real}

    @unpack DistributionAssetGrid,InitialDistribution,AggShocks,TimePeriods = FiniteElementObj.Distribution

    #Bs = fill(0.0, (IterationSize,4))
    Rsqrd = fill(0.0, (2,))
    n_discard = 500

    
    #Initial guess
    LoMK = FiniteElementObj.LoMK
    θ0 = FiniteElementObj.Guess
    FullGrid = vcat(DistributionAssetGrid,DistributionAssetGrid)
    θ0 = SolveFiniteElement(θ0,LoMK,FiniteElementObj)
    
    #Initial distribution and average capital
    Φ = InitialDistribution
    for i = 1:(TimePeriods-1)  
        Φ = NextPeriodDistribution(Φ,LoMK,AggShocks[i],AggShocks[i+1],pol,FiniteElementObj)
    end
    for i = 1:100
        Ks = fill(0.0, (TimePeriods,))
        Ks[1] = Ks[1] = dot(Φ,FullGrid)
        @show LoMK
        #solve individual problem
        θ0 = SolveFiniteElement(θ0,LoMK,KS)
        for t = 2:TimePeriods
            Φ = NextPeriodDistribution(Φ,LoMK,AggShocks[t-1],AggShocks[t],θ0,FiniteElementObj)
            Ks[t] = dot(Φ,FullGrid)
        end
        @show Ks[TimePeriods]
        ###Get indices of agg states
        n_g=count(i->(i==1),AggShocks[n_discard+1:end-1]) #size of data with good periods after discard
        n_b=count(i->(i==2),AggShocks[n_discard+1:end-1]) #size of data with bad periods after discard
        x_g=Vector{Float64}(n_g) #RHS of good productivity reression
        y_g=Vector{Float64}(n_g) #LHS of good productivity reression
        x_b=Vector{Float64}(n_b) #RHS of bad productivity reression
        y_b=Vector{Float64}(n_b) #LHS of bad productivity reression
        i_g=0
        i_b=0
        for t = n_discard+1:length(AggShocks)-1
            if AggShocks[t]==1
                i_g=i_g+1
                x_g[i_g]=log(Ks[t])
                y_g[i_g]=log(Ks[t+1])
            else
                i_b=i_b+1
                x_b[i_b]=log(Ks[t])
                y_b[i_b]=log(Ks[t+1])
            end
        end

        resg=lm(hcat(ones(n_g,1),x_g),y_g)
        resb=lm(hcat(ones(n_b,1),x_b),y_b)
        
        LoMKnew = fill(0.0,size(LoMK))
        @show Rsqrd[1]= r2(resg)
        @show Rsqrd[2]= r2(resb)
        @show LoMKnew[1,:] = coef(resg)
        @show LoMKnew[2,:] = coef(resb)
        if  LinearAlgebra.norm(LoMKnew - LoMK,Inf) < 0.000001
            println("Equilibrium found")
            return θ0, LoMK, Ks, Φ
            break
        else
            @show LoMK[1,:] = 0.3*LoMKnew[1,:] + 0.7*LoMK[1,:]
            @show LoMK[2,:] = 0.3*LoMKnew[2,:] + 0.7*LoMK[2,:]
        end
        println("LoM updated")
    end    
end

function Policies(
    kStream::Array{R,1},
    K::R,
    θ::Array{F,1},
    LoMK::Array{R,2},
    FiniteElementObj::KSMarkovianFiniteElement{R,I}) where{R <: Real,I <: Integer,F <: Real}

    @unpack β,d,A,B_,γc,γl,α,T,ζ = FiniteElementObj.Parameters  
    @unpack elements,elementsID,kGrid,KGrid,m,wx,ax,nk,nK,ne = FiniteElementObj.FiniteElement  
    @unpack states,IndStates,AggStates,statesID,aggstatesID,ns,nis,nas,πz,Π,LoML =FiniteElementObj.MarkovChain 

    #some helpful parameters
    nkK = nk*nK    

    #policies
    cPol = fill(0.0,(length(kStream),ns))
    kpPol = fill(0.0,(length(kStream),ns))
    


    nki=0
    n=0    
    for s = 1:ns
        z,ϵ = states[s,1],states[s,2]
        L = LoML[aggstatesID[s]] 
        Kb0,Kb1 = LoMK[aggstatesID[s],1], LoMK[aggstatesID[s],2] 
        for (ki,k) in enumerate(kStream)
            for i = 1:ne
                if (k>=elements[i,1] && k<=elements[i,2]) 
                    nki = i     
                    break
                elseif k<elements[1,1]
                    nki = 1
                    break
                else
                    nki = ne-nk
                end
            end
            # Find the aggregate state and adjust if it falls outside the grid
            for j = nki:nki+nK-2
                if (K >= elements[j,3] && K <= elements[j,4]) 
                    n = j     
                    break
                elseif K < elements[nki,3]
                    n = nki
                    break
                else
                    n = nki+nK-2
                end
            end
            k1,k2 = elements[n,1],elements[n,2]
            K1,K2 = elements[n,3],elements[n,4]
            kii,Ki = elementsID[n,1],elementsID[n,3] #indices of endog states for policy
            s1,s4 = (s-1)*nkK + (kii-1)*nK + Ki, (s-1)*nkK + (kii-1)*nK + Ki + 1
            s2,s3 = (s-1)*nkK + kii*nK + Ki, (s-1)*nkK + kii*nK + Ki + 1

            basis1 = (k2 - k)/(k2 - k1) * (K2 - K)/(K2 - K1)
            basis2 = (k - k1)/(k2 - k1) * (K2 - K)/(K2 - K1)
            basis3 = (k - k1)/(k2 - k1) * (K - K1)/(K2 - K1)
            basis4 = (k2 - k)/(k2 - k1) * (K - K1)/(K2 - K1)

            #Policy functions 
            kp = θ[s1]*basis1 + θ[s2]*basis2 + θ[s3]*basis3 + θ[s4]*basis4

            r = α*z*T*(K/L)^(α-1.0) - d 
            w = (1.0-α)*z*T*(K/L)^α

            c = (1.0 + r)*k + ϵ*w  - kp

            cPol[ki,s] = c
            kpPol[ki,s] = kp
        end
    end

    return cPol,kpPol
end


KS = KSModel(1.5,2.5,0.25,0.04,0.1,8.0,8.0,30,100.0,5,12.5,10.5,1.01,0.99,1.0,0.0,0.99,0.025,1.0,1.0,1.0,0.36,1.0,10000000000.0,0.07,0.3271,0.0,0.09,0.96,0.08,0.96,700,8000,100.0,2)

##################### Model pices
LoMK = KS.LoMK
Guess = KS.Guess
ns = KS.MarkovChain.ns
nk,nK = KS.FiniteElement.nk,KS.FiniteElement.nK
@unpack DistributionSize,DistributionAssetGrid,InitialDistribution,AggShocks,TimePeriods = KS.Distribution


################### Plot the guess
Guess,GuessM = KS.Guess,KS.GuessM        
pol = SolveFiniteElement(Guess,LoMK,KS)        
@unpack elements,elementsID,kGrid,KGrid,m,wx,ax,nk,nK,ne = KS.FiniteElement
@unpack states,statesID,aggstatesID,ns,πz,Π,LoML = KS.MarkovChain
p = plot(kGrid,GuessM[collect(1:nK:nk*nK),1], label = "employed")
p = plot!(kGrid,GuessM[collect(1:nK:nk*nK),2], label = "unemployed")
p = plot!(kGrid,kGrid, line = :dot, label = "45 degree line")
p = plot!(xlims = (0.0,5.0), ylims=(0.0,5.0))
savefig(p,"Exolaborguess.pdf")


######## Compute Rational Expectations equilibrium
@time pol, LoMK, Kt, Prob0 = KSEquilibrium(KS)


###### Plot distribution
p1 = plot(title= "Distribution")
p1 = plot!(DistributionAssetGrid,Prob0[:,1], label="employed")
p1 = plot!(DistributionAssetGrid,Prob0[:,2], label="unemployed")
p1 = plot!(xlims = (0.0,50.0))


###### Plot policies
polr = reshape(pol,nK,nk,ns)
p2 = plot(kGrid,polr[1,:,1], label = "high employed", linewidth = 0.5)
p2 = plot!(kGrid,polr[1,:,2], label = "high unemployed", linewidth = 0.5)
p2 = plot!(kGrid,polr[1,:,3], label = "low employed" , linewidth = 0.5)
p2 = plot!(kGrid,polr[1,:,4], label = "low unemployed", linewidth = 0.5)
p2 = plot!(kGrid,kGrid, line = :dot, label = "45 degree line")
p2 = plot!(xlims = (0.0,10.0), ylims=(0.0,10.0))
p2 = plot!(title = "low agg capital solution")

#### Construct implied and actual law of motion
Ktr = fill(0.0,size(Kt))
Ktr[1] = Kt[1]
for i = 1:length(Ktr)-1
    AggShocks[i] == 1 ? LoM = LoMK[1,:] : LoM = LoMK[2,:] 
    b0,b1 = LoM[1],LoM[2]
    Ktr[i+1] =exp(b0 + b1*log(Kt[i]))
end
p3 = plot(Ktr[1:1000])
p3 = plot!(Kt[1:1000])
p3 = plot!(title ="Implied vs actual LOM", legend=false)

#### Put these three plots together
p = plot(p1,p2,p3, layout=(1,3), size = (1000,400))
p = plot!(titlefont = ("Helvetica",6))
p = plot!(legendfont = ("Helvetica",4))
savefig(p, "exolaborks.pdf")



