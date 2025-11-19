# examples/test_api_simple.jl

"""
简单的 API 测试
"""

include("../src/data/binance_api.jl")

println("\n" * "="^70)
println("Binance API 简单测试")
println("="^70)

# 启用备用域名
set_api_config(use_backup=true)

# 打印状态和测试连接
print_api_status()