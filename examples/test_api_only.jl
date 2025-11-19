# examples/test_api_only.jl

"""
独立测试 Binance API 数据下载

专门测试 API 功能，不依赖 Vision
"""

using Dates
using TimeZones
using DataFrames
using CSV

include("../src/data/binance_api.jl")

println("\n" * "="^70)
println("Binance API 独立测试")
println("="^70)

# 获取当前 UTC 时间
current_utc = DateTime(now(tz"UTC"))
println("\n当前 UTC 时间: $current_utc")
println("本地时间: $(now())")

# 启用备用域名
set_api_config(use_backup=true)

# ============================================================================
# 测试1: 获取服务器时间
# ============================================================================

println("\n" * "="^70)
println("测试1: 获取服务器时间")
println("="^70)

println("\nSpot 市场:")
try
    spot_time = get_server_time(market=:spot)
    println("  ✅ 服务器时间: $spot_time")
    println("  本地时间差: $(round(Dates.value(now() - spot_time) / 1000, digits=2)) 秒")
catch e
    println("  ❌ 失败: $e")
end

println("\nFutures 市场:")
try
    futures_time = get_server_time(market=:futures)
    println("  ✅ 服务器时间: $futures_time")
    println("  本地时间差: $(round(Dates.value(now() - futures_time) / 1000, digits=2)) 秒")
catch e
    println("  ❌ 失败: $e")
end

# ============================================================================
# 测试2: 下载最近1小时 aggTrades（Spot）
# ============================================================================

println("\n\n" * "="^70)
println("测试2: 下载 Spot 最近1小时 aggTrades")
println("="^70)

end_time2 = current_utc
start_time2 = end_time2 - Hour(1)

println("\n时间范围 (UTC): $start_time2 到 $end_time2")
println("交易对: BTCUSDT")

try
    df_spot = fetch_aggtrades_from_api(
        "BTCUSDT",
        start_time2,
        end_time2,
        market=:spot
    )
    
    if nrow(df_spot) > 0
        println("\n✅ 下载成功！")
        println("  数据量: $(nrow(df_spot)) 笔交易")
        println("  时间范围: $(df_spot[1, :timestamp]) 到 $(df_spot[end, :timestamp])")
        println("  价格范围: \$$(round(minimum(df_spot.price), digits=2)) - \$$(round(maximum(df_spot.price), digits=2))")
        
        # 保存
        mkpath("data/api_test")
        CSV.write("data/api_test/spot_1h.csv", df_spot)
        println("  💾 已保存: data/api_test/spot_1h.csv")
    else
        println("\n❌ 没有数据")
    end
    
