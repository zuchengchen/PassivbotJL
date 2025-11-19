# src/live/websocket_client.jl

"""
Binance WebSocket客户端（使用MbedTLS）
"""

using WebSockets
using JSON3
using Dates
using Logging
using MbedTLS  # ✅ 添加

# ============================================================================
# WebSocket客户端
# ============================================================================

mutable struct BinanceWebSocket
    base_url::String
    streams::Vector{String}
    on_tick::Union{Function, Nothing}
    on_kline::Union{Function, Nothing}
    on_account::Union{Function, Nothing}
    on_order::Union{Function, Nothing}
    is_running::Bool
    messages_received::Int
    last_message_time::DateTime
    
    function BinanceWebSocket(;
        market::Symbol=:futures,
        streams::Vector{String}=String[]
    )
        base_url = if market == :futures
            "wss://fstream.binance.com"
        else
            "wss://stream.binance.com:9443"
        end
        
        new(
            base_url,
            streams,
            nothing, nothing, nothing, nothing,
            false,
            0,
            DateTime(0)
        )
    end
end

# ============================================================================
# 流订阅
# ============================================================================

function subscribe_ticks!(ws::BinanceWebSocket, symbol::String)
    stream = lowercase(symbol) * "@aggTrade"
    push!(ws.streams, stream)
    @info "Subscribed to ticks" symbol=symbol
end

function subscribe_klines!(ws::BinanceWebSocket, symbol::String, interval::String)
    stream = lowercase(symbol) * "@kline_" * interval
    push!(ws.streams, stream)
    @info "Subscribed to klines" symbol=symbol interval=interval
end

# ============================================================================
# 消息处理
# ============================================================================

function start!(ws::BinanceWebSocket)
    
    if isempty(ws.streams)
        error("No streams specified")
    end
    
    # 构建URL
    if length(ws.streams) == 1
        url = "$(ws.base_url)/ws/$(ws.streams[1])"
    else
        stream_names = join(ws.streams, "/")
        url = "$(ws.base_url)/stream?streams=$(stream_names)"
    end
    
    @info "Starting WebSocket..." url=url
    
    ws.is_running = true
    ws.last_message_time = now()
    
    @async begin
        while ws.is_running
            try
                @info "Connecting to WebSocket..."
                
                # ✅ 使用MbedTLS
                WebSockets.open(url; sslconfig=MbedTLS.SSLConfig(true)) do ws_io
                    @info "✅ WebSocket connected!"
                    
                    while ws.is_running
                        try
                            if !eof(ws_io)
                                msg = String(read(ws_io))
                                
                                if !isempty(msg)
                                    process_message!(ws, msg)
                                    ws.messages_received += 1
                                    ws.last_message_time = now()
                                end
                            else
                                sleep(0.001)
                            end
                        catch e
                            if ws.is_running
                                if isa(e, EOFError)
                                    @warn "Connection closed"
                                    break
                                else
                                    @error "Error reading message" exception=e
                                    break
                                end
                            end
                        end
                    end
                    
                    @info "WebSocket connection closed"
                end
                
                if ws.is_running
                    @warn "Reconnecting in 5 seconds..."
                    sleep(5)
                end
                
            catch e
                if ws.is_running
                    @error "WebSocket error" exception=e
                    sleep(5)
                else
                    break
                end
            end
        end
        
        @info "WebSocket stopped"
    end
    
    sleep(2)
end

function stop!(ws::BinanceWebSocket)
    @info "Stopping WebSocket..."
    ws.is_running = false
    sleep(2)
end

function process_message!(ws::BinanceWebSocket, msg::String)
    
    try
        data = JSON3.read(msg)
        
        if haskey(data, :stream) && haskey(data, :data)
            stream_name = String(data.stream)
            stream_data = data.data
            
            if contains(stream_name, "@aggTrade")
                handle_tick!(ws, stream_data)
                
            elseif contains(stream_name, "@kline")
                handle_kline!(ws, stream_data)
                
            elseif contains(stream_name, "USER_DATA")
                handle_user_data!(ws, stream_data)
            end
        end
        
    catch e
        @error "Failed to process message" exception=e
    end
end

function handle_tick!(ws::BinanceWebSocket, data)
    
    if isnothing(ws.on_tick)
        return
    end
    
    tick = (
        timestamp = unix2datetime(data.T / 1000),
        symbol = Symbol(data.s),
        price = parse(Float64, String(data.p)),
        quantity = parse(Float64, String(data.q)),
        is_buyer_maker = data.m,
        trade_id = data.a
    )
    
    try
        ws.on_tick(tick)
    catch e
        @error "Error in tick callback" exception=e
    end
end

function handle_kline!(ws::BinanceWebSocket, data)
    
    if isnothing(ws.on_kline)
        return
    end
    
    k = data.k
    
    if !k.x
        return
    end
    
    kline = (
        timestamp = unix2datetime(k.t / 1000),
        close_time = unix2datetime(k.T / 1000),
        symbol = Symbol(k.s),
        interval = String(k.i),
        open = parse(Float64, String(k.o)),
        high = parse(Float64, String(k.h)),
        low = parse(Float64, String(k.l)),
        close = parse(Float64, String(k.c)),
        volume = parse(Float64, String(k.v)),
        is_closed = k.x
    )
    
    try
        ws.on_kline(kline)
    catch e
        @error "Error in kline callback" exception=e
    end
end

function handle_user_data!(ws::BinanceWebSocket, data)
    
    event_type = String(data.e)
    
    if event_type == "ACCOUNT_UPDATE"
        if !isnothing(ws.on_account)
            try
                ws.on_account(data)
            catch e
                @error "Error in account callback" exception=e
            end
        end
        
    elseif event_type == "ORDER_TRADE_UPDATE"
        if !isnothing(ws.on_order)
            try
                ws.on_order(data)
            catch e
                @error "Error in order callback" exception=e
            end
        end
    end
end

# ============================================================================
# 辅助函数
# ============================================================================

function is_connected(ws::BinanceWebSocket)::Bool
    return ws.is_running && (now() - ws.last_message_time < Second(30))
end

function get_stats(ws::BinanceWebSocket)::Dict
    return Dict(
        "is_running" => ws.is_running,
        "messages_received" => ws.messages_received,
        "last_message" => ws.last_message_time,
        "is_connected" => is_connected(ws)
    )
end