# examples/test_market_data.jl

"""
测试市场数据获取（不需要API密钥）
"""

using PassivbotJL
using Dates
using DataFrames

# 创建一个临时配置（不需要真实API密钥）
temp_config = ExchangeConfig(
    :binance,
    "",  # 空的API密钥
    "",  # 空的API密钥
    false,  # 使用正式网（市场数据不需要密钥）
    1200,
    30,
    3
)

# 创建交易所连接
exchange = BinanceFutures(temp_config)

println("\n" * "="^70)
println("测试币安市场数据获取（无需API密钥）")
println("="^70)

# ============================================================================
# 测试1: 服务器时间
# ============================================================================
println("\n📡 测试1: 获取服务器时间")
try
    server_time = get_server_time(exchange)
    local_time = now()
    time_diff = Dates.value(local_time - server_time) / 1000
    
    println("✅ 服务器时间: $server_time")
    println("   本地时间:   $local_time")
    println("   时间差:     $(round(time_diff, digits=2))秒")
    
    if abs(time_diff) > 1.0
        println("⚠️  警告: 时间差较大")
    end
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试2: 获取K线数据
# ============================================================================
println("\n📊 测试2: 获取K线数据")
try
    # 测试不同时间周期
    for interval in ["1m", "5m", "15m"]
        klines = get_klines(exchange, :BTCUSDT, interval, 5)
        println("✅ $interval K线: $(nrow(klines)) 根")
        println("   最新: $(klines[end, :timestamp]) - 收盘价: $(klines[end, :close])")
    end
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试3: 多个交易对价格
# ============================================================================
println("\n💰 测试3: 获取多个交易对价格")
symbols = [:BTCUSDT, :ETHUSDT, :BNBUSDT]
try
    for symbol in symbols
        price = get_ticker_price(exchange, symbol)
        println("✅ $symbol: \$$price")
    end
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试4: 获取详细行情
# ============================================================================
println("\n📈 测试4: 获取BTC 24小时行情")
try
    ticker = PassivbotJL.get_ticker_24hr(exchange, :BTCUSDT)
    println("✅ BTC 24小时统计:")
    println("   当前价格:   \$$(ticker.last_price)")
    println("   24h变化:    $(round(ticker.price_change_percent, digits=2))%")
    println("   24h最高:    \$$(ticker.high)")
    println("   24h最低:    \$$(ticker.low)")
    println("   24h成交量:  $(round(ticker.volume, digits=2)) BTC")
    println("   24h成交额:  \$$(round(ticker.quote_volume, digits=2))")
catch e
    println("❌ 失败: $e")
end

println("\n" * "="^70)
println("✅ 市场数据测试完成！")
println("="^70)