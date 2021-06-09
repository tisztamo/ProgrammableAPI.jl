module ForthAPI

using Circo
using Forth

include("wsapi.jl")

mutable struct ForthActor{TCore} <: Actor{TCore}
    msg_count::Int
    reset_ts::UInt64
    engine::ForthEngine
    token::UInt64
    core::TCore
    ForthActor{TCore}(token, core::TCore) where TCore = begin
        forth = interpreter(IOBuffer(), IOBuffer())
        return new{TCore}(0, time_ns(), forth, token, core)
    end
end

function Circo.onmessage(me::ForthActor, msg::PAPIInput, service)
    me.msg_count += 1
    write(me.engine.input, String(msg.program))
    write(me.engine.input, "\n")
    seekstart(me.engine.input)
    Forth.repl(me.engine; silent = false)
    take!(me.engine.input)
    send(service, me, msg.respondto, PAPIOutput(me.token, take!(me.engine.out)))
    seekstart(me.engine.out)    
end

# factory to pass to PAPI
function manager(coretype)
    return PAPIManager(ForthActor{coretype})
end

end # module
