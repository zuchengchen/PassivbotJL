# src/exchange/binance.jl

"""
币安Futures API连接器
"""

using HTTP
using JSON3
using SHA
using Dates
using DataFrames

# ============================================================================
# 币安交易所结构
# ============================================================================

mutable struct BinanceFutures <: AbstractExchange
    api_key::String
    api_secret::String
    base_url::String
    testnet::Bool
    rate_limit_per_minute::Int
    last_request_time::DateTime
    request_count::Int
    timeout::Int
    time_offset::Int64
    
    function BinanceFutures(config::ExchangeConfig)
        base_url = if config.testnet
            "https://testnet.binancefuture.com"
        else
            "https://fapi.binance.com"
        end
        
        exchange = new(
            config.api_key,
            config.api_secret,
            base_url,
            config.testnet,
            config.rate_limit_per_minute,
            now(),
            0,
            config.order_timeout_seconds,
            0
        )
        
        sync_time!(exchange)
        return exchange
    end
end

# ============================================================================
# 辅助函数
# ============================================================================

function sync_time!(exchange::BinanceFutures)
    try
        url = exchange.base_url * "/fapi/v1/time"
        response = HTTP.get(url, readtimeout=exchange.timeout)
        data = JSON3.read(response.body)
        server_time_ms = data.serverTime
        
        local_time_ms = Int64(datetime2unix(now()) * 1000)
        exchange.time_offset = server_time_ms - local_time_ms
        
        @info "Time synchronized" offset_ms=exchange.time_offset offset_seconds=round(exchange.time_offset/1000, digits=2)
        
        if abs(exchange.time_offset) > 5000
            @warn "Large time offset detected ($(exchange.time_offset)ms). Consider syncing system time."
        end
    catch e
        @warn "Failed to sync time" exception=e
        exchange.time_offset = 0
    end
end

function generate_signature(query_string::String, api_secret::String)
    return bytes2hex(hmac_sha256(Vector{UInt8}(api_secret), Vector{UInt8}(query_string)))
end

function check_rate_limit!(exchange::BinanceFutures)
    current_time = now()
    
    if Dates.value(current_time - exchange.last_request_time) > 60000
        exchange.request_count = 0
        exchange.last_request_time = current_time
    end
    
    if exchange.request_count >= exchange.rate_limit_per_minute
        sleep_time = 60 - Dates.value(current_time - exchange.last_request_time) / 1000
        if sleep_time > 0
            @warn "Rate limit reached, sleeping for $(sleep_time)s"
            sleep(sleep_time)
        end
        exchange.request_count = 0
        exchange.last_request_time = now()
    end
    
    exchange.request_count += 1
end

function make_request(
    exchange::BinanceFutures,
    method::String,
    endpoint::String;
    params::Dict=Dict(),
    signed::Bool=false
)
    check_rate_limit!(exchange)
    
    url = exchange.base_url * endpoint
    
    if signed
        local_time_ms = Int64(datetime2unix(now()) * 1000)
        adjusted_timestamp = local_time_ms + exchange.time_offset
        params["timestamp"] = string(adjusted_timestamp)
        params["recvWindow"] = "5000"
    end
    
    query_string = join(["$k=$v" for (k, v) in sort(collect(params))], "&")
    
    if signed
        signature = generate_signature(query_string, exchange.api_secret)
        query_string *= "&signature=$signature"
    end
    
    headers = Dict("X-MBX-APIKEY" => exchange.api_key)
    
    try
        response = if method == "GET"
            HTTP.get(url * (isempty(query_string) ? "" : "?$query_string"), headers, readtimeout=exchange.timeout)
        elseif method == "POST"
            HTTP.post(url * (isempty(query_string) ? "" : "?$query_string"), headers, readtimeout=exchange.timeout)
        elseif method == "DELETE"
            HTTP.delete(url * (isempty(query_string) ? "" : "?$query_string"), headers, readtimeout=exchange.timeout)
        else
            error("Unsupported HTTP method: $method")
        end
        
        return JSON3.read(response.body)
        
    catch e
        if isa(e, HTTP.ExceptionRequest.StatusError)
            error_body = String(e.response.body)
            
            if occursin("Timestamp", error_body)
                @warn "Timestamp error, re-syncing..."
                sync_time!(exchange)
            end
            
            @error "Binance API error" status=e.status body=error_body
            error("Binance API request failed: $error_body")
        else
            rethrow(e)
        end
    end
