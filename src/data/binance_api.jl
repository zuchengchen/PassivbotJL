# src/data/binance_api.jl

"""
Binance API 数据下载器

从 Binance REST API 下载实时和近期数据

特性：
- 自动尝试多个备用域名
- 完整的错误处理
- 速率限制保护
- 支持现货和合约市场
- 处理不同的响应类型（对象/数组）
- 自动处理 UTC 时区
"""

using HTTP
using JSON3
using Dates
using DataFrames
using ProgressMeter
using TimeZones

# ============================================================================
# API 配置
# ============================================================================

# 主域名
const BINANCE_API_BASE = Dict(
    :spot => "https://api.binance.com",
    :futures => "https://fapi.binance.com"
)

# 备用域名列表
const BINANCE_API_BACKUP = Dict(
    :spot => [
        "https://api.binance.com",
        "https://api1.binance.com",
        "https://api2.binance.com",
        "https://api3.binance.com",
        "https://api4.binance.com"
    ],
    :futures => [
        "https://fapi.binance.com"  # 只使用主域名（备用域名返回空响应）
    ]
)

# API限制
const API_RATE_LIMIT = 1200  # 每分钟请求数
const API_WEIGHT_LIMIT = 2400  # 每分钟权重
const AGGTRADES_LIMIT = 1000  # aggTrades 每次最多返回条数
const KLINES_LIMIT = 1000     # klines 每次最多返回条数

