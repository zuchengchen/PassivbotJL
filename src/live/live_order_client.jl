# src/live/live_order_client.jl

"""
实盘订单执行客户端（修复版）

功能：
- 下单（市价/限价）
- 撤单
- 查询订单
- 查询持仓
- 查询账户
"""

using HTTP
using JSON3
using Dates
using SHA
using Logging

# ============================================================================
# 时间同步
# ============================================================================

"""
    get_server_time(base_url::String)::Int64

获取服务器时间（毫秒）
"""
function get_server_time(base_url::String)::Int64
    try
        response = HTTP.get("$base_url/fapi/v1/time")
        data = JSON3.read(String(response.body))
        return data.serverTime
    catch e
        @warn "Failed to get server time, using local time" exception=e
        return round(Int64, datetime2unix(now(UTC)) * 1000)
    end
end

# ============================================================================
# 订单客户端
# ============================================================================

"""
    LiveOrderClient

实盘订单客户端
"""
mutable struct LiveOrderClient
    api_key::String
    api_secret::String
    market::Symbol
    base_url::String
    
    # 时间同步
    time_offset::Int64
    last_sync::DateTime
    
    # 统计
    orders_sent::Int
    orders_filled::Int
    orders_rejected::Int
    
    function LiveOrderClient(api_key::String, api_secret::String; market::Symbol=:futures)
        base_url = if market == :futures
            "https://fapi.binance.com"
        else
            "https://api.binance.com"
        end
        
        client = new(
            api_key,
            api_secret,
            market,
            base_url,
            0,
            DateTime(0),
            0, 0, 0
        )
        
        # 初始化时同步时间
        sync_time!(client)
        
        return client
    end
end

"""
    sync_time!(client::LiveOrderClient)

同步服务器时间
"""
function sync_time!(client::LiveOrderClient)
    try
        local_time = round(Int64, datetime2unix(now(UTC)) * 1000)
        server_time = get_server_time(client.base_url)
        
        client.time_offset = server_time - local_time
        client.last_sync = now(UTC)
        
        @info "Time synchronized" offset_ms=client.time_offset
        
        if abs(client.time_offset) > 1000
            @warn "Large time offset detected" offset_ms=client.time_offset
        end
        
    catch e
        @error "Failed to sync time" exception=e
        client.time_offset = 0
    end
end

"""
    get_timestamp(client::LiveOrderClient)::Int64

获取时间戳（直接使用服务器时间）
"""
function get_timestamp(client::LiveOrderClient)::Int64
    # 直接获取服务器时间，避免时间偏差问题
    try
        return get_server_time(client.base_url)
    catch e
        @warn "Failed to get server time, using local time" exception=e
        return round(Int64, datetime2unix(now(UTC)) * 1000)
    end
end

# ============================================================================
# 签名与请求
# ============================================================================

"""
    build_query_string(params::Dict)::String

构建查询字符串
"""
function build_query_string(params::Dict)::String
    # ✅ 按字母顺序排序参数
    sorted_keys = sort(collect(keys(params)))
    
    # ✅ URL编码值
    pairs = String[]
    for key in sorted_keys
        value = params[key]
        # 不编码已经是字符串的值，直接拼接
        push!(pairs, "$key=$value")
    end
    
    return join(pairs, "&")
end

"""
    sign_request(client::LiveOrderClient, params::Dict)::String

生成请求签名
"""
function sign_request(client::LiveOrderClient, params::Dict)::String
    # 添加时间戳
    params["timestamp"] = string(get_timestamp(client))
    
    # ✅ 添加接收窗口
    params["recvWindow"] = "5000"
    
    # 构建查询字符串
    query_string = build_query_string(params)
    
    @debug "Query string for signing" query=query_string
    
    # HMAC-SHA256签名
    signature = bytes2hex(SHA.hmac_sha256(Vector{UInt8}(client.api_secret), Vector{UInt8}(query_string)))
    
    @debug "Signature generated" signature=signature
    
    return signature
