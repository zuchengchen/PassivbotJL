# examples/test_vision_quick.jl

"""
Binance Vision 快速测试（无警告版本）
"""

using Dates
using DataFrames
using CSV

include("../src/data/binance_vision.jl")

function main()
    println("\n" * "="^70)
    println("Binance Vision 快速测试")
    println("="^70)
    
    symbol = "BTCUSDT"
    test_date = today() - Day(3)
    
    println("\n📊 测试配置:")
    println("  交易对: $symbol")
    println("  日期: $test_date")
    
    # 测试1: 单日下载
    println("\n🔄 下载单日数据...")
    df = download_daily_aggtrades(symbol, test_date, market=:futures)
    
    if nrow(df) > 0
        println("✅ 成功！$(nrow(df)) 笔交易")
        print_data_summary(df)
    else
        println("❌ 失败")
    end
    
    # 测试2: 数据验证
    println("\n🔍 验证数据...")
    validation = validate_aggtrades_data(df)
    println("  结果: $(validation.is_valid ? "✅ 通过" : "❌ 失败")")
    
    # 测试3: K线下载
    println("\n🔄 下载K线数据...")
    klines = download_klines(symbol, "1m", test_date, market=:futures)
    println("  1分钟K线: $(nrow(klines)) 根")
    
    # 测试4: 缓存信息
    println("\n📦 缓存信息:")
    print_cache_info()
    
    println("\n✅ 测试完成！")
end

main()