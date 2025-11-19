# examples/test_api.jl

"""
测试 Binance API 下载器
"""

using Dates
include("../src/data/binance_api.jl")

println("\n" * "="^70)
println("Binance API 下载器测试")
println("="^70)

# ============================================================================
# 测试1: 获取服务器时间
# ============================================================================

println("\n测试1: 获取服务器时间")
println("-"^70)

server_time = get_server_time(market=:futures)
local_time = now()

println("服务器时间: $server_time")
println("本地时间:   $local_time")
println("时差:       $(Dates.value(local_time - server_time) / 1000) 秒")

# ============================================================================
# 测试2: 获取交易对信息
# ============================================================================

println("\n测试2: 获取交易对信息")
println("-"^70)

symbol_info = get_symbol_info("BTCUSDT", market=:futures)

if !isnothing(symbol_info)
    println("✅ 找到交易对信息:")
    println("  交易对: $(symbol_info["symbol"])")
    println("  状态: $(symbol_info["status"])")
    
    if haskey(symbol_info, "pricePrecision")
        println("  价格精度: $(symbol_info["pricePrecision"])")
    end
    
    if haskey(symbol_info, "quantityPrecision")
        println("  数量精度: $(symbol_info["quantityPrecision"])")
    end
else
    println("❌ 未找到交易对信息")
end

# ============================================================================
# 测试3: 下载最近的 aggTrades
# ============================================================================

println("\n测试3: 下载最近的 aggTrades（最近1小时）")
println("-"^70)

end_time = now()
start_time = end_time - Hour(1)

println("时间范围: $start_time 到 $end_time")
println("开始下载...")

df = fetch_aggtrades_from_api(
    "BTCUSDT",
    start_time,
    end_time,
    market=:futures
)

if nrow(df) > 0
    println("\n✅ 下载成功！")
    println("  数据量: $(nrow(df)) 笔交易")
    println("  时间范围: $(df[1, :timestamp]) 到 $(df[end, :timestamp])")
    println("  价格范围: \$$(minimum(df.price)) - \$$(maximum(df.price))")
    println("  总成交量: $(sum(df.quantity))")
    
    # 显示前几笔
    println("\n前5笔交易:")
    for row in eachrow(first(df, 5))
        println("  $(row.timestamp) | $(row.side) | $(row.price) | $(row.quantity)")
    end
else
    println("❌ 没有数据")
end

# ============================================================================
# 测试4: 下载K线
# ============================================================================

println("\n测试4: 下载K线数据（最近6小时，1分钟）")
println("-"^70)

end_time2 = now()
start_time2 = end_time2 - Hour(6)

klines = fetch_klines_from_api(
    "BTCUSDT",
    "1m",
    start_time2,
    end_time2,
    market=:futures
)

if nrow(klines) > 0
    println("\n✅ 下载成功！")
    println("  K线数量: $(nrow(klines))")
    println("  时间范围: $(klines[1, :open_time]) 到 $(klines[end, :close_time])")
    println("  价格范围: \$$(minimum(klines.low)) - \$$(maximum(klines.high))")
    
    # 显示最后几根K线
    println("\n最后3根K线:")
    for row in eachrow(last(klines, 3))
        println("  $(row.open_time) | O:$(row.open) H:$(row.high) L:$(row.low) C:$(row.close) | V:$(row.volume)")
    end
else
    println("❌ 没有数据")
end

println("\n" * "="^70)
println("✅ 测试完成！")
println("="^70)