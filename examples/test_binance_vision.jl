# examples/test_binance_vision.jl

"""
Binance Vision 下载器测试
"""

using Dates
using DataFrames
using Statistics
using CSV

include("../src/data/binance_vision.jl")

# ============================================================================
# 全局变量声明（修复作用域警告）
# ============================================================================

global test1_success = false
global test2_success = false
global test3_success = false
global test4_success = false
global test5_success = false
global test6_success = false
global test7_success = false
global test8_success = false

global total_files = 0
global total_size = 0.0

# ============================================================================
# 辅助函数
# ============================================================================

"""
获取最新可用数据日期（通常延迟2-3天）
"""
function get_safe_test_date()::Date
    return today() - Day(3)
end

# ============================================================================
# 主测试
# ============================================================================

println("\n" * "="^70)
println("Binance Vision 下载器测试")
println("="^70)

# 配置
TEST_SYMBOL = "BTCUSDT"
TEST_MARKET = :futures

println("\n配置:")
println("  交易对: $TEST_SYMBOL")
println("  市场: $TEST_MARKET")
println("  缓存目录: $(DOWNLOAD_CONFIG.cache_dir)")

# ============================================================================
# 测试1: 下载单日数据
# ============================================================================

println("\n" * "="^70)
println("测试1: 下载单日aggTrades数据")
println("="^70)

global test1_success = true

try
    test_date = get_safe_test_date()
    
    println("\n📅 测试日期: $test_date")
    println("🔄 开始下载...")
    
    df = download_daily_aggtrades(
        TEST_SYMBOL,
        test_date,
        market=TEST_MARKET,
        use_cache=true
    )
    
    if nrow(df) > 0
        println("\n✅ 下载成功！")
        
        # 打印摘要
        print_data_summary(df)
        
        # 验证数据
        validation = validate_aggtrades_data(df)
        
        println("\n🔍 数据验证:")
        println("  状态: $(validation.is_valid ? "✅ 通过" : "❌ 失败")")
        
        if !isempty(validation.warnings)
            println("\n  警告:")
            for w in validation.warnings
                println("    ⚠️  $w")
            end
        end
        
        if !isempty(validation.errors)
            println("\n  错误:")
            for e in validation.errors
                println("    ❌ $e")
            end
        end
        
        # 保存样本
        mkpath("data/samples")
        sample_file = "data/samples/$(TEST_SYMBOL)_$(test_date)_sample.csv"
        CSV.write(sample_file, first(df, min(1000, nrow(df))))
        println("\n💾 样本数据已保存: $sample_file")
        
        test1_success = validation.is_valid
        
    else
        println("\n⚠️  没有数据")
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试2: 下载日期范围
# ============================================================================

println("\n\n" * "="^70)
println("测试2: 下载日期范围数据（3天）")
println("="^70)

test2_success = false

try
    end_date = get_safe_test_date()
    start_date = end_date - Day(2)
    
    println("\n📅 日期范围: $start_date 到 $end_date")
    println("🔄 开始下载...")
    
    df = download_date_range_aggtrades(
        TEST_SYMBOL,
        start_date,
        end_date,
        market=TEST_MARKET,
        use_cache=true,
        merge=true
    )
    
    if nrow(df) > 0
        println("\n✅ 下载成功！")
        
        print_data_summary(df)
        
        # 按日统计
        println("\n📊 每日数据统计:")
        df.date = Date.(df.timestamp)
        daily_stats = combine(groupby(df, :date), nrow => :count)
        sort!(daily_stats, :date)
        
        for row in eachrow(daily_stats)
            println("  $(row.date): $(row.count) 笔交易")
        end
        
        # 保存
        mkpath("data/ranges")
        range_file = "data/ranges/$(TEST_SYMBOL)_$(start_date)_to_$(end_date).csv"
        CSV.write(range_file, df)
        
        file_size_mb = stat(range_file).size / 1024 / 1024
        println("\n💾 数据已保存: $range_file")
        println("   文件大小: $(round(file_size_mb, digits=2)) MB")
        
        test2_success = true
        
    else
        println("\n⚠️  没有数据")
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试3: 下载月度数据
# ============================================================================

println("\n\n" * "="^70)
println("测试3: 下载月度数据")
println("="^70)

test3_success = false