end

"""
    send_signed_request(client::LiveOrderClient, method::String, endpoint::String, params::Dict)

发送签名请求
"""
function send_signed_request(client::LiveOrderClient, method::String, endpoint::String, params::Dict)
    
    # 复制参数（避免修改原始字典）
    request_params = copy(params)
    
    # 生成签名
    signature = sign_request(client, request_params)
    
    # 添加签名到参数
    request_params["signature"] = signature
    
    # 构建完整查询字符串
    query_string = build_query_string(request_params)
    
    # 构建URL
    url = "$(client.base_url)$(endpoint)?$query_string"
    
    @debug "Request URL" url=url
    
    # 请求头
    headers = [
        "X-MBX-APIKEY" => client.api_key
    ]
    
    try
        # 发送请求
        response = if method == "GET"
            HTTP.get(url, headers)
        elseif method == "POST"
            HTTP.post(url, headers)
        elseif method == "DELETE"
            HTTP.delete(url, headers)
        else
            error("Unsupported method: $method")
        end
        
        # 解析响应
        data = JSON3.read(String(response.body))
        return data
        
    catch e
        @error "Request failed" method=method endpoint=endpoint exception=e
        
        # 如果是HTTP错误，尝试解析错误信息
        if isa(e, HTTP.Exceptions.StatusError)
            try
                error_body = String(e.response.body)
                error_data = JSON3.read(error_body)
                @error "API Error" code=error_data.code msg=error_data.msg
            catch
                # 无法解析错误
            end
        end
        
        rethrow(e)
    end
end

# ============================================================================
# 下单
# ============================================================================

"""
    place_order(client::LiveOrderClient; kwargs...)

下单
"""
function place_order(client::LiveOrderClient; kwargs...)
    
    endpoint = client.market == :futures ? "/fapi/v1/order" : "/api/v3/order"
    
    # 构建参数
    params = Dict{String, String}()
    for (k, v) in kwargs
        params[string(k)] = string(v)
    end
    
    @info "Placing order" symbol=get(params, "symbol", "") side=get(params, "side", "") type=get(params, "type", "") quantity=get(params, "quantity", "")
    
    try
        response = send_signed_request(client, "POST", endpoint, params)
        
        client.orders_sent += 1
        
        @info "Order placed successfully" orderId=response.orderId clientOrderId=get(response, :clientOrderId, "")
        
        return response
        
    catch e
        client.orders_rejected += 1
        @error "Failed to place order" exception=e
        rethrow(e)
    end
end

"""
    place_limit_order(client::LiveOrderClient, symbol::String, side::String, quantity::Float64, price::Float64; kwargs...)

下限价单
"""
function place_limit_order(client::LiveOrderClient, symbol::String, side::String, quantity::Float64, price::Float64; kwargs...)
    
    # 构建参数
    order_params = Dict{Symbol, Any}(
        :symbol => symbol,
        :side => side,
        :type => "LIMIT",
        :quantity => quantity,
        :price => price,
        :timeInForce => get(kwargs, :timeInForce, "GTC")
    )
    
    # 添加其他参数
    for (k, v) in kwargs
        if k != :timeInForce
            order_params[k] = v
        end
    end
    
    # 调用place_order
    return place_order(client; order_params...)
end

"""
    place_market_order(client::LiveOrderClient, symbol::String, side::String, quantity::Float64; kwargs...)

下市价单
"""
function place_market_order(client::LiveOrderClient, symbol::String, side::String, quantity::Float64; kwargs...)
    
    order_params = Dict{Symbol, Any}(
        :symbol => symbol,
        :side => side,
        :type => "MARKET",
        :quantity => quantity
    )
    
    for (k, v) in kwargs
        order_params[k] = v
    end
    
    return place_order(client; order_params...)
end

# ============================================================================
# 撤单
# ============================================================================

