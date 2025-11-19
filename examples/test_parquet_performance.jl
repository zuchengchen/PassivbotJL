# examples/test_parquet_performance.jl

"""
Parquet vs CSV 性能对比测试（使用 Vision 数据）
"""

using Dates
using DataFrames
using CSV
using Parquet
using TimeZones

include("../src/data/data_manager.jl")

println("\n" * "="^70)
println("Parquet vs CSV 性能对比测试")
println("="^70)

# 测试参数（使用历史日期，从 Vision 下载）
symbol = "BTCUSDT"
market = :futures
test_date = Date(2024, 11, 10)

println("\n测试参数:")
println("  交易对: $symbol")
println("  市场: $market")
println("  日期: $test_date")
println("  数据源: Binance Vision (快速)")

# ============================================================================
# 测试1: 下载并保存为两种格式
# ============================================================================

println("\n\n" * "="^70)
println("测试1: 下载并保存")
println("="^70)

# 使用 Vision 下载数据（快速）
println("\n从 Binance Vision 下载数据...")

start_time = DateTime(test_date)
end_time = DateTime(test_date, Time(23, 59, 59))

time_download_start = time()

# 使用 Vision 下载
df = download_date_range_aggtrades(
    symbol,
    test_date,
    test_date,
    market=market,
    use_cache=false,
    merge=true
)

time_download = time() - time_download_start

if nrow(df) == 0
    println("❌ 无法下载数据，测试终止")
    exit(1)
end

println("✅ 下载完成: $(nrow(df)) 笔交易")
println("   下载耗时: $(round(time_download, digits=2)) 秒")

# 清理旧的测试文件
csv_path = get_local_data_path(symbol, test_date, market, CSV_FORMAT)
parquet_path = get_local_data_path(symbol, test_date, market, PARQUET_FORMAT)

for path in [csv_path, parquet_path]
    if isfile(path)
        rm(path)
    end
end

# 保存为 CSV
println("\n保存为 CSV...")
let time_start = time()  # ✅ 使用 let 块
    CSV.write(csv_path, df)
    global csv_write_time = time() - time_start
    global csv_size = stat(csv_path).size / (1024 * 1024)
end

println("  耗时: $(round(csv_write_time, digits=3)) 秒")
println("  大小: $(round(csv_size, digits=2)) MB")

# 保存为 Parquet
println("\n保存为 Parquet...")
let time_start = time()  # ✅ 使用 let 块
    df_parquet = prepare_for_parquet(df)
    write_parquet(parquet_path, df_parquet)
    global parquet_write_time = time() - time_start
    global parquet_size = stat(parquet_path).size / (1024 * 1024)
end

println("  耗时: $(round(parquet_write_time, digits=3)) 秒")
println("  大小: $(round(parquet_size, digits=2)) MB")

# 对比
println("\n💾 保存性能对比:")
println("  CSV:     $(round(csv_write_time, digits=3)) 秒, $(round(csv_size, digits=2)) MB")
println("  Parquet: $(round(parquet_write_time, digits=3)) 秒, $(round(parquet_size, digits=2)) MB")
println("  空间节省: $(round((1 - parquet_size/csv_size)*100, digits=1))%")
if parquet_write_time > 0
    println("  速度对比: $(csv_write_time > parquet_write_time ? "Parquet" : "CSV") 快 $(round(max(csv_write_time, parquet_write_time)/min(csv_write_time, parquet_write_time), digits=2))x")
end

# ============================================================================
# 测试2: 读取性能对比
# ============================================================================

println("\n\n" * "="^70)
println("测试2: 读取性能对比")
println("="^70)

# 读取 CSV（多次测试取平均）
println("\n读取 CSV (5次测试)...")
csv_read_times = Float64[]

for i in 1:5
    let time_start = time()  # ✅ 使用 let 块
        df_csv = CSV.read(csv_path, DataFrame)
        push!(csv_read_times, time() - time_start)
    end
    print(".")
end
println()

csv_avg_read = sum(csv_read_times) / length(csv_read_times)
csv_min_read = minimum(csv_read_times)
csv_max_read = maximum(csv_read_times)

println("  平均耗时: $(round(csv_avg_read, digits=3)) 秒")
println("  最快: $(round(csv_min_read, digits=3)) 秒, 最慢: $(round(csv_max_read, digits=3)) 秒")

# 读取 Parquet（多次测试取平均）
println("\n读取 Parquet (5次测试)...")
parquet_read_times = Float64[]

for i in 1:5
    let time_start = time()  # ✅ 使用 let 块
        df_parquet_read = DataFrame(read_parquet(parquet_path))
        # ✅ 立即恢复 DateTime
        df_parquet_restored = restore_from_parquet(df_parquet_read)
        push!(parquet_read_times, time() - time_start)
    end
    print(".")
end
println()

parquet_avg_read = sum(parquet_read_times) / length(parquet_read_times)
parquet_min_read = minimum(parquet_read_times)
parquet_max_read = maximum(parquet_read_times)

println("  平均耗时: $(round(parquet_avg_read, digits=3)) 秒")
println("  最快: $(round(parquet_min_read, digits=3)) 秒, 最慢: $(round(parquet_max_read, digits=3)) 秒")

# 对比
println("\n📖 读取性能对比:")
println("  CSV:     $(round(csv_avg_read, digits=3)) 秒")
println("  Parquet: $(round(parquet_avg_read, digits=3)) 秒")
if parquet_avg_read > 0
    speedup = csv_avg_read / parquet_avg_read
    if speedup >= 1.0
        println("  速度提升: $(round(speedup, digits=2))x (Parquet 更快)")
    else
        println("  速度: CSV 快 $(round(1/speedup, digits=2))x")
    end
