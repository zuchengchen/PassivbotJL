# examples/test_api_download.jl

"""
测试从 API 下载真实数据
"""

using Dates
include("../src/data/binance_api.jl")

println("\n" * "="^70)
println("Binance API 数据下载测试")
println("="^70)

# 启用备用域名
set_api_config(use_backup=true)

# ============================================================================
# 测试1: 下载最近1小时的 aggTrades（Spot）
# ============================================================================

println("\n" * "="^70)
println("测试1: 下载 Spot 市场最近1小时数据")
println("="^70)

end_time = now()
start_time = end_time - Hour(1)

println("\n时间范围: $start_time 到 $end_time")
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
        println("  价格范围: \$$(minimum(df_spot.price)) - \$$(maximum(df_spot.price))")
        println("  总成交量: $(round(sum(df_spot.quantity), digits=4))")
        
        # 显示前几笔
        println("\n前5笔交易:")
        for row in eachrow(first(df_spot, 5))
            side = row.is_buyer_maker ? "sell" : "buy"
            println("  $(row.timestamp) | $side | \$$(row.price) | $(row.quantity)")
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
# 测试2: 下载最近30分钟的 aggTrades（Futures）
# ============================================================================

println("\n\n" * "="^70)
println("测试2: 下载 Futures 市场最近30分钟数据")
println("="^70)

end_time2 = now()
start_time2 = end_time2 - Minute(30)

println("\n时间范围: $start_time2 到 $end_time2")
println("交易对: BTCUSDT")
println("市场: Futures")
println("\n开始下载...")

try
    df_futures = fetch_aggtrades_from_api(
        "BTCUSDT",
        start_time2,
        end_time2,
        market=:futures
    )
    
    if nrow(df_futures) > 0
        println("\n✅ 下载成功！")
        println("  数据量: $(nrow(df_futures)) 笔交易")
        println("  时间范围: $(df_futures[1, :timestamp]) 到 $(df_futures[end, :timestamp])")
        println("  价格范围: \$$(minimum(df_futures.price)) - \$$(maximum(df_futures.price))")
        
        # 统计买卖比例
        buy_count = count(.!df_futures.is_buyer_maker)
        sell_count = count(df_futures.is_buyer_maker)
        println("\n买卖统计:")
        println("  主动买入: $buy_count ($(round(buy_count/nrow(df_futures)*100, digits=1))%)")
        println("  主动卖出: $sell_count ($(round(sell_count/nrow(df_futures)*100, digits=1))%)")
        
        # 保存样本
        using CSV
        CSV.write("data/api_samples/futures_30m_sample.csv", df_futures)
        println("\n💾 已保存: data/api_samples/futures_30m_sample.csv")
        
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
println("测试3: 下载 K线数据（最近6小时，1分钟）")
println("="^70)

end_time3 = now()
start_time3 = end_time3 - Hour(6)

println("\n时间范围: $start_time3 到 $end_time3")
println("交易对: BTCUSDT")
println("周期: 1m")
println("\n开始下载...")

try
    klines = fetch_klines_from_api(
        "BTCUSDT",
        "1m",
        start_time3,
        end_time3,
        market=:spot
    )
    
    if nrow(klines) > 0
        println("\n✅ 下载成功！")
        println("  K线数量: $(nrow(klines))")
        println("  时间范围: $(klines[1, :open_time]) 到 $(klines[end, :close_time])")
        println("  价格范围: \$$(minimum(klines.low)) - \$$(maximum(klines.high))")
        
        # 显示最后几根K线
        println("\n最后3根K线:")
        for row in eachrow(last(klines, 3))
            println("  $(row.open_time) | O:\$$(row.open) H:\$$(row.high) L:\$$(row.low) C:\$$(row.close) | V:$(round(row.volume, digits=2))")
        end
        
        # 保存
        using CSV
        CSV.write("data/api_samples/klines_1m_6h.csv", klines)
        println("\n💾 已保存: data/api_samples/klines_1m_6h.csv")
        
    else
        println("\n❌ 没有数据")
    end
    
catch e
    println("\n❌ 下载失败:")
    showerror(stdout, e, catch_backtrace())
end

println("\n\n" * "="^70)
println("✅ 测试完成！")
println("="^70)