# test/test_take_profit.jl

using Pkg
Pkg.activate(".")

using Dates
using Logging

include("../src/backtest/main_grid_manager.jl")
include("../src/execution/position_manager.jl")

# 启用调试日志
global_logger(ConsoleLogger(stderr, Logging.Debug))

println("="^70)
println("测试止盈平仓逻辑")
println("="^70)

# 创建持仓管理器
pm = PositionManager()

# 模拟建仓（3笔买入）
fills = [
    (timestamp=now(), symbol=:BTCUSDT, side=:BUY, quantity=0.01, fill_price=92278.0, 
     commission=0.37, order_id="1", client_order_id="c1", reduce_only=false, 
     grid_level=1, is_hedge=false),
    
    (timestamp=now(), symbol=:BTCUSDT, side=:BUY, quantity=0.015, fill_price=90374.0, 
     commission=0.54, order_id="2", client_order_id="c2", reduce_only=false, 
     grid_level=2, is_hedge=false),
    
    (timestamp=now(), symbol=:BTCUSDT, side=:BUY, quantity=0.0225, fill_price=89427.0, 
     commission=0.80, order_id="3", client_order_id="c3", reduce_only=false, 
     grid_level=3, is_hedge=false)
]

println("\n📥 建仓...")
for fill in fills
    on_fill!(pm, fill)
    println("  买入 $(fill.quantity) @ \$$(fill.fill_price)")
end

# 检查持仓
position = get_position_record(pm, :BTCUSDT, false)

println("\n📊 建仓后持仓:")
println("  数量: $(position.size)")
println("  平均价: \$$(round(position.entry_price, digits=2))")
println("  总成本: \$$(round(position.total_cost, digits=2))")

# 手工计算验证
expected_qty = 0.01 + 0.015 + 0.0225
expected_avg = (0.01*92278 + 0.015*90374 + 0.0225*89427) / expected_qty
expected_cost = 0.01*92278 + 0.015*90374 + 0.0225*89427 + 0.37 + 0.54 + 0.80

println("\n✅ 验证:")
println("  预期数量: $expected_qty")
println("  实际数量: $(position.size)")
println("  匹配: $(abs(position.size - expected_qty) < 0.0001 ? "✅" : "❌")")

println("\n  预期平均价: \$$(round(expected_avg, digits=2))")
println("  实际平均价: \$$(round(position.entry_price, digits=2))")
println("  匹配: $(abs(position.entry_price - expected_avg) < 1.0 ? "✅" : "❌")")

# 模拟止盈平仓（2笔卖出）
tp_fills = [
    (timestamp=now(), symbol=:BTCUSDT, side=:SELL, quantity=0.004, fill_price=92730.0, 
     commission=0.15, order_id="4", client_order_id="tp1", reduce_only=true,  # ✅ 关键
     grid_level=nothing, is_hedge=false),
    
    (timestamp=now(), symbol=:BTCUSDT, side=:SELL, quantity=0.004, fill_price=93191.0, 
     commission=0.15, order_id="5", client_order_id="tp2", reduce_only=true,  # ✅ 关键
     grid_level=nothing, is_hedge=false)
]

println("\n📤 止盈平仓...")
for fill in tp_fills
    on_fill!(pm, fill)
    println("  卖出 $(fill.quantity) @ \$$(fill.fill_price) [reduce_only=true]")
end

# 检查平仓后持仓
position_after = get_position_record(pm, :BTCUSDT, false)

println("\n📊 平仓后持仓:")
if !isnothing(position_after)
    println("  数量: $(position_after.size)")
    println("  平均价: \$$(round(position_after.entry_price, digits=2))")
    println("  已实现盈亏: \$$(round(position_after.realized_pnl, digits=2))")
else
    println("  持仓已完全平仓")
end

# 验证
expected_remaining = expected_qty - 0.004 - 0.004

println("\n✅ 最终验证:")
if !isnothing(position_after)
    println("  预期剩余数量: $expected_remaining")
    println("  实际剩余数量: $(position_after.size)")
    println("  匹配: $(abs(position_after.size - expected_remaining) < 0.0001 ? "✅" : "❌")")
    
    println("\n  平均价应保持不变: \$$(round(expected_avg, digits=2))")
    println("  实际平均价: \$$(round(position_after.entry_price, digits=2))")
    println("  匹配: $(abs(position_after.entry_price - expected_avg) < 1.0 ? "✅" : "❌")")
end

println("\n✅ 止盈平仓测试完成！")