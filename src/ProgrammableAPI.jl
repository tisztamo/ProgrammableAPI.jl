module ProgrammableAPI

export PAPIManager, PAPIInput, PAPIOutput, CreateEngine, EngineCreated, WSAPIService

using Circo
using Plugins

PAPIReqId = UInt64

struct PAPIInput
    respondto::Addr
    program::Vector{UInt8}
    PAPIInput(respondto::Addr, program) = new(respondto, program)
end

struct PAPIOutput
    token::UInt64
    body::Vector{UInt8}
end

struct CreateEngine
    token::UInt64
    respondto::Addr
end

struct EngineCreated
    token::UInt64
    addr::Addr
end

struct DestroyEngine
    token::UInt64
end

mutable struct PAPIManager <: Actor{Any}
    engine_factory
    living::Set{Addr}
    got_ping_from::Set{Addr} # TODO use
    core
    PAPIManager(engine_factory) = new(engine_factory, Set(), Set())
end

function Circo.onmessage(me::PAPIManager, msg::CreateEngine, service)
    engine = me.engine_factory(msg.token, emptycore(service))
    addr = spawn(service, engine)
    push!(me.living, addr)
    send(service, me, msg.respondto, EngineCreated(msg.token, addr))
end

include("wsapi.jl")

end # module