"""
    cancel_order(client::LiveOrderClient, symbol::String, order_id::Int)

撤销订单
"""
function cancel_order(client::LiveOrderClient, symbol::String, order_id::Int)
    
    endpoint = client.market == :futures ? "/fapi/v1/order" : "/api/v3/order"
    
    params = Dict{String, String}(
        "symbol" => symbol,
        "orderId" => string(order_id)
    )
    
    @info "Canceling order" symbol=symbol orderId=order_id
    
    try
        response = send_signed_request(client, "DELETE", endpoint, params)
        @info "Order canceled" orderId=order_id
        return response
        
    catch e
        @error "Failed to cancel order" exception=e
        rethrow(e)
    end
end

"""
    cancel_all_orders(client::LiveOrderClient, symbol::String)

撤销所有订单
"""
function cancel_all_orders(client::LiveOrderClient, symbol::String)
    
    endpoint = client.market == :futures ? "/fapi/v1/allOpenOrders" : "/api/v3/openOrders"
    
    params = Dict{String, String}("symbol" => symbol)
    
    @warn "Canceling ALL orders" symbol=symbol
    
    try
        response = send_signed_request(client, "DELETE", endpoint, params)
        @info "All orders canceled" symbol=symbol count=length(response)
        return response
        
    catch e
        @error "Failed to cancel all orders" exception=e
        rethrow(e)
    end
end

# ============================================================================
# 查询
# ============================================================================

"""
    get_order(client::LiveOrderClient, symbol::String, order_id::Int)

查询订单状态
"""
function get_order(client::LiveOrderClient, symbol::String, order_id::Int)
    
    endpoint = client.market == :futures ? "/fapi/v1/order" : "/api/v3/order"
    
    params = Dict{String, String}(
        "symbol" => symbol,
        "orderId" => string(order_id)
    )
    
    response = send_signed_request(client, "GET", endpoint, params)
    return response
end

"""
    get_open_orders(client::LiveOrderClient, symbol::Union{String, Nothing}=nothing)

查询未完成订单
"""
function get_open_orders(client::LiveOrderClient, symbol::Union{String, Nothing}=nothing)
    
    endpoint = client.market == :futures ? "/fapi/v1/openOrders" : "/api/v3/openOrders"
    
    params = Dict{String, String}()
    if !isnothing(symbol)
        params["symbol"] = symbol
    end
    
    response = send_signed_request(client, "GET", endpoint, params)
    return response
end

"""
    get_position(client::LiveOrderClient, symbol::Union{String, Nothing}=nothing)

查询持仓（仅期货）
"""
function get_position(client::LiveOrderClient, symbol::Union{String, Nothing}=nothing)
    
    if client.market != :futures
        error("Position query only available for futures")
    end
    
    endpoint = "/fapi/v2/positionRisk"
    
    params = Dict{String, String}()
    if !isnothing(symbol)
        params["symbol"] = symbol
    end
    
    response = send_signed_request(client, "GET", endpoint, params)
    return response
end

"""
    get_account(client::LiveOrderClient)

查询账户信息
"""
function get_account(client::LiveOrderClient)
    
    endpoint = client.market == :futures ? "/fapi/v2/account" : "/api/v3/account"
    
    response = send_signed_request(client, "GET", endpoint, Dict{String, String}())
    return response
end

# ============================================================================
# 辅助函数
# ============================================================================

"""
    print_order_stats(client::LiveOrderClient)

打印订单统计
"""
function print_order_stats(client::LiveOrderClient)
    println("\n" * "="^70)
    println("订单统计")
    println("="^70)
    println("  发送订单: $(client.orders_sent)")
    println("  成交订单: $(client.orders_filled)")
    println("  拒绝订单: $(client.orders_rejected)")
    if client.orders_sent > 0
        println("  成交率: $(round(client.orders_filled/client.orders_sent*100, digits=2))%")
    end
    println("="^70)
end