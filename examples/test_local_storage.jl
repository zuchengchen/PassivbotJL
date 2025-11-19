# examples/test_local_storage.jl

"""
本地存储完整测试（Parquet 格式）

测试功能：
1. 首次下载并保存到本地（Parquet 格式）
2. 第二次从本地加载
3. 增量下载（部分本地，部分下载）
4. 数据验证
5. 缓存管理
6. 存储统计
7. 格式转换
"""

using Dates
using DataFrames
using TimeZones

include("../src/data/data_manager.jl")

println("\n" * "="^70)
println("本地存储完整测试（Parquet 格式）")
println("="^70)

println("\n默认存储格式: $(DEFAULT_FORMAT == PARQUET_FORMAT ? "Parquet" : "CSV")")

current_utc = DateTime(now(tz"UTC"))
println("\n当前 UTC 时间: $current_utc")

# ============================================================================
# 测试1: 首次下载（保存到本地）
# ============================================================================

println("\n\n" * "="^70)
println("测试1: 首次下载（自动保存到本地）")
println("="^70)

start_date1 = Date(2024, 11, 10)
end_date1 = Date(2024, 11, 12)

start_time1 = DateTime(start_date1)
end_time1 = DateTime(end_date1, Time(23, 59, 59))

println("\n时间范围: $start_time1 到 $end_time1")
println("期望: 从 Vision 下载并保存到本地")

# 清空本地数据以测试首次下载
println("\n清理旧的测试数据...")
for date in start_date1:Day(1):end_date1
    path = get_local_data_path("BTCUSDT", date, :futures)
    if isfile(path)
        rm(path)
        println("  删除: $date")
    end
end

println("\n开始下载...")
time_start = time()
df1 = fetch_data(
    "BTCUSDT",
    start_time1,
    end_time1,
    market=:futures,
    use_cache=true,
    verbose=true
)
time_first = time() - time_start

println("\n结果:")
println("  数据量: $(nrow(df1)) 笔交易")
println("  耗时: $(round(time_first, digits=2)) 秒")

# 验证本地文件已创建
println("\n验证本地文件:")
for date in start_date1:Day(1):end_date1
    has_data = has_local_data("BTCUSDT", date, :futures)
    status = has_data ? "✅" : "❌"
    println("  $status $date")
end

# ============================================================================
# 测试2: 第二次加载（从本地）
# ============================================================================

println("\n\n" * "="^70)
println("测试2: 第二次加载（从本地，应该很快）")
println("="^70)

println("\n重新加载相同数据...")
time_start = time()
df2 = fetch_data(
    "BTCUSDT",
    start_time1,
    end_time1,
    market=:futures,
    use_cache=true,
    verbose=true
)
time_second = time() - time_start

println("\n结果:")
println("  数据量: $(nrow(df2)) 笔交易")
println("  耗时: $(round(time_second, digits=2)) 秒")
println("  数据一致: $(nrow(df1) == nrow(df2) ? "✅" : "❌")")

if time_first > 0 && time_second > 0
    speedup = time_first / time_second
    println("  加速比: $(round(speedup, digits=1))x")
end

# ============================================================================
# 测试3: 增量下载（部分本地，部分新下载）
# ============================================================================

println("\n\n" * "="^70)
println("测试3: 增量下载")
println("="^70)

# 扩展日期范围（增加一天）
start_date3 = Date(2024, 11, 10)
end_date3 = Date(2024, 11, 13)

start_time3 = DateTime(start_date3)
end_time3 = DateTime(end_date3, Time(23, 59, 59))

println("\n时间范围: $start_time3 到 $end_time3")
println("期望: 前3天从本地加载，第4天从 Vision 下载")

# 检查哪些日期本地已有
println("\n本地数据检查:")
for date in start_date3:Day(1):end_date3
    has_data = has_local_data("BTCUSDT", date, :futures)
    status = has_data ? "✅ 本地" : "📥 需下载"
    println("  $status $date")
end

time_start = time()
df3 = fetch_data(
    "BTCUSDT",
    start_time3,
    end_time3,
    market=:futures,
    use_cache=true,
    verbose=true
)
time_incremental = time() - time_start

println("\n结果:")
println("  数据量: $(nrow(df3)) 笔交易")
println("  耗时: $(round(time_incremental, digits=2)) 秒")

# ============================================================================
# 测试4: 数据验证
# ============================================================================

println("\n\n" * "="^70)
println("测试4: 数据完整性验证")
println("="^70)

println("\n验证本地数据...")

