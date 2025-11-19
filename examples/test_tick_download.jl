# examples/test_tick_download.jl

"""
测试Tick数据下载功能

演示：
1. 下载历史aggTrades数据
2. 保存到本地
3. 加载数据
4. 转换为K线
5. 基本统计分析
"""

using Dates
using DataFrames
using Statistics
using Printf

# 如果还没有添加到主模块，先直接include
include("../src/data/tick_data.jl")

println("\n" * "="^70)
println("Tick数据下载测试")
println("="^70)

# ============================================================================
# 测试1: 下载少量数据（快速测试）
# ============================================================================

println("\n📊 测试1: 下载1小时的数据（快速测试）")
println("-"^70)

try
    # 设置时间范围（最近1小时）
    end_time = now(UTC)
    start_time = end_time - Hour(1)
    
    println("交易对: BTCUSDT")
    println("开始时间: $start_time")
    println("结束时间: $end_time")
    println()
    
    # 下载数据
    ticks = download_agg_trades(
        "BTCUSDT",
        start_time,
        end_time,
        testnet=false  # 使用主网
    )
    
    if nrow(ticks) > 0
        println("\n✅ 下载成功！")
        println("\n数据概览:")
        println("  总交易数: $(nrow(ticks))")
        println("  时间范围: $(ticks[1, :timestamp]) 到 $(ticks[end, :timestamp])")
        println("  价格范围: \$$(minimum(ticks.price)) - \$$(maximum(ticks.price))")
        println("  平均价格: \$$(round(mean(ticks.price), digits=2))")
        println("  总成交量: $(round(sum(ticks.quantity), digits=4)) BTC")
        
        # 显示前5条数据
        println("\n前5条数据:")
        println(first(ticks, 5))
        
        # 保存数据
        data_dir = "data/ticks"
        mkpath(data_dir)
        
        filename = "BTCUSDT_$(Dates.format(start_time, "yyyymmdd_HHMMSS"))_1h.csv"
        filepath = joinpath(data_dir, filename)
        
        save_tick_data(ticks, filepath)
        println("\n💾 数据已保存到: $filepath")
        
        # 测试加载
        println("\n测试加载数据...")
        loaded_ticks = load_tick_data(filepath)
        println("✅ 加载成功！数据行数: $(nrow(loaded_ticks))")
        
    else
        println("⚠️  没有下载到数据")
    end
    
catch e
    println("❌ 测试失败: $e")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试2: 下载一天的数据
# ============================================================================

println("\n\n📊 测试2: 下载24小时的数据")
println("-"^70)

try
    # 下载昨天的数据
    end_time = floor(now(UTC), Day)
    start_time = end_time - Day(1)
    
    println("交易对: BTCUSDT")
    println("开始时间: $start_time")
    println("结束时间: $end_time")
    println("预计下载时间: 1-2分钟")
    println()
    
    # 下载数据
    ticks = download_agg_trades(
        "BTCUSDT",
        start_time,
        end_time,
        testnet=false
    )
    
    if nrow(ticks) > 0
        println("\n✅ 下载成功！")
        
        # 详细统计
        println("\n📈 详细统计:")
        println("  总交易数: $(nrow(ticks))")
        println("  时间跨度: $(Dates.value(ticks[end, :timestamp] - ticks[1, :timestamp]) / 1000 / 3600) 小时")
        println("  价格统计:")
        println("    最高: \$$(round(maximum(ticks.price), digits=2))")
        println("    最低: \$$(round(minimum(ticks.price), digits=2))")
        println("    均价: \$$(round(mean(ticks.price), digits=2))")
        println("    中位: \$$(round(median(ticks.price), digits=2))")
        println("  成交量统计:")
        println("    总量: $(round(sum(ticks.quantity), digits=4)) BTC")
        println("    均量: $(round(mean(ticks.quantity), digits=6)) BTC")
        println("  买卖分布:")
        buy_count = count(ticks.is_buyer_maker .== false)
        sell_count = count(ticks.is_buyer_maker .== true)
        println("    主动买入: $buy_count ($(round(buy_count/nrow(ticks)*100, digits=1))%)")
        println("    主动卖出: $sell_count ($(round(sell_count/nrow(ticks)*100, digits=1))%)")
        
        # 保存
        data_dir = "data/ticks"
        mkpath(data_dir)
        
        filename = "BTCUSDT_$(Dates.format(start_time, "yyyymmdd"))_24h.csv"
        filepath = joinpath(data_dir, filename)
        
        save_tick_data(ticks, filepath)
        println("\n💾 数据已保存到: $filepath")
        
        # 文件大小
        filesize_mb = stat(filepath).size / 1024 / 1024
        println("   文件大小: $(round(filesize_mb, digits=2)) MB")
        
    else
        println("⚠️  没有下载到数据")
    end
    
