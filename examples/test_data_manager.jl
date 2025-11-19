# examples/test_data_manager.jl

"""
智能数据管理器测试

测试自动选择数据源（Vision + API）的功能
"""

using Dates
using TimeZones
using DataFrames
using CSV
using Statistics

include("../src/data/data_manager.jl")

println("\n" * "="^70)
println("智能数据管理器测试")
println("="^70)

# 获取当前 UTC 时间
current_utc = DateTime(now(tz"UTC"))
println("\n当前 UTC 时间: $current_utc")
println("本地时间: $(now())")

# ============================================================================
# 测试1: 纯 Vision 数据（历史数据）
# ============================================================================

println("\n" * "="^70)
println("测试1: 纯 Vision 历史数据")
println("="^70)

# 使用已知可用的日期（3天前的数据）
start_time1 = DateTime(2024, 11, 10, 0, 0, 0)
end_time1 = DateTime(2024, 11, 12, 23, 59, 59)

println("\n时间范围: $start_time1 到 $end_time1")
println("预期数据源: 100% Vision")

df1 = fetch_data(
    "BTCUSDT",
    start_time1,
    end_time1,
    market=:futures,
    use_cache=true,
    verbose=true
)

println("\n结果:")
if nrow(df1) > 0
    println("  ✅ 成功获取 $(nrow(df1)) 笔交易")
    println("  时间跨度: $(df1[end, :timestamp] - df1[1, :timestamp])")
    println("  数据完整性: $(check_data_completeness(df1, start_time1, end_time1))")
    
    # 保存样本
    mkpath("data/manager_samples")
    CSV.write("data/manager_samples/vision_only_sample.csv", first(df1, 10000))
    println("  💾 已保存样本: data/manager_samples/vision_only_sample.csv")
else
    println("  ❌ 无数据")
end

# ============================================================================
# 测试2: 混合数据（Vision + API）
# ============================================================================

println("\n\n" * "="^70)
println("测试2: 混合数据（Vision 历史 + API 最新）")
println("="^70)

# 从3天前到现在（部分来自Vision，部分来自API）
vision_cutoff = today() - Day(3)

# 修复：正确构造 DateTime
start_date2 = vision_cutoff - Day(1)
start_time2 = DateTime(start_date2)  # Date 转 DateTime（午夜）
end_time2 = current_utc - Hour(1)  # 使用 UTC 时间，1小时前

println("\n时间范围: $start_time2 到 $end_time2")
println("Vision 截止日期: $vision_cutoff")
println("预期数据源: Vision ($(Date(start_time2)) 到 $vision_cutoff) + API ($vision_cutoff 到 $(Date(end_time2)))")

println("\n⚠️  注意：这会尝试从 API 下载最新数据")

df2 = fetch_data(
    "BTCUSDT",
    start_time2,
    end_time2,
    market=:futures,
    use_cache=true,
    verbose=true
)

println("\n结果:")
if nrow(df2) > 0
    println("  ✅ 成功获取 $(nrow(df2)) 笔交易")
    
    # 分析数据来源
    vision_data = df2[Date.(df2.timestamp) .<= vision_cutoff, :]
    api_data = df2[Date.(df2.timestamp) .> vision_cutoff, :]
    
    println("\n数据来源分析:")
    println("  Vision 数据: $(nrow(vision_data)) 笔 ($(round(nrow(vision_data)/nrow(df2)*100, digits=1))%)")
    println("  API 数据: $(nrow(api_data)) 笔 ($(round(nrow(api_data)/nrow(df2)*100, digits=1))%)")
    
    if nrow(vision_data) > 0
        println("\n  Vision 时间范围: $(vision_data[1, :timestamp]) 到 $(vision_data[end, :timestamp])")
    end
    
    if nrow(api_data) > 0
        println("  API 时间范围: $(api_data[1, :timestamp]) 到 $(api_data[end, :timestamp])")
    end
    
    # 保存样本
    CSV.write("data/manager_samples/mixed_sample.csv", first(df2, 10000))
    println("\n  💾 已保存样本: data/manager_samples/mixed_sample.csv")
else
    println("  ❌ 无数据")
end

# ============================================================================
# 测试3: 为回测准备数据（带缓存）
# ============================================================================

println("\n\n" * "="^70)
println("测试3: 为回测准备数据（带缓存）")
println("="^70)

start_time3 = DateTime(2024, 11, 11, 0, 0, 0)
end_time3 = DateTime(2024, 11, 11, 23, 59, 59)