for date in start_date3:Day(1):end_date3
    if has_local_data("BTCUSDT", date, :futures)
        is_valid = validate_local_data("BTCUSDT", date, :futures)
        status = is_valid ? "✅" : "❌"
        println("  $status $date")
        
        if is_valid
            # 显示数据统计
            df_day = load_local_data("BTCUSDT", date, :futures)
            if nrow(df_day) > 0
                println("      行数: $(nrow(df_day))")
                println("      时间范围: $(df_day[1, :timestamp]) 到 $(df_day[end, :timestamp])")
            end
        end
    else
        println("  ⚠️  $date (无本地数据)")
    end
end

# ============================================================================
# 测试5: 多交易对下载
# ============================================================================

println("\n\n" * "="^70)
println("测试5: 多交易对下载")
println("="^70)

symbols = ["BTCUSDT", "ETHUSDT"]
start_date5 = Date(2024, 11, 12)
end_date5 = Date(2024, 11, 12)

start_time5 = DateTime(start_date5)
end_time5 = DateTime(end_date5, Time(23, 59, 59))

println("\n交易对: $(join(symbols, ", "))")
println("日期: $start_date5")

for symbol in symbols
    println("\n下载 $symbol...")
    
    time_start = time()
    df_symbol = fetch_data(
        symbol,
        start_time5,
        end_time5,
        market=:futures,
        use_cache=true,
        verbose=false
    )
    time_symbol = time() - time_start
    
    println("  数据量: $(nrow(df_symbol)) 笔交易")
    println("  耗时: $(round(time_symbol, digits=2)) 秒")
    
    # 验证本地保存
    has_data = has_local_data(symbol, start_date5, :futures)
    println("  本地保存: $(has_data ? "✅" : "❌")")
end

# ============================================================================
# 测试6: 本地存储信息
# ============================================================================

println("\n\n" * "="^70)
println("测试6: 本地存储信息")
println("="^70)

get_local_storage_info(market=:futures, detailed=true)

# ============================================================================
# 测试7: 数据修复
# ============================================================================

println("\n\n" * "="^70)
println("测试7: 数据修复功能")
println("="^70)

repair_local_data("BTCUSDT", :futures)

# ============================================================================
# 测试8: 缓存管理
# ============================================================================

println("\n\n" * "="^70)
println("测试8: 回测缓存管理")
println("="^70)

# 创建一些回测缓存
println("\n创建回测缓存...")
df_bt = fetch_data_for_backtest(
    "BTCUSDT",
    DateTime(2024, 11, 12, 0, 0, 0),
    DateTime(2024, 11, 12, 12, 0, 0),
    market=:futures
)
println("  缓存创建: $(nrow(df_bt)) 笔交易")

# 查看缓存信息
println("\n回测缓存信息:")
get_cache_info()

# ============================================================================
# 测试9: 清理功能（预览模式）
# ============================================================================

println("\n\n" * "="^70)
println("测试9: 清理功能（预览）")
println("="^70)

println("\n预览清理 30 天前的本地数据:")
result = clean_local_data(older_than_days=30, market=:futures, dry_run=true)

println("\n预览清理 7 天前的回测缓存:")
# clear_backtest_cache 不支持 dry_run，这里只显示信息
println("  使用 clear_backtest_cache(older_than_days=7) 来清理")

# ============================================================================
# 测试10: 性能对比
# ============================================================================

println("\n\n" * "="^70)
println("测试10: 性能对比总结")
println("="^70)

println("\n性能对比:")
println("  首次下载（Vision + 保存）: $(round(time_first, digits=2)) 秒")
println("  第二次加载（本地）:        $(round(time_second, digits=2)) 秒")
println("  增量下载（部分本地）:      $(round(time_incremental, digits=2)) 秒")

if time_first > 0 && time_second > 0
    println("\n加速效果:")
    println("  本地加载 vs 首次下载: $(round(time_first/time_second, digits=1))x 更快")
end

# ============================================================================
# 测试总结
# ============================================================================

println("\n\n" * "="^70)
println("测试总结")
println("="^70)

println("\n✅ 所有测试完成！")

println("\n关键指标:")
println("  • 本地存储路径: $LOCAL_DATA_DIR")
println("  • 回测缓存路径: $BACKTEST_CACHE_DIR")

# 显示存储摘要
println()
print_storage_summary()

println("\n建议:")
println("  • 定期运行 clean_local_data() 清理旧数据")
println("  • 定期运行 repair_local_data() 检查数据完整性")
println("  • 使用 get_local_storage_info() 查看存储状态")

println("\n" * "="^70)

# 在测试结束前添加格式统计

println("\n\n" * "="^70)
println("存储格式统计")
println("="^70)

print_storage_summary()

println("\n提示:")
println("  • Parquet 格式占用空间更小（约节省 70-80%）")
println("  • Parquet 格式读取速度更快（约快 2-5x）")
println("  • 使用 convert_to_parquet.jl 转换现有 CSV 文件")

println("\n" * "="^70)