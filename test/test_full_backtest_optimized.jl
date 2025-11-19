# test/test_full_backtest_optimized.jl

using Pkg
Pkg.activate(".")

using Dates
using DataFrames

include("../src/backtest/backtest_engine.jl")
include("../src/data/data_manager.jl")

println("="^70)
println("优化后的完整回测测试")
println("="^70)

# ✅ 优化后的配置
config = (
    grid_spacing = 0.01,          # 1%间距（更保守）
    max_grid_levels = 5,          # 5层（减少频繁交易）
    ddown_factor = 1.5
)

symbol = :BTCUSDT

# 加载数据
println("\n📥 加载数据...")
tick_data = fetch_data_for_backtest(
    "BTCUSDT",
    DateTime(2024, 11, 13, 0, 0, 0),
    DateTime(2024, 11, 14, 0, 0, 0),
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

# ✅ 额外分析
println("\n" * "="^70)
println("交易分析")
println("="^70)

if !isempty(engine.trade_log)
    println("\n前10笔交易:")
    for (i, trade) in enumerate(engine.trade_log[1:min(10, end)])
        side_emoji = trade["side"] == :BUY ? "🟢" : "🔴"
        hedge_str = trade["is_hedge"] ? "[对冲]" : "[主网格]"
        
        println("  $(i). $side_emoji $(trade["side"]) $(trade["quantity"]) @ \$$(round(trade["price"], digits=2)) $hedge_str")
    end
    
    println("\n交易分布:")
    buy_trades = count(t -> t["side"] == :BUY, engine.trade_log)
    sell_trades = count(t -> t["side"] == :SELL, engine.trade_log)
    hedge_trades = count(t -> t["is_hedge"], engine.trade_log)
    
    println("  买入: $buy_trades")
    println("  卖出: $sell_trades")
    println("  对冲: $hedge_trades")
end

println("\n✅ 回测完成！")