end

# ============================================================================
# 测试3: 数据完整性验证
# ============================================================================

println("\n\n" * "="^70)
println("测试3: 数据完整性验证")
println("="^70)

df_csv = CSV.read(csv_path, DataFrame)
df_parquet_loaded = DataFrame(read_parquet(parquet_path))
df_parquet_restored = restore_from_parquet(df_parquet_loaded)  # ✅ 恢复 DateTime

# 转换 CSV 的时间列
if eltype(df_csv.timestamp) == String
    df_csv.timestamp = DateTime.(df_csv.timestamp)
end

println("\nCSV 数据:")
println("  行数: $(nrow(df_csv))")
println("  列数: $(ncol(df_csv))")
println("  timestamp 类型: $(eltype(df_csv.timestamp))")

println("\nParquet 数据:")
println("  行数: $(nrow(df_parquet_restored))")
println("  列数: $(ncol(df_parquet_restored))")
println("  timestamp 类型: $(eltype(df_parquet_restored.timestamp))")

# 验证数据一致性
rows_match = nrow(df_csv) == nrow(df_parquet_restored)
cols_match = ncol(df_csv) == ncol(df_parquet_restored)

println("\n数据一致性:")
println("  行数匹配: $(rows_match ? "✅" : "❌")")
println("  列数匹配: $(cols_match ? "✅" : "❌")")

# 验证具体数值
if rows_match && cols_match
    # 检查价格列
    price_match = all(df_csv.price .≈ df_parquet_restored.price)
    quantity_match = all(df_csv.quantity .≈ df_parquet_restored.quantity)
    
    # ✅ 检查时间戳（允许毫秒级差异）
    # 确保两边都是 DateTime 类型
    if eltype(df_csv.timestamp) == DateTime && eltype(df_parquet_restored.timestamp) == DateTime
        time_diffs = abs.(Dates.value.(df_csv.timestamp - df_parquet_restored.timestamp))
        time_match = all(time_diffs .< 1000)  # 允许1秒误差（毫秒单位）
        max_diff = maximum(time_diffs)
        
        println("  价格数据: $(price_match ? "✅" : "❌")")
        println("  数量数据: $(quantity_match ? "✅" : "❌")")
        println("  时间数据: $(time_match ? "✅" : "❌") (最大差异: $(max_diff) ms)")
    else
        println("  价格数据: $(price_match ? "✅" : "❌")")
        println("  数量数据: $(quantity_match ? "✅" : "❌")")
        println("  时间数据: ⚠️  类型不匹配")
    end
    
    # 采样验证
    sample_size = min(5, nrow(df_csv))
    println("\n数据采样 (前 $sample_size 行):")
    println("\nCSV:")
    println(first(df_csv, sample_size))
    println("\nParquet:")
    println(first(df_parquet_restored, sample_size))
end

# ============================================================================
# 测试4: 内存使用对比
# ============================================================================

println("\n\n" * "="^70)
println("测试4: 内存使用")
println("="^70)

println("\n原始 DataFrame:")
println("  内存占用: $(round(Base.summarysize(df) / (1024 * 1024), digits=2)) MB")

println("\nCSV 读取:")
df_csv_mem = CSV.read(csv_path, DataFrame)
println("  内存占用: $(round(Base.summarysize(df_csv_mem) / (1024 * 1024), digits=2)) MB")

println("\nParquet 读取:")
df_parquet_mem = restore_from_parquet(DataFrame(read_parquet(parquet_path)))
println("  内存占用: $(round(Base.summarysize(df_parquet_mem) / (1024 * 1024), digits=2)) MB")

# ============================================================================
# 测试总结
# ============================================================================

println("\n\n" * "="^70)
println("测试总结")
println("="^70)

println("\n📊 综合对比:")
println("\n存储:")
println("  CSV:     $(round(csv_size, digits=2)) MB")
println("  Parquet: $(round(parquet_size, digits=2)) MB")
println("  节省:    $(round((1 - parquet_size/csv_size)*100, digits=1))%")

println("\n写入速度:")
println("  CSV:     $(round(csv_write_time, digits=3)) 秒")
println("  Parquet: $(round(parquet_write_time, digits=3)) 秒")

println("\n读取速度:")
println("  CSV:     $(round(csv_avg_read, digits=3)) 秒")
println("  Parquet: $(round(parquet_avg_read, digits=3)) 秒")

# 计算总体性能
total_csv_time = csv_write_time + csv_avg_read
total_parquet_time = parquet_write_time + parquet_avg_read

println("\n总体性能 (写入 + 读取):")
println("  CSV:     $(round(total_csv_time, digits=3)) 秒")
println("  Parquet: $(round(total_parquet_time, digits=3)) 秒")

println("\n✅ 结论:")
println("  • Parquet 节省 $(round((1 - parquet_size/csv_size)*100, digits=1))% 存储空间")
if parquet_avg_read < csv_avg_read
    println("  • Parquet 读取快 $(round(csv_avg_read/parquet_avg_read, digits=2))x")
else
    println("  • CSV 读取快 $(round(parquet_avg_read/csv_avg_read, digits=2))x")
end
if total_parquet_time < total_csv_time
    println("  • 总体性能: Parquet 优于 CSV")
else
    println("  • 总体性能: CSV 优于 Parquet")
end

println("\n推荐:")
if parquet_size < csv_size * 0.5
    println("  ✅ 使用 Parquet 格式（空间节省显著）")
else
    println("  ⚠️  根据具体需求选择格式")
end

println("\n" * "="^70)