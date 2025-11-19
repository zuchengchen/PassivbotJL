# test/test_hedge_manager.jl

using Pkg
Pkg.activate(".")

using Dates

include("../src/backtest/hedge_grid_manager.jl")

println("="^70)
println("测试对冲网格管理器")
println("="^70)

# 模拟配置
config = (
    grid_spacing = 0.005,
    max_grid_levels = 6,
    ddown_factor = 1.5
)

# 创建管理器
mgr = HedgeGridManager(config)
println("\n✅ HedgeGridManager创建成功")
println("  回撤阈值: $(mgr.drawdown_threshold * 100)%")
println("  时间阈值: $(mgr.time_threshold)")

# 模拟被套的主仓位
println("\n📉 模拟主仓位被套...")
position = (
    symbol = :BTCUSDT,
    side = :BUY,
    size = 0.1,
    entry_price = 90000.0,
    total_cost = 9000.0,
    unrealized_pnl = -500.0,  # 亏损$500
    open_time = now() - Hour(3)  # 持仓3小时
)

current_price = 85000.0  # 价格大幅下跌

# 检查是否应该触发对冲
println("\n🔍 检查对冲触发条件...")
trigger = should_activate_hedge(mgr, position, current_price, now(), config)

if !isnothing(trigger)
    println("✅ 对冲触发")
    println("  原因: $(trigger.reason)")
    println("  当前价格: \$$(round(trigger.current_price, digits=2))")
    println("  未实现盈亏: \$$(round(trigger.unrealized_pnl, digits=2))")
    println("  盈亏比例: $(round(trigger.unrealized_pnl_pct, digits=2))%")
    println("  对冲比例: $(trigger.hedge_ratio * 100)%")
else
    println("❌ 对冲未触发")
    exit(1)
end

# 初始化对冲网格
println("\n📊 初始化对冲网格...")
hedge = initialize_hedge_grid!(mgr, trigger, current_price)

if !isnothing(hedge)
    println("✅ 对冲网格初始化成功")
    println("  符号: $(hedge.parent_symbol)")
    println("  方向: $(hedge.side) (与主仓位LONG相反)")
    println("  对冲层数: $(length(hedge.levels))")
    
    println("\n对冲层级:")
    for level in hedge.levels
        println("  Level $(level.level): \$$(round(level.price, digits=2)) x $(round(level.quantity, digits=4))")
    end
else
    println("❌ 对冲网格初始化失败")
    exit(1)
end

# 测试对冲触发
println("\n🔍 测试对冲价格触发...")
test_price = hedge.levels[1].price + 100  # 价格上涨，触发做空对冲
triggers = check_hedge_triggers(mgr, :BTCUSDT, test_price, now())

if length(triggers) > 0
    println("✅ 触发了 $(length(triggers)) 个对冲层级")
    for t in triggers
        println("  Level $(t.grid_level): \$$(round(t.trigger_price, digits=2)) x $(t.order_quantity)")
    end
else
    println("⏳ 对冲未触发")
end

# 模拟对冲成交
println("\n💰 模拟对冲成交...")
fill = (
    timestamp = now(),
    symbol = :BTCUSDT,
    side = :SELL,  # 做空对冲
    quantity = hedge.levels[1].quantity,
    fill_price = hedge.levels[1].price,
    commission = 2.0,
    order_id = "HEDGE_001",
    client_order_id = "hedge_client_001",
    grid_level = 1,
    is_hedge = true
)

on_hedge_fill!(mgr, fill)

println("✅ 对冲成交处理完成")
println("  对冲持仓: $(round(hedge.total_quantity, digits=4))")
println("  平均成本: \$$(round(hedge.average_entry, digits=2))")

# 更新对冲盈亏
println("\n📈 更新对冲盈亏...")
profit_price = hedge.average_entry - 2000.0  # 价格下跌，对冲盈利
update_hedge_pnl!(hedge, profit_price)

println("✅ 对冲盈亏更新")
println("  浮盈: \$$(round(hedge.unrealized_pnl, digits=2))")

# 检查利润回收
println("\n🎯 检查利润回收...")
recycle = check_hedge_profit_taking(mgr, hedge, profit_price)

if !isnothing(recycle)
    println("✅ 触发利润回收")
    println("  平仓数量: $(round(recycle.close_quantity, digits=4))")
    println("  利润: \$$(round(recycle.profit, digits=2))")
    println("  回收金额: \$$(round(recycle.recycle_amount, digits=2))")
    
    # 执行回收
    recycle_hedge_profit!(mgr, :BTCUSDT, recycle.recycle_amount)
    println("  ✅ 利润已回收")
else
    println("⏳ 未达到回收条件")
end

# 打印完整状态
print_hedge_status(hedge, profit_price)

# 统计信息
println("\n📊 管理器统计:")
println("  活跃对冲: $(length(mgr.active_hedges))")
println("  历史对冲: $(length(mgr.closed_hedges))")
println("  总创建数: $(mgr.total_hedges_created)")
println("  总回收利润: \$$(round(mgr.total_profit_recycled, digits=2))")

println("\n✅ 所有测试完成！")