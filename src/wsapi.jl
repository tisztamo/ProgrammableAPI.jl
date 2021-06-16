using HTTP, Logging
import Sockets

const Token = UInt64

struct Connection
    ws
    api_addr
end

abstract type WSAPIService <: Plugin end
mutable struct WSAPIServiceImpl<: WSAPIService
    manager_factory
    connections::Dict{Token, Connection}
    helper
    socket
    WSAPIServiceImpl(; wsapi_managerfactory, options...) = new(wsapi_managerfactory, Dict())
end
Plugins.symbol(plugin::WSAPIServiceImpl) = :wsapi
__init__() = Plugins.register(WSAPIServiceImpl)

mutable struct WSAPIHelper <: Actor{Any}
    manager_addr::Addr
    wsapi::WSAPIServiceImpl
    core
    WSAPIHelper(manager_addr, wsapi) = new(manager_addr, wsapi)
end

function spawn_helper(wsapi::WSAPIServiceImpl, scheduler)
    manager = wsapi.manager_factory(typeof(emptycore(scheduler.service)))
    manager_addr = spawn(scheduler.service, manager)
    wsapi.helper = WSAPIHelper(manager_addr, wsapi)
    spawn(scheduler.service, wsapi.helper)
end

Circo.schedule_start(wsapi::WSAPIServiceImpl, scheduler::AbstractScheduler{TMsg}) where {TMsg} = begin
    spawn_helper(wsapi, scheduler)
    listenport = 7274 + port(postcode(scheduler)) - CircoCore.PORT_RANGE[1] # PAPI, Programmable API
    ipaddr = Sockets.IPv4(0) # TODO config
    try
        wsapi.socket = Sockets.listen(Sockets.InetAddr(ipaddr, listenport))
        @info "Programmable API websocket listening on $(ipaddr):$(listenport)"
    catch e
        @warn "Programmable API unable to listen on $(ipaddr):$(listenport)", e
    end
    @async HTTP.listen(ipaddr, listenport; server=wsapi.socket) do http
        if HTTP.WebSockets.is_upgrade(http.message)
            HTTP.WebSockets.upgrade(http; binary=true) do ws
                try
                    @debug "Programmable API got WS connection", ws
                    handle_connection(wsapi, ws, scheduler)
                catch e
                    @info "wsapi: $e"
                end
            end
        end
    end
end

function Circo.schedule_stop(wsapi::WSAPIServiceImpl, scheduler)
    for conn in values(wsapi.connections)
        try
            close(conn.ws)
        catch e end
    end
    isdefined(wsapi, :socket) && close(wsapi.socket)
end

function create_api(wsapi::WSAPIServiceImpl, ws, scheduler)
    token = rand(ProgrammableAPI.PAPIReqId)
    conn = Connection(ws, nothing)
    wsapi.connections[token] = conn
    send(scheduler.service, wsapi.helper, wsapi.helper.manager_addr,
        CreateEngine(token, addr(wsapi.helper)))
    return token
end

function handle_connection(wsapi::WSAPIServiceImpl, ws, scheduler)
    @debug "Programmable API ws handle_connection on thread $(Threads.threadid())"
    token = create_api(wsapi, ws, scheduler)
    readloop(wsapi, token, scheduler)
end

Circo.onmessage(me::WSAPIHelper, msg::EngineCreated, service) = begin
    connection = get(me.wsapi.connections, msg.token, nothing)
    if isnothing(connection)
        @info "Got EngineCreated with unknown token $(msg.token)"
        return nothing
    end
    ws = connection.ws
    conn = Connection(ws, msg.addr)
    me.wsapi.connections[msg.token] = conn
    return nothing
end

function sendws(rawmsg, ws)
    try
        write(ws, rawmsg)
    catch e
        @error "Unable to write to websocket." exception=(e, catch_backtrace())
    end
end

function handleinput(wsapi::WSAPIServiceImpl, buf, connection, scheduler)
    send(scheduler.service, wsapi.helper, connection.api_addr,
        PAPIInput(addr(wsapi.helper), buf))
    return nothing
end

function _close_connection(wsapi, token, service)
    try
        connection = get(wsapi.connections, token, nothing)
        isnothing(connection) && return nothing
        # TODO send(service, wsapi.helper, connection.api_addr, DestroyEngine(connection.token))
        delete!(wsapi.connections, token)
        isnothing(connection.ws) && return nothing
        close(connection.ws)
    catch e
        @debug "Error closing websocket", e
    end
    return nothing
end

function readloop(wsapi::WSAPIServiceImpl, token, scheduler)
    connection = wsapi.connections[token]
    wait_count = 0
    while isnothing(connection.api_addr) && wait_count < 1000
        sleep(0.001)
        wait_count += 1
        connection = wsapi.connections[token]
    end
    if isnothing(connection.api_addr)
        @error "API endpoint creation timeouted."
        return _close_connection(wsapi, token, scheduler.service)
    end
    @debug "Created API endpoint at $(connection.api_addr)"
    ws = connection.ws
    buf = nothing
    try
        while !eof(ws)
            try
                buf = readavailable(ws)
            catch e
                @debug "Websocket closed: $e"
                return
            end
            handleinput(wsapi, buf, connection, scheduler)
        end
    catch e
        if e isa MethodError && e.f == convert
            @show e
            @info "Erroneous websocket frame: ", buf
        else
            # TODO this causes segfault on 1.5.0 with multithreading
            if Threads.nthreads() == 1
                @error "Exception while handling websocket frame" exception=(e, catch_backtrace())
            else
                @error "Exception while handling websocket frame: $e"
                @error "Cannot print stack trace due to an unknown issue in Base or HTTP.jl. Rerun with JULIA_NUM_THREADS=1 to get more info"
            end
        end
    end
    @debug "PAPI Websocket closed", ws
end

Circo.onmessage(me::WSAPIHelper, msg::PAPIOutput, service) = begin
    try
        ws = me.wsapi.connections[msg.token].ws
        write(ws, msg.body)
        return nothing
    catch e
        @debug "Error writing to websocket", e
    end
    _close_connection(me.wsapi, msg.token, service)
end
