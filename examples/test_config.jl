# examples/test_config.jl

"""
测试配置加载

运行方法：
julia --project=. examples/test_config.jl
"""

using PassivbotJL

# 加载配置
config = load_config("config/strategy.yaml")

# 打印配置摘要
print_config_summary(config)

# 测试访问配置
println("\n测试配置访问：")
println("Long enabled: $(config.long.enabled)")
println("Long leverage: $(config.long.leverage)x")
println("Grid base spacing: $(config.long.grid.base_spacing*100)%")
println("ATR multiplier: $(config.long.grid.atr_multiplier_major)")

# 测试日志
@info "这是一条Info日志"
@warn "这是一条Warning日志"
@debug "这是一条Debug日志（默认不显示）"

println("\n✅ 配置加载测试完成！")