# examples/test_binance_vision_fixed.jl

"""
Binance Vision 测试套件（修复版）

修复：
- 使用正确的可用日期
- 修复变量作用域问题
- 添加更好的错误处理
"""

using Dates
using DataFrames
using Statistics
using Printf

include("../src/data/binance_vision.jl")

# ============================================================================
# 辅助函数
# ============================================================================

"""
获取最新可用数据日期（Binance Vision通常延迟2-3天）
"""
function get_latest_available_date()::Date
    return today() - Day(3)
end

"""
获取测试用的日期范围
"""
function get_test_date_range(days::Int=3)::Tuple{Date, Date}
    end_date = get_latest_available_date()
    start_date = end_date - Day(days - 1)
    return (start_date, end_date)
end

# ============================================================================
# 测试配置
# ============================================================================

const TEST_SYMBOLS = ["BTCUSDT", "ETHUSDT", "BNBUSDT"]
const TEST_MARKET = :futures

# 测试结果（使用全局变量）
global test_results = Dict{String, Bool}()

println("\n" * "="^70)
println("Binance Vision 测试套件（修复版）")
println("="^70)

latest_date = get_latest_available_date()
println("\n配置:")
println("  测试交易对: $(join(TEST_SYMBOLS, ", "))")
println("  市场类型: $TEST_MARKET")
println("  缓存目录: $(DOWNLOAD_CONFIG.cache_dir)")
println("  最新可用日期: $latest_date")
println("  当前日期: $(today())")

# ============================================================================
# 测试1: 单日下载
# ============================================================================

println("\n" * "="^70)
println("测试1: 单日aggTrades下载")
println("="^70)

try
    global test_results
    
    test_date = get_latest_available_date()
    
    println("\n📅 测试日期: $test_date")
    println("🔄 开始下载...")
    
    df = download_daily_aggtrades(
        TEST_SYMBOLS[1],
        test_date,
        market=TEST_MARKET,
        use_cache=true
    )
    
    if nrow(df) > 0
        println("\n✅ 下载成功！")
        
        print_data_summary(df)
        
        validation = validate_aggtrades_data(df)
        
        println("\n🔍 数据验证:")
        println("  有效: $(validation.is_valid ? "✅" : "❌")")
        
        if !isempty(validation.warnings)
            println("  警告:")
            for warning in validation.warnings
                println("    ⚠️  $warning")
            end
        end
        
        if !isempty(validation.errors)
            println("  错误:")
            for error in validation.errors
                println("    ❌ $error")
            end
        end
        
        # 保存样本
        sample_file = "data/samples/$(TEST_SYMBOLS[1])_$(test_date)_sample.csv"
        mkpath(dirname(sample_file))
        CSV.write(sample_file, first(df, 1000))
        println("\n💾 样本数据已保存: $sample_file")
        
        test_results["单日下载"] = validation.is_valid
        
    else
        println("⚠️  没有数据")
        test_results["单日下载"] = false
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
    test_results["单日下载"] = false
end

# ============================================================================
# 测试2: 日期范围下载
# ============================================================================

println("\n\n" * "="^70)
println("测试2: 日期范围下载（3天）")
println("="^70)

try
    global test_results
    
    start_date, end_date = get_test_date_range(3)
    
    println("\n📅 日期范围: $start_date 到 $end_date")
    println("🔄 开始下载...")
    
    df = download_date_range_aggtrades(
        TEST_SYMBOLS[1],
        start_date,
        end_date,
        market=TEST_MARKET,
        use_cache=true,
        merge=true
    )
    
    if nrow(df) > 0
        println("\n✅ 下载成功！")
        
        print_data_summary(df)
        
        # 检查数据连续性
        println("\n📊 数据连续性检查:")
        
        df.date = Date.(df.timestamp)
        daily_counts = combine(groupby(df, :date), nrow => :count)
        sort!(daily_counts, :date)
        
        println("\n每日数据量:")
        for row in eachrow(daily_counts)
            println("  $(row.date): $(row.count) 笔交易")
        end
        
        # 保存
        range_file = "data/samples/$(TEST_SYMBOLS[1])_range_$(start_date)_to_$(end_date).csv"
        mkpath(dirname(range_file))
        CSV.write(range_file, df)
        println("\n💾 数据已保存: $range_file")
        
        file_size_mb = stat(range_file).size / 1024 / 1024
        println("   文件大小: $(round(file_size_mb, digits=2)) MB")
        
        test_results["日期范围下载"] = true
        
    else
        println("⚠️  没有数据")
        test_results["日期范围下载"] = false
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
    test_results["日期范围下载"] = false
end

# ============================================================================
# 测试3: 月度下载
# ============================================================================

println("\n\n" * "="^70)
println("测试3: 月度数据下载")
println("="^70)