end

# ============================================================================
# 实现抽象接口 - 直接定义函数（不用Base.）
# ============================================================================

function get_server_time(exchange::BinanceFutures)
    response = make_request(exchange, "GET", "/fapi/v1/time")
    return unix2datetime(response.serverTime / 1000)
end

function get_klines(exchange::BinanceFutures, symbol::Symbol, interval::String, limit::Int=100)
    params = Dict(
        "symbol" => string(symbol),
        "interval" => interval,
        "limit" => string(min(limit, 1500))
    )
    
    response = make_request(exchange, "GET", "/fapi/v1/klines", params=params)
    
    klines = DataFrame(
        timestamp = DateTime[],
        open = Float64[],
        high = Float64[],
        low = Float64[],
        close = Float64[],
        volume = Float64[]
    )
    
    for kline in response
        push!(klines, (
            unix2datetime(kline[1] / 1000),
            parse(Float64, kline[2]),
            parse(Float64, kline[3]),
            parse(Float64, kline[4]),
            parse(Float64, kline[5]),
            parse(Float64, kline[6])
        ))
    end
    
    @debug "Fetched $(nrow(klines)) klines for $symbol ($interval)"
    return klines
end

function get_ticker_price(exchange::BinanceFutures, symbol::Symbol)
    params = Dict("symbol" => string(symbol))
    response = make_request(exchange, "GET", "/fapi/v1/ticker/price", params=params)
    
    price = parse(Float64, response.price)
    @debug "Current price for $symbol: $price"
    return price
end

function get_ticker_24hr(exchange::BinanceFutures, symbol::Symbol)
    params = Dict("symbol" => string(symbol))
    response = make_request(exchange, "GET", "/fapi/v1/ticker/24hr", params=params)
    
    return (
        symbol = Symbol(response.symbol),
        price_change = parse(Float64, response.priceChange),
        price_change_percent = parse(Float64, response.priceChangePercent),
        last_price = parse(Float64, response.lastPrice),
        volume = parse(Float64, response.volume),
        quote_volume = parse(Float64, response.quoteVolume),
        high = parse(Float64, response.highPrice),
        low = parse(Float64, response.lowPrice)
    )
end

function get_account_balance(exchange::BinanceFutures)
    response = make_request(exchange, "GET", "/fapi/v2/balance", signed=true)
    
    usdt_balance = nothing
    for asset in response
        if asset.asset == "USDT"
            usdt_balance = (
                asset = asset.asset,
                balance = parse(Float64, asset.balance),
                available = parse(Float64, asset.availableBalance),
                cross_wallet_balance = parse(Float64, asset.crossWalletBalance),
                cross_unrealized_pnl = parse(Float64, asset.crossUnPnl)
            )
            break
        end
    end
    
    if isnothing(usdt_balance)
        error("USDT balance not found")
    end
    
    @debug "Account balance" balance=usdt_balance.balance
    return usdt_balance
end

function get_account_info(exchange::BinanceFutures)
    response = make_request(exchange, "GET", "/fapi/v2/account", signed=true)
    
    return (
        total_wallet_balance = parse(Float64, response.totalWalletBalance),
        total_unrealized_profit = parse(Float64, response.totalUnrealizedProfit),
        total_margin_balance = parse(Float64, response.totalMarginBalance),
        available_balance = parse(Float64, response.availableBalance),
        max_withdraw_amount = parse(Float64, response.maxWithdrawAmount),
        can_trade = response.canTrade,
        can_deposit = response.canDeposit,
        can_withdraw = response.canWithdraw
    )
end

function get_position(exchange::BinanceFutures, symbol::Symbol)
    response = make_request(exchange, "GET", "/fapi/v2/positionRisk", signed=true)
    
    for pos in response
        if pos.symbol == string(symbol)
            position_amt = parse(Float64, pos.positionAmt)
            
            if position_amt == 0.0
                return nothing
            end
            
            side = position_amt > 0 ? LONG : SHORT
            
            return Position(
                Symbol(pos.symbol),
                side,
                abs(position_amt),
                parse(Float64, pos.entryPrice),
                parse(Float64, pos.markPrice),
                parse(Float64, pos.liquidationPrice),
                parse(Float64, pos.unRealizedProfit),
                parse(Int, pos.leverage)
            )
        end
    end
    
    return nothing