println("\n时间范围: $start_time3 到 $end_time3")

println("\n第一次调用（会下载并缓存）:")
time_start = time()
df3 = fetch_data_for_backtest(
    "BTCUSDT",
    start_time3,
    end_time3,
    market=:futures
)
time_first = time() - time_start

println("\n第二次调用（从缓存加载）:")
time_start = time()
df3_cached = fetch_data_for_backtest(
    "BTCUSDT",
    start_time3,
    end_time3,
    market=:futures
)
time_cached = time() - time_start

println("\n验证缓存:")
println("  第一次数据量: $(nrow(df3))")
println("  第二次数据量: $(nrow(df3_cached))")
println("  数据一致: $(nrow(df3) == nrow(df3_cached) ? "✅" : "❌")")
println("  第一次耗时: $(round(time_first, digits=2)) 秒")
println("  第二次耗时: $(round(time_cached, digits=2)) 秒")
if time_cached > 0
    println("  加速比: $(round(time_first/time_cached, digits=1))x")
end

# ============================================================================
# 测试4: 多交易对准备
# ============================================================================

println("\n\n" * "="^70)
println("测试4: 多交易对数据准备")
println("="^70)

symbols = ["BTCUSDT", "ETHUSDT", "BNBUSDT"]
start_time4 = DateTime(2024, 11, 12, 0, 0, 0)
end_time4 = DateTime(2024, 11, 12, 12, 0, 0)

println("\n交易对: $(join(symbols, ", "))")
println("时间范围: $start_time4 到 $end_time4")

data_dict = prepare_multiple_symbols(
    symbols,
    start_time4,
    end_time4,
    market=:futures
)

println("\n结果:")
let total_trades = 0
    for (symbol, df) in sort(collect(data_dict), by=x->x[1])
        trades = nrow(df)
        total_trades += trades
        println("  $symbol: $(trades) 笔交易")
        
        if trades > 0
            println("    时间范围: $(df[1, :timestamp]) 到 $(df[end, :timestamp])")
            println("    价格范围: \$$(round(minimum(df.price), digits=2)) - \$$(round(maximum(df.price), digits=2))")
        end
    end
    
    println("\n总计: $total_trades 笔交易")
end

# ============================================================================
# 测试5: 仅 API 数据（最新数据）
# ============================================================================

println("\n\n" * "="^70)
println("测试5: 仅 API 数据（最新1小时）")
println("="^70)

end_time5 = current_utc
start_time5 = end_time5 - Hour(1)

println("\n时间范围 (UTC): $start_time5 到 $end_time5")
println("预期数据源: 100% API")

df5 = fetch_data(
    "BTCUSDT",
    start_time5,
    end_time5,
    market=:spot,  # 使用 Spot 市场（API 更稳定）
    use_cache=true,
    verbose=true
)

println("\n结果:")
if nrow(df5) > 0
    println("  ✅ 成功获取 $(nrow(df5)) 笔交易")
    println("  时间范围: $(df5[1, :timestamp]) 到 $(df5[end, :timestamp])")
    println("  价格范围: \$$(round(minimum(df5.price), digits=2)) - \$$(round(maximum(df5.price), digits=2))")
    
    # 计算价格变化
    price_change = df5[end, :price] - df5[1, :price]
    price_change_pct = (price_change / df5[1, :price]) * 100
    println("  价格变化: \$$(round(price_change, digits=2)) ($(round(price_change_pct, digits=2))%)")
    
    # 买卖统计
    buy_count = count(.!df5.is_buyer_maker)
    sell_count = count(df5.is_buyer_maker)
    println("\n  买卖统计:")
    println("    主动买入: $buy_count ($(round(buy_count/nrow(df5)*100, digits=1))%)")
    println("    主动卖出: $sell_count ($(round(sell_count/nrow(df5)*100, digits=1))%)")
    
    # 保存样本
    CSV.write("data/manager_samples/api_only_sample.csv", df5)
    println("\n  💾 已保存: data/manager_samples/api_only_sample.csv")
else
    println("  ❌ 无数据")
end

# ============================================================================
# 测试6: 数据完整性检查
# ============================================================================

println("\n\n" * "="^70)
println("测试6: 数据完整性检查")
println("="^70)