catch e
    println("\n❌ 下载失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试3: 下载最近1小时 aggTrades（Futures）
# ============================================================================

println("\n\n" * "="^70)
println("测试3: 下载 Futures 最近1小时 aggTrades")
println("="^70)

end_time3 = current_utc
start_time3 = end_time3 - Hour(1)

println("\n时间范围 (UTC): $start_time3 到 $end_time3")
println("交易对: BTCUSDT")

try
    df_futures = fetch_aggtrades_from_api(
        "BTCUSDT",
        start_time3,
        end_time3,
        market=:futures
    )
    
    if nrow(df_futures) > 0
        println("\n✅ 下载成功！")
        println("  数据量: $(nrow(df_futures)) 笔交易")
        println("  时间范围: $(df_futures[1, :timestamp]) 到 $(df_futures[end, :timestamp])")
        println("  价格范围: \$$(round(minimum(df_futures.price), digits=2)) - \$$(round(maximum(df_futures.price), digits=2))")
        
        # 保存
        CSV.write("data/api_test/futures_1h.csv", df_futures)
        println("  💾 已保存: data/api_test/futures_1h.csv")
    else
        println("\n❌ 没有数据")
    end
    
catch e
    println("\n❌ 下载失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试4: 下载最近30分钟（更短时间测试）
# ============================================================================

println("\n\n" * "="^70)
println("测试4: 下载 Futures 最近30分钟（更短时间）")
println("="^70)

end_time4 = current_utc
start_time4 = end_time4 - Minute(30)

println("\n时间范围 (UTC): $start_time4 到 $end_time4")
println("交易对: ETHUSDT")

try
    df_eth = fetch_aggtrades_from_api(
        "ETHUSDT",
        start_time4,
        end_time4,
        market=:futures
    )
    
    if nrow(df_eth) > 0
        println("\n✅ 下载成功！")
        println("  数据量: $(nrow(df_eth)) 笔交易")
        println("  时间范围: $(df_eth[1, :timestamp]) 到 $(df_eth[end, :timestamp])")
        println("  价格范围: \$$(round(minimum(df_eth.price), digits=2)) - \$$(round(maximum(df_eth.price), digits=2))")
        
        # 买卖统计
        buy_count = count(.!df_eth.is_buyer_maker)
        sell_count = count(df_eth.is_buyer_maker)
        println("\n  买卖统计:")
        println("    主动买入: $buy_count ($(round(buy_count/nrow(df_eth)*100, digits=1))%)")
        println("    主动卖出: $sell_count ($(round(sell_count/nrow(df_eth)*100, digits=1))%)")
        
        # 保存
        CSV.write("data/api_test/eth_30m.csv", df_eth)
        println("  💾 已保存: data/api_test/eth_30m.csv")
    else
        println("\n❌ 没有数据")
    end
    
catch e
    println("\n❌ 下载失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试5: 下载 K线数据
# ============================================================================

println("\n\n" * "="^70)
println("测试5: 下载 K线数据（最近6小时，5分钟）")
println("="^70)

end_time5 = current_utc
start_time5 = end_time5 - Hour(6)

println("\n时间范围 (UTC): $start_time5 到 $end_time5")
println("交易对: BTCUSDT")
println("周期: 5m")

try
    klines = fetch_klines_from_api(
        "BTCUSDT",
        "5m",
        start_time5,
        end_time5,
        market=:spot
    )
    
    if nrow(klines) > 0
        println("\n✅ 下载成功！")
        println("  K线数量: $(nrow(klines))")
        println("  时间范围: $(klines[1, :open_time]) 到 $(klines[end, :close_time])")
        println("  价格范围: \$$(round(minimum(klines.low), digits=2)) - \$$(round(maximum(klines.high), digits=2))")
        
        # 显示最后3根K线
        println("\n  最后3根K线:")
        for row in eachrow(last(klines, 3))
            change = row.close - row.open
            change_pct = (change / row.open) * 100
            direction = change >= 0 ? "📈" : "📉"
            
            println("    $(row.open_time) $direction | O:\$$(round(row.open, digits=2)) C:\$$(round(row.close, digits=2)) | $(round(change_pct, digits=2))%")
        end
        
        # 保存
        CSV.write("data/api_test/klines_5m_6h.csv", klines)
        println("\n  💾 已保存: data/api_test/klines_5m_6h.csv")
    else
        println("\n❌ 没有数据")
    end
    
catch e
    println("\n❌ 下载失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试6: 测试不同时间段（诊断问题）
# ============================================================================

println("\n\n" * "="^70)
println("测试6: 测试不同时间段（诊断）")
println("="^70)

# 测试最近10分钟
println("\n尝试1: 最近10分钟")
test_end = current_utc
test_start = test_end - Minute(10)
println("  时间范围: $test_start 到 $test_end")

try
    df_test = fetch_aggtrades_from_api("BTCUSDT", test_start, test_end, market=:futures)
    println("  结果: $(nrow(df_test)) 笔交易")
catch e
    println("  失败: $e")
end

# 测试昨天的某个小时
println("\n尝试2: 昨天的某个小时")
yesterday = current_utc - Day(1)
test_start2 = DateTime(Date(yesterday), Time(12, 0, 0))
test_end2 = test_start2 + Hour(1)
println("  时间范围: $test_start2 到 $test_end2")

try
    df_test2 = fetch_aggtrades_from_api("BTCUSDT", test_start2, test_end2, market=:futures)
    println("  结果: $(nrow(df_test2)) 笔交易")
catch e
    println("  失败: $e")
end

# 测试3天前的某个小时
println("\n尝试3: 3天前的某个小时")
three_days_ago = current_utc - Day(3)
test_start3 = DateTime(Date(three_days_ago), Time(12, 0, 0))
test_end3 = test_start3 + Hour(1)
println("  时间范围: $test_start3 到 $test_end3")

try
    df_test3 = fetch_aggtrades_from_api("BTCUSDT", test_start3, test_end3, market=:futures)
    println("  结果: $(nrow(df_test3)) 笔交易")
catch e
    println("  失败: $e")
end

# ============================================================================
# 测试总结
# ============================================================================

println("\n\n" * "="^70)
println("测试总结")
println("="^70)

if isdir("data/api_test")
    files = readdir("data/api_test", join=true)
    
    if !isempty(files)
        println("\n生成的文件:")
        local total_size = 0
        for file in sort(files)
            if isfile(file)
                size_kb = stat(file).size / 1024
                total_size += size_kb
                println("  📄 $(basename(file)) ($(round(size_kb, digits=2)) KB)")
            end
        end
        println("\n  总计: $(round(total_size / 1024, digits=2)) MB")
    else
        println("\n⚠️  没有生成任何文件")
    end
else
    println("\n⚠️  没有生成任何文件")
end

println("\n" * "="^70)
println("✅ 测试完成！")
println("="^70)

println("\n提示:")
println("  • 如果 Futures 失败但 Spot 成功，可能是 Futures API 限制")
println("  • 如果全部失败，检查网络或 API 访问权限")
println("  • 尝试使用 VPN 可能有帮助")