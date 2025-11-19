# examples/test_engine.jl

"""
测试交易引擎（模拟模式）
"""

using PassivbotJL

println("\n" * "="^70)
println("测试交易引擎")
println("="^70)

# 加载配置
config = load_config("config/strategy.yaml")

# 创建交易所连接
exchange = BinanceFutures(config.exchange)

# 创建交易引擎
engine = TradingEngine(config, exchange)

println("\n✅ 交易引擎已创建")
println("配置:")
println("  - 循环间隔: $(config.loop_interval_seconds)秒")
println("  - 最大交易对: $(config.portfolio.max_symbols)")
println("  - 做多启用: $(config.long.enabled)")
println("  - 做空启用: $(config.short.enabled)")

# 运行3次迭代进行测试
println("\n🚀 开始测试运行 (3次迭代)...")

try
    start_engine(engine, max_iterations=3)  # 改这里
    
    println("\n✅ 测试运行完成")
    
catch e
    println("\n❌ 测试失败: $e")
    showerror(stdout, e, catch_backtrace())
end

println("\n" * "="^70)