# examples/test_api_download_utc.jl

"""
测试从 API 下载真实数据（使用 UTC 时间）
"""

using Dates
using TimeZones
include("../src/data/binance_api.jl")

println("\n" * "="^70)
println("Binance API 数据下载测试（UTC 时间）")
println("="^70)

# 使用 UTC 时间
current_utc = now(tz"UTC")
current_time = DateTime(current_utc)  # 转换为 DateTime

println("\n时间信息:")
println("  UTC 时间: $current_time")
println("  本地时间: $(now())")
println("  时差: $(round((Dates.value(now()) - Dates.value(current_time)) / 3600000, digits=1)) 小时")

# 启用备用域名
set_api_config(use_backup=true)

# ============================================================================
# 测试1: 下载最近1小时的 aggTrades（Spot）
# ============================================================================

println("\n" * "="^70)
println("测试1: 下载 Spot 市场最近1小时数据")
println("="^70)

end_time = current_time
start_time = end_time - Hour(1)

println("\n时间范围 (UTC): $start_time 到 $end_time")
println("交易对: BTCUSDT")
println("市场: Spot")
println("\n开始下载...")

try
    df_spot = fetch_aggtrades_from_api(
        "BTCUSDT",
        start_time,
        end_time,
        market=:spot
    )
    
    if nrow(df_spot) > 0
        println("\n✅ 下载成功！")
        println("  数据量: $(nrow(df_spot)) 笔交易")
        println("  时间范围: $(df_spot[1, :timestamp]) 到 $(df_spot[end, :timestamp])")
        println("  价格范围: \$$(round(minimum(df_spot.price), digits=2)) - \$$(round(maximum(df_spot.price), digits=2))")
        println("  总成交量: $(round(sum(df_spot.quantity), digits=4)) BTC")
        
        # 计算价格变化
        price_change = df_spot[end, :price] - df_spot[1, :price]
        price_change_pct = (price_change / df_spot[1, :price]) * 100
        println("  价格变化: $(round(price_change, digits=2)) (\$(round(price_change_pct, digits=2))%)")
        
        # 显示前几笔
        println("\n前5笔交易:")
        for row in eachrow(first(df_spot, 5))
            side = row.is_buyer_maker ? "SELL" : "BUY "
            println("  $(row.timestamp) | $side | \$$(row.price) | $(row.quantity) BTC")
        end
        
        # 保存样本
        using CSV
        mkpath("data/api_samples")
        CSV.write("data/api_samples/spot_1h_sample.csv", df_spot)
        println("\n💾 已保存: data/api_samples/spot_1h_sample.csv")
        
    else
        println("\n❌ 没有数据")
    end
    
