# test/test_full_backtest.jl

using Pkg
Pkg.activate(".")

using Dates
using DataFrames

include("../src/backtest/backtest_engine.jl")
include("../src/data/data_manager.jl")

println("="^70)
println("完整回测测试")
println("="^70)

# 配置
config = (
    grid_spacing = 0.005,
    max_grid_levels = 6,
    ddown_factor = 1.5
)

symbol = :BTCUSDT

# 加载数据
println("\n📥 加载数据...")
tick_data = fetch_data_for_backtest(
    "BTCUSDT",
    DateTime(2024, 11, 13, 0, 0, 0),
    DateTime(2024, 11, 14, 0, 0, 0),  # 24小时
    market=:futures
)

println("✅ 数据加载完成: $(nrow(tick_data)) ticks")

# 创建回测引擎
println("\n🔧 创建回测引擎...")
engine = BacktestEngine(config, symbol, tick_data, initial_capital=10000.0)

# 初始化
println("\n⚙️  初始化引擎...")
initialize!(engine)

println("✅ 引擎初始化完成")

# 运行回测
println("\n🚀 开始回测...")
run!(engine)

# 性能报告
print_performance_report(engine)

# 打印持仓
print_positions(engine.position_manager)

# Broker统计
print_broker_stats(engine.broker)

println("\n✅ 回测完成！")