try
    # 下载上个月
    last_month = today() - Month(1)
    test_year = Dates.year(last_month)
    test_month = Dates.month(last_month)
    
    println("\n📅 年月: $test_year-$(lpad(test_month, 2, '0'))")
    println("🔄 开始下载...")
    println("⏱️  预计需要1-2分钟...")
    
    df = download_monthly_aggtrades(
        TEST_SYMBOL,
        test_year,
        test_month,
        market=TEST_MARKET,
        use_cache=true
    )
    
    if nrow(df) > 0
        println("\n✅ 下载成功！")
        
        print_data_summary(df)
        
        # 统计分析
        println("\n📈 统计分析:")
        
        # 价格波动
        price_changes = diff(df.price)
        price_change_pct = price_changes ./ df.price[1:end-1] .* 100
        
        println("\n  价格变化:")
        println("    平均变化: $(round(mean(abs.(price_change_pct)), digits=4))%")
        println("    最大涨幅: $(round(maximum(price_change_pct), digits=4))%")
        println("    最大跌幅: $(round(minimum(price_change_pct), digits=4))%")
        println("    标准差: $(round(std(price_change_pct), digits=4))%")
        
        # 交易频率
        time_diffs = diff(Dates.value.(df.timestamp))
        avg_interval_ms = mean(time_diffs)
        
        println("\n  交易频率:")
        println("    平均间隔: $(round(avg_interval_ms, digits=2)) ms")
        println("    每秒交易: $(round(1000/avg_interval_ms, digits=2)) 笔")
        
        # 保存
        mkpath("data/monthly")
        monthly_file = "data/monthly/$(TEST_SYMBOL)_$(test_year)_$(lpad(test_month, 2, '0')).csv"
        CSV.write(monthly_file, df)
        
        file_size_mb = stat(monthly_file).size / 1024 / 1024
        println("\n💾 月度数据已保存: $monthly_file")
        println("   文件大小: $(round(file_size_mb, digits=2)) MB")
        
        test3_success = true
        
    else
        println("\n⚠️  没有数据")
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试4: K线数据
# ============================================================================

println("\n\n" * "="^70)
println("测试4: K线数据下载")
println("="^70)

test4_success = false

