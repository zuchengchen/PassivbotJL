# examples/test_binance_vision_quick.jl

"""
快速测试 - 只测试核心功能
"""

using Dates
include("../src/data/binance_vision.jl")

println("\n" * "="^70)
println("Binance Vision 快速测试")
println("="^70)

# 测试1: 下载昨天的数据
println("\n📊 下载昨天的BTCUSDT数据...")

yesterday = today() - Day(1)

df = download_daily_aggtrades("BTCUSDT", yesterday, market=:futures)

if nrow(df) > 0
    println("✅ 成功！")
    println("  数据量: $(nrow(df)) 笔交易")
    println("  价格范围: $(minimum(df.price)) - $(maximum(df.price))")
    println("  时间范围: $(df[1, :timestamp]) 到 $(df[end, :timestamp])")
    
    print_data_summary(df)
    
    # 保存
    mkpath("data/quick_test")
    filepath = "data/quick_test/BTCUSDT_$(yesterday).csv"
    CSV.write(filepath, df)
    println("\n💾 已保存: $filepath")
    
else
    println("❌ 没有数据")
end

# 测试2: 缓存
println("\n📦 缓存信息:")
print_cache_info()

println("\n✅ 快速测试完成！")