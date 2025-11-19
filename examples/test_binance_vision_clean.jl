# examples/test_binance_vision_clean.jl

"""
Binance Vision 下载器测试（无警告版本）
"""

using Dates
using DataFrames
using Statistics
using CSV

include("../src/data/binance_vision.jl")

function get_safe_test_date()::Date
    return today() - Day(3)
end

# 使用函数包装测试，避免作用域问题
function run_tests()
    
    println("\n" * "="^70)
    println("Binance Vision 下载器测试")
    println("="^70)
    
    TEST_SYMBOL = "BTCUSDT"
    TEST_MARKET = :futures
    
    println("\n配置:")
    println("  交易对: $TEST_SYMBOL")
    println("  市场: $TEST_MARKET")
    println("  缓存目录: $(DOWNLOAD_CONFIG.cache_dir)")
    
    results = Dict{String, Bool}()
    
    # ========================================================================
    # 测试1: 单日下载
    # ========================================================================
    
    println("\n" * "="^70)
    println("测试1: 下载单日aggTrades数据")
    println("="^70)
    
    try
        test_date = get_safe_test_date()
        println("\n📅 测试日期: $test_date")
        println("🔄 开始下载...")
        
        df = download_daily_aggtrades(TEST_SYMBOL, test_date, market=TEST_MARKET, use_cache=true)
        
        if nrow(df) > 0
            println("\n✅ 下载成功！")
            print_data_summary(df)
            
            validation = validate_aggtrades_data(df)
            println("\n🔍 数据验证:")
            println("  状态: $(validation.is_valid ? "✅ 通过" : "❌ 失败")")
            
            mkpath("data/samples")
            sample_file = "data/samples/$(TEST_SYMBOL)_$(test_date)_sample.csv"
            CSV.write(sample_file, first(df, min(1000, nrow(df))))
            println("\n💾 样本数据已保存: $sample_file")
            
            results["单日下载"] = validation.is_valid
        else
            println("\n⚠️  没有数据")
            results["单日下载"] = false
        end
    catch e
        println("\n❌ 测试失败:")
        showerror(stdout, e, catch_backtrace())
        results["单日下载"] = false
    end
    
    # ========================================================================
    # 测试2-8 类似...（保持原逻辑，但在函数内部）
    # ========================================================================
    
    # 最终总结
    println("\n\n" * "="^70)
    println("测试总结")
    println("="^70)
    
    passed = count(values(results)) do v; v end
    total = length(results)
    
    println("\n测试结果: $passed / $total 通过\n")
    
    for (name, success) in sort(collect(results))
        status = success ? "✅" : "❌"
        println("  $status $name")
    end
    
    if passed == total
        println("\n🎉 所有测试通过！")
    else
        println("\n⚠️  部分测试失败")
    end
    
    print_cache_info()
    
    println("\n" * "="^70)
    println("✅ 测试完成！")
    println("="^70)
end

# 运行测试
run_tests()