# 全局配置
mutable struct APIConfig
    use_backup::Bool
    timeout::Int
    retry_delay::Float64
    max_retries::Int
    user_agent::String
    
    function APIConfig(;
        use_backup::Bool=true,
        timeout::Int=30,
        retry_delay::Float64=1.0,
        max_retries::Int=3,
        user_agent::String="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    )
        new(use_backup, timeout, retry_delay, max_retries, user_agent)
    end
end

const API_CONFIG = APIConfig()

# ============================================================================
# 辅助函数
# ============================================================================

"""
    set_api_config(;kwargs...)

设置 API 配置

可用参数：
- use_backup: 是否使用备用域名
- timeout: 请求超时时间（秒）
- retry_delay: 重试延迟（秒）
- max_retries: 最大重试次数
- user_agent: User-Agent 字符串
"""
function set_api_config(;
    use_backup::Union{Bool,Nothing}=nothing,
    timeout::Union{Int,Nothing}=nothing,
    retry_delay::Union{Float64,Nothing}=nothing,
    max_retries::Union{Int,Nothing}=nothing,
    user_agent::Union{String,Nothing}=nothing
)
    if !isnothing(use_backup)
        API_CONFIG.use_backup = use_backup
    end
    if !isnothing(timeout)
        API_CONFIG.timeout = timeout
    end
    if !isnothing(retry_delay)
        API_CONFIG.retry_delay = retry_delay
    end
    if !isnothing(max_retries)
        API_CONFIG.max_retries = max_retries
    end
    if !isnothing(user_agent)
        API_CONFIG.user_agent = user_agent
    end
end

"""
    get_utc_now()::DateTime

获取当前 UTC 时间
"""
function get_utc_now()::DateTime
    try
        return DateTime(now(tz"UTC"))
    catch
        # 如果 TimeZones 不可用，使用系统时间
        return now()
    end
end

# ============================================================================
# API 请求核心函数
# ============================================================================

"""
    api_request(
        endpoint::String;
        market::Symbol=:futures,
        params::Dict=Dict(),
        retry_count::Int=0
    )::Any

发送API请求（支持自动重试和备用域名）

参数：
- endpoint: API端点，如 "/fapi/v1/aggTrades"
- market: :spot 或 :futures
- params: 请求参数字典
- retry_count: 当前重试次数（内部使用）

返回：
- 解析后的JSON响应（可能是对象或数组）
"""
function api_request(
    endpoint::String;
    market::Symbol=:futures,
    params::Dict=Dict(),
    retry_count::Int=0
)::Any
    
    # 构建查询字符串
    query_string = ""
    if !isempty(params)
        query_string = "?" * join(["$k=$v" for (k, v) in params], "&")
    end
    
    # 选择要尝试的URL列表
    urls_to_try = if API_CONFIG.use_backup
        [base * endpoint * query_string for base in BINANCE_API_BACKUP[market]]
    else
        [BINANCE_API_BASE[market] * endpoint * query_string]
    end
    
    last_error = nothing
    
    # 尝试所有URL
    for (idx, url) in enumerate(urls_to_try)
        
        @debug "Trying API endpoint" url=url attempt=idx
        
        try
            response = HTTP.get(
                url,
                retry=false,
                readtimeout=API_CONFIG.timeout,
                headers=["User-Agent" => API_CONFIG.user_agent]
            )
            
            # 接受 200 和 202 状态码
            if response.status == 200 || response.status == 202
                body = String(response.body)
                
                # 检查是否为空响应
                if isempty(strip(body))
                    @debug "Empty response body, trying next endpoint" url=url
                    last_error = "Empty response"
                    continue
                end
                
                # 解析 JSON
                data = JSON3.read(body)
                @debug "API request successful" status=response.status base_url=split(url, "?")[1]
                return data
            else
                @warn "Unexpected status code" status=response.status url=url
                last_error = "HTTP $(response.status)"
                continue
            end
            
        catch e
            last_error = e
            
            if isa(e, HTTP.ExceptionRequest.StatusError)
                status = e.status
                
                if status == 403
                    @debug "403 Forbidden (IP restricted or geo-blocked)" url=url
                    continue
                    
                elseif status == 429
                    @warn "Rate limit exceeded (429), waiting..."
                    sleep(60)
                    
                    if retry_count < API_CONFIG.max_retries
                        return api_request(
                            endpoint,
                            market=market,
                            params=params,
                            retry_count=retry_count+1
                        )
                    end
                    
                elseif status == 418
                    @error "IP banned (418)"
                    break
                    
                elseif status >= 500
                    @warn "Server error ($status), retrying..."
                    sleep(API_CONFIG.retry_delay)
                    continue
                    
                else
                    @warn "HTTP error" status=status url=url
                    continue
                end
            else
                @debug "Request failed" error=e url=url
                sleep(API_CONFIG.retry_delay)
                continue
            end
        end
    end
    
    # 所有URL都失败了
    @error "All API endpoints failed" last_error=last_error
    
    if !isnothing(last_error)
        if isa(last_error, Exception)
            throw(last_error)
        else
            error("API request failed: $last_error")
        end
    end
    
    # 返回空字典
    return Dict()
end

# ============================================================================
# aggTrades 下载
# ============================================================================

"""
    fetch_aggtrades_from_api(
        symbol::String,
        start_time::DateTime,
        end_time::DateTime;
        market::Symbol=:futures
    )::DataFrame

从API下载aggTrades数据

参数：
- symbol: 交易对，如 "BTCUSDT"
- start_time: 开始时间（UTC）
- end_time: 结束时间（UTC）
- market: :spot 或 :futures

返回：
- DataFrame 包含交易数据
"""
function fetch_aggtrades_from_api(
    symbol::String,
    start_time::DateTime,
    end_time::DateTime;
    market::Symbol=:futures
)::DataFrame
    
    @info "Fetching aggTrades from API" symbol=symbol start_time=start_time end_time=end_time market=market
    
    # 转换为毫秒时间戳
    start_ms = Int64(datetime2unix(start_time) * 1000)
    end_ms = Int64(datetime2unix(end_time) * 1000)
    
    # 选择正确的端点
    endpoint = market == :spot ? "/api/v3/aggTrades" : "/fapi/v1/aggTrades"
    
    all_trades = []
    current_start = start_ms
    request_count = 0
    
    # 估算需要的请求次数
    time_range_hours = Dates.value(end_time - start_time) / (1000 * 3600)
    estimated_requests = max(1, Int(ceil(time_range_hours / 2)))
    
    p = Progress(estimated_requests, desc="Downloading $symbol from API...")
    
    while current_start < end_ms
        
        # 构建参数
        params = Dict(
            "symbol" => symbol,
            "startTime" => string(current_start),
            "endTime" => string(end_ms),
            "limit" => string(AGGTRADES_LIMIT)
        )
        
        try
            # 请求数据
            response = api_request(endpoint, market=market, params=params)
            
            # 确保响应是数组类型
            trades = if isa(response, AbstractArray)
                collect(response)
            elseif isa(response, AbstractDict) && isempty(response)
                []
            else
                @warn "Unexpected response type" type=typeof(response)
                []
            end
            
            request_count += 1
            
            if isempty(trades)
                @debug "No more trades available"
                break
            end
            
            append!(all_trades, trades)
            
            # 更新起始时间（使用最后一笔交易的时间+1ms）
            last_trade = trades[end]
            last_time = haskey(last_trade, :T) ? last_trade.T : last_trade["T"]
            current_start = last_time + 1
            
            next!(p)
            
            # 限速：避免超过API限制
            sleep(0.1)
            
            # 如果一次请求返回的数据少于limit，说明已经到达终点
            if length(trades) < AGGTRADES_LIMIT
                @debug "Received less than limit, reached end"
                break
            end
            
        catch e
            @error "Failed to fetch trades" error=e current_start=current_start
            break
        end
        
        # 安全检查：避免无限循环
        if request_count > 10000
            @warn "Too many requests ($request_count), stopping"
            break
        end
    end
    
    finish!(p)
    
    if isempty(all_trades)
        @warn "No trades downloaded from API"
        return DataFrame(
            agg_trade_id = Int64[],
            price = Float64[],
            quantity = Float64[],
            first_trade_id = Int64[],
            last_trade_id = Int64[],
            timestamp = DateTime[],
            is_buyer_maker = Bool[],
            symbol = String[]
        )
    end
    
    @info "Downloaded trades from API" count=length(all_trades) requests=request_count
    
    # 转换为DataFrame
    try
        df = DataFrame(
            agg_trade_id = [Int64(haskey(t, :a) ? t.a : t["a"]) for t in all_trades],
            price = [parse(Float64, string(haskey(t, :p) ? t.p : t["p"])) for t in all_trades],
            quantity = [parse(Float64, string(haskey(t, :q) ? t.q : t["q"])) for t in all_trades],
            first_trade_id = [Int64(haskey(t, :f) ? t.f : t["f"]) for t in all_trades],
            last_trade_id = [Int64(haskey(t, :l) ? t.l : t["l"]) for t in all_trades],
            timestamp = [unix2datetime((haskey(t, :T) ? t.T : t["T"]) / 1000) for t in all_trades],
            is_buyer_maker = [haskey(t, :m) ? t.m : t["m"] for t in all_trades],
            symbol = fill(symbol, length(all_trades))
        )
        
        # 排序并去重
        sort!(df, :timestamp)
        unique!(df, :agg_trade_id)
        
        return df
        
    catch e
        @error "Failed to parse trades data" error=e
        return DataFrame()
    end
end

# ============================================================================
# K线下载
# ============================================================================

"""
    fetch_klines_from_api(
        symbol::String,
        interval::String,
        start_time::DateTime,
        end_time::DateTime;
        market::Symbol=:futures
    )::DataFrame

从API下载K线数据

参数：
- symbol: 交易对
- interval: 时间周期（1m, 5m, 15m, 1h, 4h, 1d等）
- start_time: 开始时间（UTC）
- end_time: 结束时间（UTC）
- market: :spot 或 :futures

返回：
- DataFrame 包含K线数据
"""
function fetch_klines_from_api(
    symbol::String,
    interval::String,
    start_time::DateTime,
    end_time::DateTime;
    market::Symbol=:futures
)::DataFrame
    
    @info "Fetching klines from API" symbol=symbol interval=interval start_time=start_time end_time=end_time
    
    start_ms = Int64(datetime2unix(start_time) * 1000)
    end_ms = Int64(datetime2unix(end_time) * 1000)
    
    # 选择正确的端点
    endpoint = market == :spot ? "/api/v3/klines" : "/fapi/v1/klines"
    
    all_klines = []
    current_start = start_ms
    request_count = 0
    
    while current_start < end_ms
        
        params = Dict(
            "symbol" => symbol,
            "interval" => interval,
            "startTime" => string(current_start),
            "endTime" => string(end_ms),
            "limit" => string(KLINES_LIMIT)
        )
        
        try
            response = api_request(endpoint, market=market, params=params)
            
            # 确保响应是数组
            klines = if isa(response, AbstractArray)
                collect(response)
            elseif isa(response, AbstractDict) && isempty(response)
                []
            else
                @warn "Unexpected response type for klines" type=typeof(response)
                []
            end
            
            request_count += 1
            
            if isempty(klines)
                break
            end
            
            append!(all_klines, klines)
            
            # 使用 close_time + 1ms
            last_kline = klines[end]
            current_start = Int64(last_kline[7]) + 1
            
            sleep(0.1)
            
            # 如果返回数据少于limit，说明已经到达终点
            if length(klines) < KLINES_LIMIT
                break
            end
            
        catch e
            @error "Failed to fetch klines" error=e
            break
        end
        
        # 安全检查
        if request_count > 5000
            @warn "Too many requests for klines, stopping"
            break
        end
    end
    
    if isempty(all_klines)
        @warn "No klines downloaded from API"
        return DataFrame()
    end
    
    @info "Downloaded klines from API" count=length(all_klines) requests=request_count
    
    # 转换为DataFrame
    try
        df = DataFrame(
            open_time = [unix2datetime(Int64(k[1]) / 1000) for k in all_klines],
            open = [parse(Float64, string(k[2])) for k in all_klines],
            high = [parse(Float64, string(k[3])) for k in all_klines],
            low = [parse(Float64, string(k[4])) for k in all_klines],
            close = [parse(Float64, string(k[5])) for k in all_klines],
            volume = [parse(Float64, string(k[6])) for k in all_klines],
            close_time = [unix2datetime(Int64(k[7]) / 1000) for k in all_klines],
            quote_volume = [parse(Float64, string(k[8])) for k in all_klines],
            count = [Int64(k[9]) for k in all_klines],
            taker_buy_volume = [parse(Float64, string(k[10])) for k in all_klines],
            taker_buy_quote_volume = [parse(Float64, string(k[11])) for k in all_klines],
            symbol = fill(symbol, length(all_klines))
        )
        
        return df
        
    catch e
        @error "Failed to parse klines data" error=e
        return DataFrame()
    end
end

# ============================================================================
# 服务器时间和交易所信息
# ============================================================================

"""
    get_server_time(;market::Symbol=:futures)::DateTime

获取Binance服务器时间（UTC）

参数：
- market: :spot 或 :futures

返回：
- DateTime 服务器时间（UTC）
"""
function get_server_time(;market::Symbol=:futures)::DateTime
    
    try
        # 选择正确的端点
        endpoint = market == :spot ? "/api/v3/time" : "/fapi/v1/time"
        
        data = api_request(endpoint, market=market)
        
        # 处理字典或对象类型
        if isa(data, AbstractDict) || isa(data, JSON3.Object)
            server_time_ms = haskey(data, :serverTime) ? data.serverTime : 
                             haskey(data, "serverTime") ? data["serverTime"] : nothing
            
            if !isnothing(server_time_ms)
                return unix2datetime(server_time_ms / 1000)
            end
        end
        
        @warn "Could not parse server time" data=data
        
    catch e
        @error "Failed to get server time" error=e
    end
    
    # 失败时返回 UTC 时间
    return get_utc_now()
end

"""
    get_exchange_info(;market::Symbol=:futures)::Dict

获取交易所信息

参数：
- market: :spot 或 :futures

返回：
- Dict 包含交易所信息
"""
function get_exchange_info(;market::Symbol=:futures)::Dict
    
    try
        # 选择正确的端点
        endpoint = market == :spot ? "/api/v3/exchangeInfo" : "/fapi/v1/exchangeInfo"
        
        data = api_request(endpoint, market=market)
        return Dict(data)
        
    catch e
        @error "Failed to get exchange info" error=e
    end
    
    return Dict()
end

"""
    get_symbol_info(symbol::String; market::Symbol=:futures)::Union{Dict, Nothing}

获取指定交易对的信息

参数：
- symbol: 交易对名称
- market: :spot 或 :futures

返回：
- Dict 交易对信息，如果未找到则返回 nothing
"""
function get_symbol_info(symbol::String; market::Symbol=:futures)::Union{Dict, Nothing}
    
    info = get_exchange_info(market=market)
    
    if haskey(info, :symbols) || haskey(info, "symbols")
        symbols = haskey(info, :symbols) ? info.symbols : info["symbols"]
        
        for s in symbols
            sym = haskey(s, :symbol) ? s.symbol : s["symbol"]
            if sym == symbol
                return Dict(s)
            end
        end
    end
    
    return nothing
end

# ============================================================================
# 便捷函数
# ============================================================================

"""
    test_api_connection(;market::Symbol=:futures)::Bool

测试API连接

参数：
- market: :spot 或 :futures

返回：
- Bool 连接是否成功
"""
function test_api_connection(;market::Symbol=:futures)::Bool
    
    println("Testing API connection to Binance $market...")
    
    try
        server_time = get_server_time(market=market)
        local_time = get_utc_now()
        
        time_diff = Dates.value(local_time - server_time) / 1000
        
        println("✅ Connection successful!")
        println("   Server time (UTC): $server_time")
        println("   Local UTC time:    $local_time")
        println("   Time diff:         $(round(time_diff, digits=2)) seconds")
        
        if abs(time_diff) > 60
            println("   ⚠️  Time difference > 1 minute ($(round(time_diff, digits=2)) seconds)")
        end
        
        return true
        
    catch e
        println("❌ Connection failed!")
        println("   Error: $e")
        
        if isa(e, HTTP.ExceptionRequest.StatusError) && e.status == 403
            println("\n⚠️  403 Forbidden - Possible causes:")
            println("   1. IP address is geo-blocked")
            println("   2. Using VPN/Proxy might help")
        end
        
        return false
    end
end

"""
    print_api_status()

打印API配置和状态
"""
function print_api_status()
    
    println("\n" * "="^70)
    println("Binance API Configuration")
    println("="^70)
    
    println("\nSettings:")
    println("  Use backup domains: $(API_CONFIG.use_backup)")
    println("  Timeout: $(API_CONFIG.timeout) seconds")
    println("  Retry delay: $(API_CONFIG.retry_delay) seconds")
    println("  Max retries: $(API_CONFIG.max_retries)")
    
    println("\nAvailable endpoints:")
    println("  Spot:    $(join(BINANCE_API_BACKUP[:spot], "\n           "))")
    println("  Futures: $(join(BINANCE_API_BACKUP[:futures], "\n           "))")
    
    println("\nTesting connections...")
    
    println("\nSpot market:")
    test_api_connection(market=:spot)
    
    println("\nFutures market:")
    test_api_connection(market=:futures)
    
    println("\n" * "="^70)
end