try
    global test_results
    
    # 下载上个月的数据
    last_month = today() - Month(1)
    test_year = Dates.year(last_month)
    test_month = Dates.month(last_month)
    
    println("\n📅 年月: $test_year-$(lpad(test_month, 2, '0'))")
    println("🔄 开始下载...")
    println("⏱️  预计需要1-2分钟...")
    
    df = download_monthly_aggtrades(
        TEST_SYMBOLS[1],
        test_year,
        test_month,
        market=TEST_MARKET,
        use_cache=true
    )
    
    if nrow(df) > 0
        println("\n✅ 下载成功！")
        
        print_data_summary(df)
        
        # 数据质量统计
        println("\n📈 质量统计:")
        
        price_changes = diff(df.price)
        price_change_pct = price_changes ./ df.price[1:end-1] .* 100
        
        println("  价格变化:")
        println("    平均: $(round(mean(abs.(price_change_pct)), digits=4))%")
        println("    最大涨幅: $(round(maximum(price_change_pct), digits=4))%")
        println("    最大跌幅: $(round(minimum(price_change_pct), digits=4))%")
        println("    标准差: $(round(std(price_change_pct), digits=4))%")
        
        time_diffs = diff(Dates.value.(df.timestamp))
        println("\n  交易频率:")
        println("    平均间隔: $(round(mean(time_diffs), digits=2)) ms")
        println("    最大间隔: $(round(maximum(time_diffs)/1000, digits=2)) 秒")
        println("    每秒交易: $(round(1000/mean(time_diffs), digits=2)) 笔")
        
        # 保存
        monthly_file = "data/monthly/$(TEST_SYMBOLS[1])_$(test_year)_$(lpad(test_month, 2, '0')).csv"
        mkpath(dirname(monthly_file))
        CSV.write(monthly_file, df)
        
        file_size_mb = stat(monthly_file).size / 1024 / 1024
        println("\n💾 月度数据已保存: $monthly_file")
        println("   文件大小: $(round(file_size_mb, digits=2)) MB")
        
        test_results["月度下载"] = true
        
    else
        println("⚠️  没有数据")
        test_results["月度下载"] = false
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
    test_results["月度下载"] = false
end

# ============================================================================
# 测试4: 缓存管理
# ============================================================================

println("\n\n" * "="^70)
println("测试4: 缓存管理")
println("="^70)

try
    global test_results
    
    println("\n📦 缓存信息:")
    print_cache_info()
    
    println("\n🔄 测试缓存命中...")
    test_date = get_latest_available_date()
    
    # 第一次下载
    start_time = time()
    df1 = download_daily_aggtrades(TEST_SYMBOLS[1], test_date, use_cache=true)
    time1 = time() - start_time
    
    # 第二次下载（从缓存）
    start_time = time()
    df2 = download_daily_aggtrades(TEST_SYMBOLS[1], test_date, use_cache=true)
    time2 = time() - start_time
    
    println("  第一次下载: $(round(time1, digits=2)) 秒")
    println("  第二次下载: $(round(time2, digits=2)) 秒")
    
    if time2 < time1
        speedup = round(time1/time2, digits=2)
        println("  加速比: $(speedup)x")
        println("  ✅ 缓存工作正常")
        test_results["缓存管理"] = true
    else
        println("  ⚠️  缓存可能未生效")
        test_results["缓存管理"] = false
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
    test_results["缓存管理"] = false
end

# ============================================================================
# 测试5: K线下载
# ============================================================================

println("\n\n" * "="^70)
println("测试5: K线数据下载")
println("="^70)

try
    global test_results
    
    test_date = get_latest_available_date()
    intervals = ["1m", "5m", "1h"]
    
    println("\n📅 测试日期: $test_date")
    println("📊 时间周期: $(join(intervals, ", "))")
    println("🔄 开始下载...")
    
    kline_results = Dict{String, DataFrame}()
    
    for interval in intervals
        try
            df = download_klines(
                TEST_SYMBOLS[1],
                interval,
                test_date,
                market=TEST_MARKET,
                use_cache=true
            )
            
            if nrow(df) > 0
                kline_results[interval] = df
                println("  ✅ $interval: $(nrow(df)) 根K线")
            else
                println("  ⚠️  $interval: 无数据")
            end
            
        catch e
            println("  ❌ $interval: 失败")
        end
        
        sleep(0.1)
    end
    
    if !isempty(kline_results)
        println("\n✅ K线下载完成！")
        
        println("\nK线数据统计:")
        println(rpad("周期", 10) * rpad("K线数", 10) * rpad("价格范围", 25) * "总成交量")
        println("-"^70)
        
        for interval in intervals
            if haskey(kline_results, interval)
                df = kline_results[interval]
                
                price_range = "$(round(minimum(df.low), digits=2)) - $(round(maximum(df.high), digits=2))"
                total_vol = round(sum(df.volume), digits=2)
                
                println(
                    rpad(interval, 10) *
                    rpad(string(nrow(df)), 10) *
                    rpad(price_range, 25) *
                    string(total_vol)
                )
            end
        end
        
        # 保存
        kline_dir = "data/klines/$(TEST_SYMBOLS[1])/$(test_date)"
        mkpath(kline_dir)
        
        for (interval, df) in kline_results
            filepath = joinpath(kline_dir, "$(interval).csv")
            CSV.write(filepath, df)
        end
        
        println("\n💾 K线数据已保存到: $kline_dir")
        
        test_results["K线下载"] = true
        
    else
        println("⚠️  没有下载到任何K线数据")
        test_results["K线下载"] = false
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
    test_results["K线下载"] = false
end

# ============================================================================
# 测试总结
# ============================================================================

println("\n\n" * "="^70)
println("测试总结")
println("="^70)

passed_count = count(values(test_results)) do passed
    passed == true
end
total_count = length(test_results)

println("\n测试结果: $passed_count / $total_count 通过\n")

for (name, passed) in sort(collect(test_results))
    status = passed ? "✅" : "❌"
    println("  $status $name")
end

if passed_count == total_count
    println("\n🎉 所有测试通过！")
else
    println("\n⚠️  部分测试失败，请检查错误信息")
end

# 最终缓存信息
println("\n" * "="^70)
print_cache_info()

println("\n" * "="^70)
println("测试完成！")
println("="^70)
println()