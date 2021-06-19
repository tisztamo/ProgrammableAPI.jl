# ProgrammableAPI.jl

![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-orange.svg)
<!--
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://tisztamo.github.io/ProgrammableAPI.jl/stable)
[![Documentation](https://img.shields.io/badge/docs-master-blue.svg)](https://tisztamo.github.io/ProgrammableAPI.jl/dev)
-->

Simple programmable API framework over websocket with Circo.

ProgrammableAPI.jl helps you to provide highly secure but programmable, possibly Turing-complete API layer at the edge of your Julia projects.

## What is a programmable API?

A Programmable API is a network interface that allows efficient communication across incompatible programming environments by providing a common language that the parties use to script each other.

The simplest example is a frontend client and a backend server with the twist that instead of issuing REST requests, the client sends small scripts to the server for execution.

The sandboxed scripts can hold state and prepare queries on the server. After executing a query, additional server-side logic can run on the received data instead of just forwarding it to the client.

This pre- and postprocessing is programmed by the client developer and is deployed with the client, allowing it to change quickly, to be specific to the client if more than one type of clients exist and to define its own domain language, possibly lowering communication costs, latency or even server costs.

On the other hand the extra layer of abstraction allows the server to provide a lower-level API. Instead of defining a rigid, functional API endpoint structure, it exports small building blocks that the client can use to build its own (query) language.

ProgrammableAPI.jl is agnostic of the script language, it only manages client connections, sandbox creation/destruction and message forwarding. [ChainForth.jl](https://github.com/tisztamo/ChainForth.jl) is an engine designed to work in concert with ProgrammableAPI.jl.

Usage example:

```julia
module ChainForthAPI

using Circo
import ChainForth
using ProgrammableAPI

abstract type ForthActor{TCore} <: Actor{TCore} end

mutable struct ForthActorImpl{TCore} <: ForthActor{TCore}
    engine::Union{ChainForth.ForthEngine, Nothing}
    token::UInt64
    core::TCore
    ForthActorImpl(token, core) =
        new{typeof(core)}(nothing, token, core)
end

function Circo.onspawn(me::ForthActor, service)
    me.engine = ChainForth.interpreter(IOBuffer(), IOBuffer())

    # Define low level API and Domain language
    ChainForth.define(me.engine, "mydata", op_mydata)
    ChainForth.interpret(me.engine, ": double 2 * ;")
end

function op_mydata(engine, parent, myidx)
    push!(engine.stack, 42)
    return 1
end

function Circo.onmessage(me::ForthActor, msg::PAPIInput, service)
    try
        ChainForth.interpret(me.engine, msg.program)
    catch e
        @error "ForthActor onmessage: $e" exception=(e, catch_backtrace())
    end
    take!(me.engine.input)
    send(service, me, msg.respondto, PAPIOutput(me.token, take!(me.engine.out)))
    seekstart(me.engine.out)    
end

# factory to pass to PAPI
function manager(coretype)
    return PAPIManager(ForthActorImpl)
end

end # module


# Start Circo with ChainForth PAPI

using Circo, ProgrammableAPI, .ChainForthAPI

zygote(ctx) = []
plugins() = [ProgrammableAPI.WSAPIService]
options() = (wsapi_managerfactory = ChainForthAPI.manager,)
profile(;opts...) = Circo.Profiles.ClusterProfile(;opts...)

macro run()
    return quote
        $(Circo.cli.runnerquote())
    end
end

@run
```

```
[ Info: First node started. To add nodes to this cluster, run:
[ Info: bin/circonode.sh --roots 192.168.193.99:24721
[ Info: Circo scheduler starting on thread 1
[ Info: Web Socket listening on 0.0.0.0:2497
[ Info: Programmable API websocket listening on 0.0.0.0:7274
```

Then connect to the PAPI port 7274 with websocket:

```
$ wscat -c ws://localhost:7274
Connected (press CTRL+C to quit)
> mydata double .
< 84
```