catch e
    println("❌ 测试失败: $e")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试3: Tick数据转K线
# ============================================================================

println("\n\n📊 测试3: Tick数据转K线")
println("-"^70)

try
    # 使用刚才下载的数据
    data_dir = "data/ticks"
    files = readdir(data_dir, join=true)
    
    if isempty(files)
        println("⚠️  没有找到Tick数据文件，请先运行测试1或2")
    else
        # 使用最新的文件
        latest_file = last(sort(files))
        println("使用数据文件: $(basename(latest_file))")
        
        # 加载数据
        ticks = load_tick_data(latest_file)
        
        # 添加symbol列（如果没有）
        if !hasproperty(ticks, :symbol)
            ticks.symbol .= "BTCUSDT"
        end
        
        # 转换为不同时间周期的K线
        timeframes = ["1m", "5m", "15m", "1h"]
        
        for tf in timeframes
            println("\n转换为 $tf K线...")
            
            bars = ticks_to_bars(ticks, tf)
            
            println("  K线数量: $(nrow(bars))")
            
            if nrow(bars) > 0
                println("  时间范围: $(bars[1, :timestamp]) 到 $(bars[end, :timestamp])")
                println("  价格范围: \$$(round(minimum(bars.low), digits=2)) - \$$(round(maximum(bars.high), digits=2))")
                
                # 显示前3根K线
                println("\n  前3根K线:")
                println(first(bars, 3))
                
                # 保存K线数据
                bars_dir = "data/bars"
                mkpath(bars_dir)
                
                bars_file = replace(basename(latest_file), ".csv" => "_$(tf).csv")
                bars_path = joinpath(bars_dir, bars_file)
                
                CSV.write(bars_path, bars)
                println("\n  💾 K线数据已保存: $bars_path")
            end
        end
        
        println("\n✅ K线转换完成！")
    end
    
catch e
    println("❌ 测试失败: $e")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试4: 数据质量检查
# ============================================================================

println("\n\n📊 测试4: 数据质量检查")
println("-"^70)

try
    data_dir = "data/ticks"
    files = readdir(data_dir, join=true)
    
    if isempty(files)
        println("⚠️  没有找到数据文件")
    else
        latest_file = last(sort(files))
        println("检查文件: $(basename(latest_file))")
        
        ticks = load_tick_data(latest_file)
        
        println("\n数据质量检查:")
        
        # 1. 检查时间顺序
        is_sorted = issorted(ticks.timestamp)
        println("  ✓ 时间顺序: $(is_sorted ? "✅ 正确" : "❌ 错误")")
        
        # 2. 检查缺失值
        has_missing = any(ismissing, ticks.price) || any(ismissing, ticks.quantity)
        println("  ✓ 缺失值: $(has_missing ? "❌ 存在" : "✅ 无")")
        
        # 3. 检查异常价格
        price_std = std(ticks.price)
        price_mean = mean(ticks.price)
        outliers = count(abs.(ticks.price .- price_mean) .> 3 * price_std)
        println("  ✓ 价格异常值: $outliers ($(round(outliers/nrow(ticks)*100, digits=2))%)")
        
        # 4. 检查时间间隔
        time_diffs = diff(Dates.value.(ticks.timestamp))
        avg_interval = mean(time_diffs)
        max_gap = maximum(time_diffs)
        println("  ✓ 平均时间间隔: $(round(avg_interval, digits=2)) ms")
        println("  ✓ 最大时间间隔: $(round(max_gap/1000, digits=2)) 秒")
        
        # 5. 每秒交易数统计
        trades_per_second = nrow(ticks) / (Dates.value(ticks[end, :timestamp] - ticks[1, :timestamp]) / 1000)
        println("  ✓ 平均每秒交易: $(round(trades_per_second, digits=2)) 笔")
        
        # 6. 价格变化统计
        price_changes = diff(ticks.price)
        price_change_pct = price_changes ./ ticks.price[1:end-1] .* 100
        
        println("\n  价格变化统计:")
        println("    平均变化: $(round(mean(abs.(price_change_pct)), digits=4))%")
        println("    最大涨幅: $(round(maximum(price_change_pct), digits=4))%")
        println("    最大跌幅: $(round(minimum(price_change_pct), digits=4))%")
        
        println("\n✅ 数据质量检查完成！")
    end
    
