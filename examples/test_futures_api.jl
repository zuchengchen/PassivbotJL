# examples/test_futures_api.jl

"""
Binance Futures API 专项测试

专门诊断 Futures API 问题
"""

using Dates
using TimeZones
using DataFrames
using HTTP
using JSON3

include("../src/data/binance_api.jl")

println("\n" * "="^70)
println("Binance Futures API 专项测试")
println("="^70)

# 获取当前 UTC 时间
current_utc = DateTime(now(tz"UTC"))
println("\n当前 UTC 时间: $current_utc")
println("本地时间: $(now())")

# ============================================================================
# 测试1: 直接访问 Futures API（原始 HTTP）
# ============================================================================

println("\n" * "="^70)
println("测试1: 直接访问 Futures API（原始 HTTP）")
println("="^70)

futures_bases = [
    "https://fapi.binance.com",
    "https://fapi1.binance.com",
    "https://fapi2.binance.com"
]

println("\n测试所有 Futures 端点...")

for (idx, base_url) in enumerate(futures_bases)
    println("\n尝试 $idx: $base_url")
    
    # 测试 ping
    try
        url = "$base_url/fapi/v1/ping"
        println("  测试 ping: $url")
        
        response = HTTP.get(url, readtimeout=10)
        println("  ✅ Ping 成功: $(response.status)")
        
    catch e
        println("  ❌ Ping 失败: $e")
    end
    
    # 测试 time
    try
        url = "$base_url/fapi/v1/time"
        println("  测试 time: $url")
        
        response = HTTP.get(url, readtimeout=10)
        body = String(response.body)
        
        println("  ✅ Time 成功: $(response.status)")
        println("  响应: $body")
        
        data = JSON3.read(body)
        server_time = unix2datetime(data.serverTime / 1000)
        println("  服务器时间: $server_time")
        
    catch e
        println("  ❌ Time 失败: $e")
    end
    
    # 测试 exchangeInfo
    try
        url = "$base_url/fapi/v1/exchangeInfo"
        println("  测试 exchangeInfo: $url")
        
        response = HTTP.get(url, readtimeout=10)
        println("  ✅ ExchangeInfo 成功: $(response.status)")
        println("  响应大小: $(length(response.body)) bytes")
        
    catch e
        println("  ❌ ExchangeInfo 失败: $e")
    end
end

# ============================================================================
# 测试2: aggTrades 端点（不同时间范围）
# ============================================================================

println("\n\n" * "="^70)
println("测试2: aggTrades 端点（不同参数）")
println("="^70)

base_url = "https://fapi.binance.com"
symbol = "BTCUSDT"

# 测试1: 只用 limit，不用时间
println("\n尝试1: 只用 limit（最新1000笔）")
try
    url = "$base_url/fapi/v1/aggTrades?symbol=$symbol&limit=1000"
    println("  URL: $url")
    
    response = HTTP.get(url, readtimeout=10)
    body = String(response.body)
    
    println("  ✅ 成功: $(response.status)")
    println("  响应大小: $(length(body)) bytes")
    
    if !isempty(body)
        data = JSON3.read(body)
        println("  数据条数: $(length(data))")
        
        if length(data) > 0
            first_trade = data[1]
            last_trade = data[end]
            
            println("  第一笔: $(unix2datetime(first_trade.T / 1000))")
            println("  最后笔: $(unix2datetime(last_trade.T / 1000))")
        end
    else
        println("  ⚠️  响应为空")
    end
    
catch e
    println("  ❌ 失败: $e")
end

# 测试2: 使用 fromId
println("\n尝试2: 使用 fromId")
try
    url = "$base_url/fapi/v1/aggTrades?symbol=$symbol&limit=100"
    println("  获取最新数据以找到有效的 ID...")
    
    response = HTTP.get(url, readtimeout=10)
    body = String(response.body)
    
    if !isempty(body)
        data = JSON3.read(body)
        if length(data) > 0
            from_id = data[1].a  # 第一笔交易的 ID
            
            url2 = "$base_url/fapi/v1/aggTrades?symbol=$symbol&fromId=$from_id&limit=100"
            println("  URL: $url2")
            
            response2 = HTTP.get(url2, readtimeout=10)
            body2 = String(response2.body)
            
            println("  ✅ 成功: $(response2.status)")
            println("  响应大小: $(length(body2)) bytes")
            
            if !isempty(body2)
                data2 = JSON3.read(body2)
                println("  数据条数: $(length(data2))")
            end
        end
    end
    
catch e
    println("  ❌ 失败: $e")
end

# 测试3: 使用最近的时间范围（最近10分钟）
println("\n尝试3: 最近10分钟（UTC 时间）")

# 使用服务器时间
try
    # 先获取服务器时间
    time_url = "$base_url/fapi/v1/time"
    time_response = HTTP.get(time_url, readtimeout=10)
    time_data = JSON3.read(String(time_response.body))
    server_time = unix2datetime(time_data.serverTime / 1000)
    
    println("  服务器时间: $server_time")
    
    # 使用服务器时间计算范围
    end_time = server_time
    start_time = end_time - Minute(10)
    
    start_ms = Int64(datetime2unix(start_time) * 1000)
    end_ms = Int64(datetime2unix(end_time) * 1000)
    
    url = "$base_url/fapi/v1/aggTrades?symbol=$symbol&startTime=$start_ms&endTime=$end_ms&limit=1000"
    println("  URL: $url")
    println("  时间范围: $start_time 到 $end_time")
    
    response = HTTP.get(url, readtimeout=30)
    body = String(response.body)
    
    println("  ✅ 成功: $(response.status)")
    println("  响应大小: $(length(body)) bytes")
    
    if !isempty(body)
        data = JSON3.read(body)
        println("  数据条数: $(length(data))")
        
        if length(data) > 0
            println("  第一笔: $(unix2datetime(data[1].T / 1000))")
            println("  最后笔: $(unix2datetime(data[end].T / 1000))")
        end
    else
        println("  ⚠️  响应为空")
    end
    