# 使用测试1的数据
if nrow(df1) > 0
    println("\n检查数据: BTCUSDT $(start_time1) 到 $(end_time1)")
    
    # 时间连续性
    time_diffs = diff([Dates.value(t) for t in df1.timestamp])
    avg_diff = mean(time_diffs)
    max_diff = maximum(time_diffs)
    
    println("\n时间连续性:")
    println("  平均间隔: $(round(avg_diff, digits=2)) ms")
    println("  最大间隔: $(round(max_diff, digits=2)) ms ($(round(max_diff/1000, digits=2)) 秒)")
    
    # 价格连续性
    price_changes = abs.(diff(df1.price) ./ df1.price[1:end-1])
    max_price_change = maximum(price_changes) * 100
    
    println("\n价格连续性:")
    println("  最大单笔变化: $(round(max_price_change, digits=4))%")
    
    # 数据量统计
    total_volume = sum(df1.quantity)
    avg_volume = mean(df1.quantity)
    
    println("\n成交量统计:")
    println("  总成交量: $(round(total_volume, digits=4)) BTC")
    println("  平均成交量: $(round(avg_volume, digits=6)) BTC")
    println("  最大单笔: $(round(maximum(df1.quantity), digits=4)) BTC")
    println("  最小单笔: $(round(minimum(df1.quantity), digits=8)) BTC")
    
    # 买卖平衡
    buy_volume = sum(df1[.!df1.is_buyer_maker, :quantity])
    sell_volume = sum(df1[df1.is_buyer_maker, :quantity])
    
    println("\n买卖平衡:")
    println("  买入量: $(round(buy_volume, digits=4)) BTC ($(round(buy_volume/total_volume*100, digits=1))%)")
    println("  卖出量: $(round(sell_volume, digits=4)) BTC ($(round(sell_volume/total_volume*100, digits=1))%)")
else
    println("  ⚠️  没有数据可供检查")
end

# ============================================================================
# 测试总结
# ============================================================================

println("\n\n" * "="^70)
println("测试总结")
println("="^70)

test_results = [
    ("纯 Vision 数据", nrow(df1) > 0),
    ("混合数据 (Vision + API)", nrow(df2) > 0),
    ("回测数据准备（缓存）", nrow(df3) > 0 && nrow(df3) == nrow(df3_cached)),
    ("多交易对准备", length(data_dict) == length(symbols)),
    ("仅 API 数据", nrow(df5) > 0),
    ("数据完整性检查", nrow(df1) > 0)
]

passed = count(x -> x[2], test_results)
total = length(test_results)

println("\n测试结果: $passed / $total 通过\n")

for (name, result) in test_results
    status = result ? "✅" : "❌"
    println("  $status $name")
end

if passed == total
    println("\n🎉 所有测试通过！")
else
    println("\n⚠️  部分测试失败")
end

# ============================================================================
# 生成的文件统计
# ============================================================================

println("\n" * "="^70)
println("生成的文件")
println("="^70)

if isdir("data/manager_samples")
    println("\n📂 data/manager_samples:")
    files = readdir("data/manager_samples", join=true)
    
    let total_size = 0
        for file in sort(files)
            if isfile(file)
                size_kb = stat(file).size / 1024
                total_size += size_kb
                println("  📄 $(basename(file)) ($(round(size_kb, digits=2)) KB)")
            end
        end
        
        if total_size > 0
            println("\n  总计: $(round(total_size / 1024, digits=2)) MB")
        end
    end
end

if isdir("data/backtest_cache")
    println("\n📂 data/backtest_cache:")
    files = readdir("data/backtest_cache", join=true)
    
    let cache_size = 0, cache_count = 0
        for file in sort(files)
            if isfile(file)
                size_mb = stat(file).size / (1024 * 1024)
                cache_size += size_mb
                cache_count += 1
                println("  📄 $(basename(file)) ($(round(size_mb, digits=2)) MB)")
            end
        end
        
        if cache_count > 0
            println("\n  总计: $cache_count 个文件, $(round(cache_size, digits=2)) MB")
        end
    end
end

println("\n" * "="^70)
println("✅ 测试完成！")
println("="^70)

println("\n提示:")
println("  • Vision 数据: 快速、完整，适合历史回测")
println("  • API 数据: 实时、最新，适合实盘或最新回测")
println("  • 数据管理器会自动选择最优数据源")
println("  • 缓存系统可以加速重复查询")
println("\n使用缓存管理:")
println("  • 查看缓存: get_cache_info()")
println("  • 清理缓存: clear_backtest_cache(older_than_days=7)")