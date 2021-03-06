abstract type OrdinaryDiffEqCache <: DECache end
abstract type OrdinaryDiffEqConstantCache <: OrdinaryDiffEqCache end
abstract type OrdinaryDiffEqMutableCache <: OrdinaryDiffEqCache end
struct ODEEmptyCache <: OrdinaryDiffEqConstantCache end
struct ODEChunkCache{CS} <: OrdinaryDiffEqConstantCache end

mutable struct CompositeCache{T,F} <: OrdinaryDiffEqCache
  caches::T
  choice_function::F
  current::Int
end

function alg_cache{T}(alg::CompositeAlgorithm,u,rate_prototype,uEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,::Type{Val{T}})
  caches = map((x)->alg_cache(x,u,rate_prototype,uEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,Val{T}),alg.algs)
  CompositeCache(caches,alg.choice_function,1)
end

alg_cache{F}(alg::OrdinaryDiffEqAlgorithm,prob,callback::F) = ODEEmptyCache()

struct DiscreteCache{uType,rateType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  du::rateType
end

u_cache(c::DiscreteCache) = ()
du_cache(c::DiscreteCache) = (c.du)

function alg_cache(alg::Discrete,u,rate_prototype,uEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,::Type{Val{true}})
  DiscreteCache(u,uprev,discrete_scale_by_time(alg) ? rate_prototype : similar(u))
end

struct DiscreteConstantCache <: OrdinaryDiffEqConstantCache end

alg_cache(alg::Discrete,u,rate_prototype,uEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,::Type{Val{false}}) = DiscreteConstantCache()

struct ExplicitRKCache{uType,rateType,uEltypeNoUnits,ksEltype,TabType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  utilde::rateType
  atmp::uEltypeNoUnits
  fsalfirst::ksEltype
  fsallast::ksEltype
  kk::Vector{ksEltype}
  tab::TabType
end

u_cache(c::ExplicitRKCache) = (c.utilde,c.atmp,c.update)
du_cache(c::ExplicitRKCache) = (c.kk...)

function alg_cache(alg::ExplicitRK,u,rate_prototype,uEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,::Type{Val{true}})
  kk = Vector{typeof(rate_prototype)}(0)
  for i = 1:alg.tableau.stages
    push!(kk,zeros(rate_prototype))
  end
  fsalfirst = kk[1]
  if isfsal(alg.tableau)
    fsallast = kk[end]
  else
    fsallast = zeros(rate_prototype)
  end
  utilde = zeros(rate_prototype)
  tmp = similar(u)
  atmp = similar(u,uEltypeNoUnits,indices(u))
  tab = ExplicitRKConstantCache(alg.tableau,rate_prototype)
  ExplicitRKCache(u,uprev,tmp,utilde,atmp,fsalfirst,fsallast,kk,tab)
end

struct ExplicitRKConstantCache{MType,VType,KType} <: OrdinaryDiffEqConstantCache
  A::MType
  c::VType
  α::VType
  αEEst::VType
  stages::Int
  kk::KType
end

function ExplicitRKConstantCache(tableau,rate_prototype)
  @unpack A,c,α,αEEst,stages = tableau
  A = A' # Transpose A to column major looping
  kk = Array{typeof(rate_prototype)}(stages) # Not ks since that's for integrator.opts.dense
  ExplicitRKConstantCache(A,c,α,αEEst,stages,kk)
end

alg_cache(alg::ExplicitRK,u,rate_prototype,uEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,::Type{Val{false}}) = ExplicitRKConstantCache(alg.tableau,rate_prototype)

get_chunksize(cache::DECache) = error("This cache does not have a chunksize.")
get_chunksize{CS}(cache::ODEChunkCache{CS}) = CS
