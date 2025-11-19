# examples/debug_csv_format.jl

"""
检查Binance Vision CSV实际格式
"""

using ZipFile
using CSV
using DataFrames

# 使用已缓存的文件
cache_file = "data/cache/BTCUSDT-aggTrades-2025-11-12.zip"

if !isfile(cache_file)
    println("缓存文件不存在: $cache_file")
    exit(1)
end

println("检查文件: $cache_file")

# 读取ZIP
zf = ZipFile.Reader(cache_file)

println("ZIP包含 $(length(zf.files)) 个文件:")
for f in zf.files
    println("  - $(f.name)")
end

# 读取第一个文件
csv_file = zf.files[1]
csv_data = read(csv_file, String)

close(zf)

# 显示前几行
lines = split(csv_data, '\n')
println("\n前10行原始数据:")
for (i, line) in enumerate(lines[1:min(10, length(lines))])
    println("$i: $line")
end

# 检查列数
first_line = lines[1]
fields = split(first_line, ',')
println("\n第一行字段数: $(length(fields))")

# 尝试解析
println("\n尝试用CSV.jl解析:")
df = CSV.read(IOBuffer(csv_data), DataFrame, header=false, limit=5)

println("DataFrame列数: $(ncol(df))")
println("DataFrame列名: $(names(df))")
println("\n前5行:")
println(df)