catch e
    println("❌ 测试失败: $e")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试5: 多交易对下载
# ============================================================================

println("\n\n📊 测试5: 下载多个交易对")
println("-"^70)

try
    symbols = ["BTCUSDT", "ETHUSDT", "BNBUSDT"]
    
    # 下载最近30分钟的数据
    end_time = now(UTC)
    start_time = end_time - Minute(30)
    
    println("时间范围: $start_time 到 $end_time")
    println("交易对: $(join(symbols, ", "))")
    println()
    
    for symbol in symbols
        println("\n下载 $symbol...")
        
        try
            ticks = download_agg_trades(
                symbol,
                start_time,
                end_time,
                testnet=false
            )
            
            if nrow(ticks) > 0
                println("  ✅ 成功: $(nrow(ticks)) 笔交易")
                println("  价格: \$$(round(ticks[end, :price], digits=2))")
                
                # 保存
                data_dir = "data/ticks/multi"
                mkpath(data_dir)
                
                filename = "$(symbol)_$(Dates.format(start_time, "yyyymmdd_HHMMSS"))_30m.csv"
                filepath = joinpath(data_dir, filename)
                
                # 添加symbol列
                ticks.symbol .= symbol
                
                save_tick_data(ticks, filepath)
                
            else
                println("  ⚠️  无数据")
            end
            
        catch e
            println("  ❌ 失败: $e")
        end
        
        # 避免触发速率限制
        sleep(1)
    end
    
    println("\n✅ 多交易对下载完成！")
    
catch e
    println("❌ 测试失败: $e")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 总结
# ============================================================================

println("\n" * "="^70)
println("测试总结")
println("="^70)

try
    # 统计下载的数据
    data_dir = "data/ticks"
    
    if isdir(data_dir)
        files = readdir(data_dir, join=true)
        
        if !isempty(files)
            total_size = sum(stat(f).size for f in files if isfile(f))
            total_size_mb = total_size / 1024 / 1024
            
            println("\n📁 数据文件统计:")
            println("  文件数量: $(length(files))")
            println("  总大小: $(round(total_size_mb, digits=2)) MB")
            println("  保存位置: $data_dir")
            
            println("\n文件列表:")
            for f in files
                if isfile(f)
                    size_mb = stat(f).size / 1024 / 1024
                    println("  - $(basename(f)) ($(round(size_mb, digits=2)) MB)")
                end
            end
        else
            println("\n⚠️  没有下载任何数据")
        end
    else
        println("\n⚠️  数据目录不存在")
    end
    
    # 检查K线数据
    bars_dir = "data/bars"
    if isdir(bars_dir)
        bars_files = readdir(bars_dir, join=true)
        if !isempty(bars_files)
            println("\n📊 K线数据:")
            println("  文件数量: $(length(bars_files))")
            for f in bars_files
                println("  - $(basename(f))")
            end
        end
    end
    
catch e
    println("统计失败: $e")
end

println("\n" * "="^70)
println("✅ 所有测试完成！")
println("="^70)
println()