try
    test_date = get_safe_test_date()
    intervals = ["1m", "5m", "15m", "1h"]
    
    println("\n📅 测试日期: $test_date")
    println("📊 时间周期: $(join(intervals, ", "))")
    println("🔄 开始下载...")
    
    kline_results = Dict{String, DataFrame}()
    
    for interval in intervals
        try
            df = download_klines(
                TEST_SYMBOL,
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
            println("  ❌ $interval: 下载失败")
        end
        
        sleep(0.1)
    end
    
    if !isempty(kline_results)
        println("\n✅ K线下载完成！")
        
        # 统计
        println("\n📊 K线统计:")
        println(rpad("周期", 10) * rpad("数量", 10) * rpad("价格范围", 30) * "成交量")
        println("-"^70)
        
        for interval in intervals
            if haskey(kline_results, interval)
                df = kline_results[interval]
                
                price_range = "\$$(round(minimum(df.low), digits=2)) - \$$(round(maximum(df.high), digits=2))"
                total_vol = round(sum(df.volume), digits=2)
                
                println(
                    rpad(interval, 10) *
                    rpad(string(nrow(df)), 10) *
                    rpad(price_range, 30) *
                    string(total_vol)
                )
            end
        end
        
        # 保存
        kline_dir = "data/klines/$(TEST_SYMBOL)/$(test_date)"
        mkpath(kline_dir)
        
        for (interval, df) in kline_results
            filepath = joinpath(kline_dir, "$(interval).csv")
            CSV.write(filepath, df)
        end
        
        println("\n💾 K线数据已保存到: $kline_dir")
        
        test4_success = !isempty(kline_results)
        
    else
        println("\n⚠️  没有下载到任何K线数据")
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试5: 缓存功能
# ============================================================================

println("\n\n" * "="^70)
println("测试5: 缓存功能测试")
println("="^70)

test5_success = false

try
    println("\n📦 当前缓存信息:")
    print_cache_info()
    
    println("\n🔄 测试缓存加速...")
    test_date = get_safe_test_date()
    
    # 第一次下载（可能使用缓存）
    start_time = time()
    df1 = download_daily_aggtrades(TEST_SYMBOL, test_date, use_cache=true)
    time1 = time() - start_time
    
    # 第二次下载（必定使用缓存）
    start_time = time()
    df2 = download_daily_aggtrades(TEST_SYMBOL, test_date, use_cache=true)
    time2 = time() - start_time
    
    println("\n  第一次下载: $(round(time1, digits=3)) 秒")
    println("  第二次下载: $(round(time2, digits=3)) 秒")
    
    if time2 < time1
        speedup = round(time1/time2, digits=2)
        println("  加速比: $(speedup)x")
        println("  ✅ 缓存工作正常")
        test5_success = true
    else
        println("  ⚠️  缓存未生效")
    end
    
    # 测试缓存清理
    println("\n🗑️  测试缓存清理（清理7天前的文件）...")
    
    initial_files = length(list_cached_files())
    initial_size = get_cache_size()
    
    clear_cache(older_than_days=7)
    
    final_files = length(list_cached_files())
    final_size = get_cache_size()
    
    println("  清理前: $initial_files 个文件 ($(round(initial_size, digits=2)) MB)")
    println("  清理后: $final_files 个文件 ($(round(final_size, digits=2)) MB)")
    
    freed_mb = initial_size - final_size
    if freed_mb > 0
        println("  释放空间: $(round(freed_mb, digits=2)) MB")
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试6: 多交易对下载
# ============================================================================

println("\n\n" * "="^70)
println("测试6: 多交易对下载")
println("="^70)

test6_success = false

try
    symbols = ["BTCUSDT", "ETHUSDT", "BNBUSDT"]
    test_date = get_safe_test_date()
    
    println("\n📅 测试日期: $test_date")
    println("📊 交易对: $(join(symbols, ", "))")
    println("🔄 开始下载...")
    
    results = download_multiple_symbols(
        symbols,
        test_date,
        market=TEST_MARKET,
        use_cache=true
    )
    
    if !isempty(results)
        println("\n✅ 下载完成！成功: $(length(results)) / $(length(symbols))")
        
        println("\n📊 各交易对统计:")
        println(rpad("交易对", 12) * rpad("数据量", 12) * rpad("均价", 15) * "总成交量")
        println("-"^60)
        
        for symbol in symbols
            if haskey(results, symbol)
                df = results[symbol]
                avg_price = round(mean(df.price), digits=2)
                total_vol = round(sum(df.quantity), digits=4)
                
                println(
                    rpad(symbol, 12) *
                    rpad(string(nrow(df)), 12) *
                    rpad("\$$avg_price", 15) *
                    string(total_vol)
                )
            else
                println(rpad(symbol, 12) * "下载失败")
            end
        end
        
        # 保存
        multi_dir = "data/multi/$(test_date)"
        mkpath(multi_dir)
        
        for (symbol, df) in results
            filepath = joinpath(multi_dir, "$(symbol).csv")
            CSV.write(filepath, df)
        end
        
        println("\n💾 数据已保存到: $multi_dir")
        
        test6_success = length(results) > 0
        
    else
        println("\n⚠️  没有下载到任何数据")
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试7: 数据转换（Tick转K线）
# ============================================================================

println("\n\n" * "="^70)
println("测试7: 数据转换（Tick转K线）")
println("="^70)

test7_success = false

try
    test_date = get_safe_test_date()
    
    println("\n🔄 下载Tick数据...")
    ticks = download_daily_aggtrades(TEST_SYMBOL, test_date, use_cache=true)
    
    if nrow(ticks) > 0
        println("✅ 获得 $(nrow(ticks)) 笔交易")
        
        # 添加必要的列
        if !hasproperty(ticks, :symbol)
            ticks.symbol .= TEST_SYMBOL
        end
        
        println("\n🔄 转换为K线...")
        
        # 包含tick_data.jl以使用转换函数
        include("../src/data/tick_data.jl")
        
        timeframes = ["1m", "5m", "15m"]
        
        converted_bars = Dict{String, DataFrame}()
        
        for tf in timeframes
            try
                bars = ticks_to_bars(ticks, tf)
                
                if nrow(bars) > 0
                    converted_bars[tf] = bars
                    println("  ✅ $tf: $(nrow(bars)) 根K线")
                    
                    # 显示前3根
                    if nrow(bars) >= 3
                        println("    前3根K线:")
                        for row in eachrow(first(bars, 3))
                            println("      $(row.timestamp): O=$(round(row.open, digits=2)) H=$(round(row.high, digits=2)) L=$(round(row.low, digits=2)) C=$(round(row.close, digits=2))")
                        end
                    end
                else
                    println("  ⚠️  $tf: 无K线")
                end
            catch e
                println("  ❌ $tf: 转换失败 - $e")
            end
        end
        
        if !isempty(converted_bars)
            # 保存转换后的K线
            converted_dir = "data/converted/$(TEST_SYMBOL)/$(test_date)"
            mkpath(converted_dir)
            
            for (tf, bars) in converted_bars
                filepath = joinpath(converted_dir, "$(tf)_converted.csv")
                CSV.write(filepath, bars)
            end
            
            println("\n💾 转换后的K线已保存到: $converted_dir")
            test7_success = true
        end
        
    else
        println("⚠️  无Tick数据")
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试8: 数据质量检查
# ============================================================================

println("\n\n" * "="^70)
println("测试8: 数据质量检查")
println("="^70)

test8_success = false

try
    test_date = get_safe_test_date()
    
    println("\n🔄 下载数据...")
    df = download_daily_aggtrades(TEST_SYMBOL, test_date, use_cache=true)
    
    if nrow(df) > 0
        println("✅ 数据下载成功")
        
        println("\n🔍 质量检查:")
        
        # 1. 时间连续性
        time_diffs = diff(Dates.value.(df.timestamp))
        max_gap_sec = maximum(time_diffs) / 1000
        avg_gap_ms = mean(time_diffs)
        
        println("\n  时间连续性:")
        println("    平均间隔: $(round(avg_gap_ms, digits=2)) ms")
        println("    最大间隔: $(round(max_gap_sec, digits=2)) 秒")
        
        if max_gap_sec > 60
            println("    ⚠️  存在超过1分钟的间隔")
        else
            println("    ✅ 时间连续性良好")
        end
        
        # 2. 价格异常检测
        price_changes = diff(df.price)
        price_change_pct = abs.(price_changes ./ df.price[1:end-1] .* 100)
        
        max_change = maximum(price_change_pct)
        outliers = count(price_change_pct .> 1.0)  # 超过1%的变化
        
        println("\n  价格异常:")
        println("    最大单笔变化: $(round(max_change, digits=4))%")
        println("    异常变化数量: $outliers ($(round(outliers/length(price_change_pct)*100, digits=2))%)")
        
        if max_change > 5.0
            println("    ⚠️  存在异常价格跳动")
        else
            println("    ✅ 价格变化正常")
        end
        
        # 3. 成交量分布
        vol_mean = mean(df.quantity)
        vol_std = std(df.quantity)
        vol_outliers = count(df.quantity .> vol_mean + 3 * vol_std)
        
        println("\n  成交量分布:")
        println("    平均成交量: $(round(vol_mean, digits=6))")
        println("    标准差: $(round(vol_std, digits=6))")
        println("    异常值数量: $vol_outliers ($(round(vol_outliers/nrow(df)*100, digits=2))%)")
        
        # 4. 买卖平衡
        buy_count = count(.!df.is_buyer_maker)
        sell_count = count(df.is_buyer_maker)
        buy_ratio = buy_count / nrow(df) * 100
        
        println("\n  买卖平衡:")
        println("    主动买入: $buy_count ($(round(buy_ratio, digits=1))%)")
        println("    主动卖出: $sell_count ($(round(100-buy_ratio, digits=1))%)")
        
        if abs(buy_ratio - 50) > 10
            println("    ⚠️  买卖不平衡")
        else
            println("    ✅ 买卖比例正常")
        end
        
        test8_success = true
        
    else
        println("⚠️  无数据")
    end
    
catch e
    println("\n❌ 测试失败:")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 最终总结
# ============================================================================

println("\n\n" * "="^70)
println("测试总结")
println("="^70)

test_results = [
    ("单日下载", test1_success),
    ("日期范围下载", test2_success),
    ("月度下载", test3_success),
    ("K线下载", test4_success),
    ("缓存功能", test5_success),
    ("多交易对下载", test6_success),
    ("数据转换", test7_success),
    ("质量检查", test8_success)
]

passed = count(x -> x[2], test_results)
total = length(test_results)

println("\n测试结果: $passed / $total 通过\n")

for (name, success) in test_results
    status = success ? "✅" : "❌"
    println("  $status $name")
end

if passed == total
    println("\n🎉 所有测试通过！")
else
    println("\n⚠️  部分测试失败")
end

# 文件统计
println("\n" * "="^70)
println("生成的文件")
println("="^70)

data_dirs = ["data/samples", "data/ranges", "data/monthly", "data/klines", "data/multi", "data/converted"]

total_files = 0
total_size = 0.0

for dir in data_dirs
    if isdir(dir)
        files = readdir(dir, join=true)
        if !isempty(files)
            println("\n📂 $dir:")
            for f in files
                if isfile(f)
                    size_mb = stat(f).size / 1024 / 1024
                    total_size += size_mb
                    total_files += 1
                    println("  - $(basename(f)) ($(round(size_mb, digits=2)) MB)")
                elseif isdir(f)
                    sub_files = filter(isfile, readdir(f, join=true))
                    file_count = length(sub_files)
                    total_files += file_count
                    
                    sub_size = sum(stat(sf).size for sf in sub_files) / 1024 / 1024
                    total_size += sub_size
                    
                    println("  - $(basename(f))/ ($file_count 个文件, $(round(sub_size, digits=2)) MB)")
                end
            end
        end
    end
end

println("\n总计:")
println("  文件数: $total_files")
println("  总大小: $(round(total_size, digits=2)) MB")

# 缓存状态
println("\n" * "="^70)
print_cache_info()

println("\n" * "="^70)
println("✅ 测试完成！")
println("="^70)
println()