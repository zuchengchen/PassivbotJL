#!/usr/bin/env julia

# scripts/download_historical_data.jl

"""
批量下载历史数据

用法：
    julia scripts/download_historical_data.jl BTCUSDT 2024-01 2024-12
    
参数：
    symbol: 交易对
    start: 开始年月 (YYYY-MM)
    end: 结束年月 (YYYY-MM)
"""

using Dates
using DataFrames
using CSV

include("../src/data/binance_vision.jl")

# ============================================================================
# 解析参数
# ============================================================================

if length(ARGS) < 3
    println("""
    用法: julia scripts/download_historical_data.jl SYMBOL START END
    
    示例: julia scripts/download_historical_data.jl BTCUSDT 2024-01 2024-12
    """)
    exit(1)
end

symbol = ARGS[1]
start_str = ARGS[2]
end_str = ARGS[3]

# 解析日期
start_parts = split(start_str, "-")
start_year = parse(Int, start_parts[1])
start_month = parse(Int, start_parts[2])

end_parts = split(end_str, "-")
end_year = parse(Int, end_parts[1])
end_month = parse(Int, end_parts[2])

# ============================================================================
# 下载
# ============================================================================

println("\n" * "="^70)
println("批量下载历史数据")
println("="^70)
println("\n配置:")
println("  交易对: $symbol")
println("  开始: $start_year-$(lpad(start_month, 2, '0'))")
println("  结束: $end_year-$(lpad(end_month, 2, '0'))")
println()

# 创建输出目录
output_dir = "data/historical/$symbol"
mkpath(output_dir)

println("📁 输出目录: $output_dir")
println()

# 下载所有月份
df = download_multiple_months(
    symbol,
    start_year,
    start_month,
    end_year,
    end_month,
    market=:futures,
    use_cache=true
)

if nrow(df) > 0
    println("\n✅ 下载完成！")
    
    # 打印摘要
    print_data_summary(df)
    
    # 保存合并文件
    combined_file = joinpath(output_dir, "$(symbol)_$(start_str)_to_$(end_str)_combined.csv")
    CSV.write(combined_file, df)
    
    file_size_mb = stat(combined_file).size / 1024 / 1024
    println("\n💾 合并文件已保存:")
    println("  路径: $combined_file")
    println("  大小: $(round(file_size_mb, digits=2)) MB")
    
    # 按月保存
    println("\n📅 按月保存...")
    df.year_month = Dates.format.(df.timestamp, "yyyy-mm")
    
    for ym in unique(df.year_month)
        month_df = filter(row -> row.year_month == ym, df)
        month_file = joinpath(output_dir, "$(symbol)_$(ym).csv")
        CSV.write(month_file, select(month_df, Not(:year_month)))
        println("  ✅ $ym: $(nrow(month_df)) 行")
    end
    
    println("\n🎉 所有数据已保存到: $output_dir")
    
else
    println("\n❌ 没有下载到数据")
    exit(1)
end

println("\n" * "="^70)
println("完成！")
println("="^70)