catch e
    println("  ❌ 失败: $e")
    if isa(e, HTTP.ExceptionRequest.StatusError)
        println("  HTTP 状态码: $(e.status)")
        println("  响应: $(String(e.response.body))")
    end
end

# 测试4: 使用昨天的时间范围
println("\n尝试4: 昨天某个小时（UTC 时间）")
try
    # 获取服务器时间
    time_url = "$base_url/fapi/v1/time"
    time_response = HTTP.get(time_url, readtimeout=10)
    time_data = JSON3.read(String(time_response.body))
    server_time = unix2datetime(time_data.serverTime / 1000)
    
    # 昨天的12:00-13:00
    yesterday = server_time - Day(1)
    start_time = DateTime(Date(yesterday), Time(12, 0, 0))
    end_time = start_time + Hour(1)
    
    start_ms = Int64(datetime2unix(start_time) * 1000)
    end_ms = Int64(datetime2unix(end_time) * 1000)
    
    url = "$base_url/fapi/v1/aggTrades?symbol=$symbol&startTime=$start_ms&endTime=$end_ms&limit=1000"
    println("  URL: $url")
    println("  时间范围: $start_time 到 $end_time")
    
    response = HTTP.get(url, readtimeout=30)
    body = String(response.body)
    
    println("  ✅ 成功: $(response.status)")
    println("  响应大小: $(length(body)) bytes")
    
    if !isempty(body)
        data = JSON3.read(body)
        println("  数据条数: $(length(data))")
        
        if length(data) > 0
            println("  第一笔: $(unix2datetime(data[1].T / 1000))")
            println("  最后笔: $(unix2datetime(data[end].T / 1000))")
        end
    else
        println("  ⚠️  响应为空")
    end
    
catch e
    println("  ❌ 失败: $e")
    if isa(e, HTTP.ExceptionRequest.StatusError)
        println("  HTTP 状态码: $(e.status)")
        println("  响应: $(String(e.response.body))")
    end
end

# ============================================================================
# 测试3: 对比 Spot vs Futures
# ============================================================================

println("\n\n" * "="^70)
println("测试3: 对比 Spot vs Futures（最新1000笔）")
println("="^70)

# Spot
println("\nSpot 市场:")
try
    url = "https://api.binance.com/api/v3/aggTrades?symbol=$symbol&limit=1000"
    
    response = HTTP.get(url, readtimeout=10)
    body = String(response.body)
    
    println("  ✅ 成功")
    println("  响应大小: $(length(body)) bytes")
    
    if !isempty(body)
        data = JSON3.read(body)
        println("  数据条数: $(length(data))")
        
        if length(data) > 0
            println("  时间范围: $(unix2datetime(data[1].T / 1000)) 到 $(unix2datetime(data[end].T / 1000))")
            println("  价格范围: $(data[1].p) - $(data[end].p)")
        end
    end
    
catch e
    println("  ❌ 失败: $e")
end

# Futures
println("\nFutures 市场:")
try
    url = "https://fapi.binance.com/fapi/v1/aggTrades?symbol=$symbol&limit=1000"
    
    response = HTTP.get(url, readtimeout=10)
    body = String(response.body)
    
    println("  ✅ 成功")
    println("  响应大小: $(length(body)) bytes")
    
    if !isempty(body)
        data = JSON3.read(body)
        println("  数据条数: $(length(data))")
        
        if length(data) > 0
            println("  时间范围: $(unix2datetime(data[1].T / 1000)) 到 $(unix2datetime(data[end].T / 1000))")
            println("  价格范围: $(data[1].p) - $(data[end].p)")
        end
    end
    
catch e
    println("  ❌ 失败: $e")
end

# ============================================================================
# 测试4: 使用我们的封装函数
# ============================================================================

println("\n\n" * "="^70)
println("测试4: 使用我们的封装函数")
println("="^70)

println("\n获取服务器时间...")
server_time = get_server_time(market=:spot)
println("服务器时间: $server_time")

# 测试最近10分钟
println("\n下载最近10分钟 Futures 数据...")
end_time = server_time
start_time = end_time - Minute(10)

println("时间范围: $start_time 到 $end_time")

try
    df = fetch_aggtrades_from_api(
        "BTCUSDT",
        start_time,
        end_time,
        market=:futures
    )
    
    if nrow(df) > 0
        println("✅ 成功获取 $(nrow(df)) 笔交易")
        println("时间范围: $(df[1, :timestamp]) 到 $(df[end, :timestamp])")
        println("价格范围: $(minimum(df.price)) - $(maximum(df.price))")
    else
        println("❌ 没有数据")
    end
    
catch e
    println("❌ 失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试总结
# ============================================================================

println("\n\n" * "="^70)
println("测试总结")
println("="^70)

println("\n请检查上面的输出，看看:")
println("  1. 哪些端点可以访问？")
println("  2. 哪些参数组合有效？")
println("  3. Spot 和 Futures 的差异在哪里？")
println("\n如果只用 limit 参数成功，说明时间参数有问题")
println("如果所有测试都失败，说明 Futures API 被封锁")