end

function get_all_positions(exchange::BinanceFutures)
    response = make_request(exchange, "GET", "/fapi/v2/positionRisk", signed=true)
    
    positions = Position[]
    
    for pos in response
        position_amt = parse(Float64, pos.positionAmt)
        
        if position_amt != 0.0
            side = position_amt > 0 ? LONG : SHORT
            
            push!(positions, Position(
                Symbol(pos.symbol),
                side,
                abs(position_amt),
                parse(Float64, pos.entryPrice),
                parse(Float64, pos.markPrice),
                parse(Float64, pos.liquidationPrice),
                parse(Float64, pos.unRealizedProfit),
                parse(Int, pos.leverage)
            ))
        end
    end
    
    return positions
end

function set_leverage(exchange::BinanceFutures, symbol::Symbol, leverage::Int)
    params = Dict(
        "symbol" => string(symbol),
        "leverage" => string(leverage)
    )
    
    response = make_request(exchange, "POST", "/fapi/v1/leverage", params=params, signed=true)
    @info "Leverage set for $symbol" leverage=leverage
    return parse(Int, response.leverage)
end

function set_margin_type(exchange::BinanceFutures, symbol::Symbol, margin_type::String)
    params = Dict(
        "symbol" => string(symbol),
        "marginType" => margin_type
    )
    
    try
        make_request(exchange, "POST", "/fapi/v1/marginType", params=params, signed=true)
        @info "Margin type set for $symbol" margin_type=margin_type
        return true
    catch e
        if occursin("No need to change", string(e))
            @debug "Margin type already set"
            return true
        else
            rethrow(e)
        end
    end
end

function place_order(
    exchange::BinanceFutures,
    symbol::Symbol,
    side::String,
    order_type::String,
    quantity::Float64,
    price::Union{Float64, Nothing}=nothing;
    reduce_only::Bool=false,
    time_in_force::String="GTC"
)
    params = Dict(
        "symbol" => string(symbol),
        "side" => side,
        "type" => order_type,
        "quantity" => string(quantity)
    )
    
    if order_type == "LIMIT"
        if isnothing(price)
            error("Price required for LIMIT order")
        end
        params["price"] = string(price)
        params["timeInForce"] = time_in_force
    end
    
    if reduce_only
        params["reduceOnly"] = "true"
    end
    
    response = make_request(exchange, "POST", "/fapi/v1/order", params=params, signed=true)
    order_id = string(response.orderId)
    
    @info "Order placed" symbol=symbol side=side type=order_type quantity=quantity order_id=order_id
    return order_id
end

function cancel_order(exchange::BinanceFutures, symbol::Symbol, order_id::String)
    params = Dict(
        "symbol" => string(symbol),
        "orderId" => order_id
    )
    
    make_request(exchange, "DELETE", "/fapi/v1/order", params=params, signed=true)
    @info "Order cancelled" symbol=symbol order_id=order_id
    return true
end

function cancel_all_orders(exchange::BinanceFutures, symbol::Symbol)
    params = Dict("symbol" => string(symbol))
    response = make_request(exchange, "DELETE", "/fapi/v1/allOpenOrders", params=params, signed=true)
    @info "All orders cancelled for $symbol"
    return response
end

function get_open_orders(exchange::BinanceFutures, symbol::Symbol)
    params = Dict("symbol" => string(symbol))
    response = make_request(exchange, "GET", "/fapi/v1/openOrders", params=params, signed=true)
    
    orders = []
    for order in response
        push!(orders, (
            order_id = string(order.orderId),
            symbol = Symbol(order.symbol),
            side = order.side,
            type = order.type,
            price = parse(Float64, order.price),
            quantity = parse(Float64, order.origQty),
            executed_qty = parse(Float64, order.executedQty),
            status = order.status,
            time = unix2datetime(order.time / 1000)
        ))
    end
    
    return orders
end

function get_order_status(exchange::BinanceFutures, symbol::Symbol, order_id::String)
    params = Dict(
        "symbol" => string(symbol),
        "orderId" => order_id
    )
    
    response = make_request(exchange, "GET", "/fapi/v1/order", params=params, signed=true)
    
    return (
        order_id = string(response.orderId),
        status = response.status,
        executed_qty = parse(Float64, response.executedQty),
        avg_price = parse(Float64, response.avgPrice)
    )
end