catch e
    println("\n❌ 下载失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试2: 下载最近30分钟的数据（ETHUSDT）
# ============================================================================

println("\n\n" * "="^70)
println("测试2: 下载 ETHUSDT 最近30分钟数据")
println("="^70)

end_time2 = current_time
start_time2 = end_time2 - Minute(30)

println("\n时间范围 (UTC): $start_time2 到 $end_time2")
println("交易对: ETHUSDT")
println("市场: Spot")
println("\n开始下载...")

try
    df_eth = fetch_aggtrades_from_api(
        "ETHUSDT",
        start_time2,
        end_time2,
        market=:spot
    )
    
    if nrow(df_eth) > 0
        println("\n✅ 下载成功！")
        println("  数据量: $(nrow(df_eth)) 笔交易")
        println("  时间范围: $(df_eth[1, :timestamp]) 到 $(df_eth[end, :timestamp])")
        println("  价格范围: \$$(round(minimum(df_eth.price), digits=2)) - \$$(round(maximum(df_eth.price), digits=2))")
        println("  总成交量: $(round(sum(df_eth.quantity), digits=2)) ETH")
        
        # 统计买卖比例
        buy_count = count(.!df_eth.is_buyer_maker)
        sell_count = count(df_eth.is_buyer_maker)
        buy_volume = sum(df_eth[.!df_eth.is_buyer_maker, :quantity])
        sell_volume = sum(df_eth[df_eth.is_buyer_maker, :quantity])
        
        println("\n买卖统计:")
        println("  主动买入: $buy_count 笔 ($(round(buy_count/nrow(df_eth)*100, digits=1))%) | 成交量: $(round(buy_volume, digits=2)) ETH")
        println("  主动卖出: $sell_count 笔 ($(round(sell_count/nrow(df_eth)*100, digits=1))%) | 成交量: $(round(sell_volume, digits=2)) ETH")
        
        # 保存样本
        using CSV
        CSV.write("data/api_samples/eth_30m_sample.csv", df_eth)
        println("\n💾 已保存: data/api_samples/eth_30m_sample.csv")
        
    else
        println("\n❌ 没有数据")
    end
    
catch e
    println("\n❌ 下载失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试3: 下载 K线数据
# ============================================================================

println("\n\n" * "="^70)
println("测试3: 下载 K线数据（最近3小时，5分钟）")
println("="^70)

end_time3 = current_time
start_time3 = end_time3 - Hour(3)

println("\n时间范围 (UTC): $start_time3 到 $end_time3")
println("交易对: BTCUSDT")
println("周期: 5m")
println("\n开始下载...")

try
    klines = fetch_klines_from_api(
        "BTCUSDT",
        "5m",
        start_time3,
        end_time3,
        market=:spot
    )
    
    if nrow(klines) > 0
        println("\n✅ 下载成功！")
        println("  K线数量: $(nrow(klines))")
        println("  时间范围: $(klines[1, :open_time]) 到 $(klines[end, :close_time])")
        println("  价格范围: \$$(round(minimum(klines.low), digits=2)) - \$$(round(maximum(klines.high), digits=2))")
        println("  总成交量: $(round(sum(klines.volume), digits=2)) BTC")
        
        # 计算涨跌
        price_start = klines[1, :open]
        price_end = klines[end, :close]
        price_change = price_end - price_start
        price_change_pct = (price_change / price_start) * 100
        
        println("\n价格变化:")
        println("  开始: \$$(round(price_start, digits=2))")
        println("  结束: \$$(round(price_end, digits=2))")
        println("  变化: \$$(round(price_change, digits=2)) ($(round(price_change_pct, digits=2))%)")
        
        # 显示最后几根K线
        println("\n最后5根K线:")
        for row in eachrow(last(klines, 5))
            change = row.close - row.open
            change_pct = (change / row.open) * 100
            direction = change >= 0 ? "📈" : "📉"
            
            println("  $(row.open_time) $direction | O:\$$(round(row.open, digits=2)) H:\$$(round(row.high, digits=2)) L:\$$(round(row.low, digits=2)) C:\$$(round(row.close, digits=2)) | $(round(change_pct, digits=2))%")
        end
        
        # 保存
        using CSV
        CSV.write("data/api_samples/klines_5m_3h.csv", klines)
        println("\n💾 已保存: data/api_samples/klines_5m_3h.csv")
        
    else
        println("\n❌ 没有数据")
    end
    
catch e
    println("\n❌ 下载失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试4: 对比不同时间周期
# ============================================================================

println("\n\n" * "="^70)
println("测试4: 下载多个时间周期 K线对比")
println("="^70)

intervals = ["1m", "5m", "15m", "1h"]
end_time4 = current_time
start_time4 = end_time4 - Hour(6)

println("\n时间范围 (UTC): $start_time4 到 $end_time4")
println("交易对: BTCUSDT")
println("周期: $(join(intervals, ", "))")

for interval in intervals
    try
        klines_test = fetch_klines_from_api(
            "BTCUSDT",
            interval,
            start_time4,
            end_time4,
            market=:spot
        )
        
        if nrow(klines_test) > 0
            println("\n  ✅ $interval: $(nrow(klines_test)) 根K线")
        else
            println("\n  ❌ $interval: 无数据")
        end
        
    catch e
        println("\n  ❌ $interval: 下载失败")
    end
    
    sleep(0.2)  # 避免请求过快
end

println("\n\n" * "="^70)
println("✅ 所有测试完成！")
println("="^70)

println("\n生成的文件:")
if isdir("data/api_samples")
    files = readdir("data/api_samples", join=true)
    for file in files
        size_kb = round(stat(file).size / 1024, digits=2)
        println("  📄 $(basename(file)) ($size_kb KB)")
    end
end