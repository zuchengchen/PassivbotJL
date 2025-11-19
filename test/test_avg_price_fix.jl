# test/test_avg_price_fix.jl

using Pkg
Pkg.activate(".")

println("="^70)
println("测试平均成本计算修复")
println("="^70)

include("../src/backtest/main_grid_manager.jl")

# 创建测试网格
config = (
    grid_spacing = 0.01,
    max_grid_levels = 5,
    ddown_factor = 1.5
)

mgr = MainGridManager(config)

# 模拟信号
signal = (
    timestamp = now(),
    symbol = :BTCUSDT,
    signal_type = :LONG_ENTRY,
    strength = 0.8,
    grid_spacing = 0.01,
    max_levels = 5,
    ddown_factor = 1.5,
    indicators = Dict{Symbol, Any}()
)

# 初始化网格
grid = initialize_grid!(mgr, signal, 90000.0)

println("\n初始状态:")
println("  平均入场价: \$$(grid.average_entry)")
println("  总持仓: $(grid.total_quantity)")
println("  总成本: \$$(grid.total_cost)")

# 模拟第一笔成交
fill1 = (
    timestamp = now(),
    symbol = :BTCUSDT,
    side = :BUY,
    quantity = 0.01,
    fill_price = 90000.0,
    commission = 3.6,
    order_id = "TEST_001",
    grid_level = 1,
    is_hedge = false
)

on_grid_fill!(mgr, fill1)

println("\n第一笔成交后:")
println("  买入: 0.01 BTC @ \$90,000")
println("  手续费: \$3.6")
println("  平均入场价: \$$(round(grid.average_entry, digits=2))")
println("  总持仓: $(grid.total_quantity)")
println("  总成本: \$$(round(grid.total_cost, digits=2))")

# 预期结果
expected_avg = 90000.0
expected_cost = 90000.0 * 0.01 + 3.6  # 903.6

println("\n✅ 验证:")
println("  预期平均价: \$$(expected_avg)")
println("  实际平均价: \$$(round(grid.average_entry, digits=2))")
println("  匹配: $(abs(grid.average_entry - expected_avg) < 0.01 ? "✅" : "❌")")

println("\n  预期总成本: \$$(expected_cost)")
println("  实际总成本: \$$(round(grid.total_cost, digits=2))")
println("  匹配: $(abs(grid.total_cost - expected_cost) < 0.01 ? "✅" : "❌")")

# 模拟第二笔成交（加仓）
fill2 = (
    timestamp = now(),
    symbol = :BTCUSDT,
    side = :BUY,
    quantity = 0.015,
    fill_price = 89000.0,
    commission = 5.34,
    order_id = "TEST_002",
    grid_level = 2,
    is_hedge = false
)

on_grid_fill!(mgr, fill2)

println("\n第二笔成交后:")
println("  买入: 0.015 BTC @ \$89,000")
println("  手续费: \$5.34")
println("  平均入场价: \$$(round(grid.average_entry, digits=2))")
println("  总持仓: $(grid.total_quantity)")
println("  总成本: \$$(round(grid.total_cost, digits=2))")

# 预期结果
# 平均价 = (0.01 * 90000 + 0.015 * 89000) / 0.025
expected_avg_2 = (0.01 * 90000.0 + 0.015 * 89000.0) / 0.025
expected_cost_2 = 903.6 + (89000.0 * 0.015 + 5.34)

println("\n✅ 验证:")
println("  预期平均价: \$$(round(expected_avg_2, digits=2))")
println("  实际平均价: \$$(round(grid.average_entry, digits=2))")
println("  匹配: $(abs(grid.average_entry - expected_avg_2) < 0.01 ? "✅" : "❌")")

println("\n  预期总成本: \$$(round(expected_cost_2, digits=2))")
println("  实际总成本: \$$(round(grid.total_cost, digits=2))")
println("  匹配: $(abs(grid.total_cost - expected_cost_2) < 0.01 ? "✅" : "❌")")

# 计算盈亏
current_price = 91000.0
unrealized_pnl = (current_price - grid.average_entry) * grid.total_quantity

println("\n📊 盈亏计算:")
println("  当前价格: \$$(current_price)")
println("  平均成本: \$$(round(grid.average_entry, digits=2))")
println("  持仓数量: $(grid.total_quantity)")
println("  浮盈: \$$(round(unrealized_pnl, digits=2))")

pnl_pct = (unrealized_pnl / grid.total_cost) * 100
println("  盈亏比例: $(round(pnl_pct, digits=2))%")

println("\n✅ 平均成本计算修复测试完成！")