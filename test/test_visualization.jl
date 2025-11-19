# test/test_visualization.jl

using Pkg
Pkg.activate(".")

using Dates
using DataFrames

include("../src/backtest/backtest_engine.jl")
include("../src/data/data_manager.jl")
include("../src/analysis/performance_plots.jl")

println("="^70)
println("回测 + 可视化分析")
println("="^70)

# 配置
config = (
    grid_spacing = 0.01,
    max_grid_levels = 5,
    ddown_factor = 1.5
)

# 加载数据
println("\n📥 加载数据...")
tick_data = fetch_data_for_backtest(
    "BTCUSDT",
    DateTime(2024, 11, 13, 0, 0, 0),
    DateTime(2024, 11, 14, 0, 0, 0),
    market=:futures
)

# 运行回测
println("\n🚀 运行回测...")
engine = BacktestEngine(config, :BTCUSDT, tick_data, initial_capital=10000.0)
initialize!(engine)
run!(engine)

# 性能报告
print_performance_report(engine)

# 生成图表
println("\n📊 生成可视化图表...")
mkpath("results")

plot_equity_curve(engine, save_path="results/equity_curve.png")
plot_drawdown(engine, save_path="results/drawdown.png")
plot_trades(engine, save_path="results/trades.png")
plot_dashboard(engine, save_path="results/dashboard.png")

println("\n✅ 图表已保存到 results/ 目录")