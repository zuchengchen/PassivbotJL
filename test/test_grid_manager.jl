# test/test_grid_manager.jl

using Pkg
Pkg.activate(".")

using Dates

include("../src/backtest/main_grid_manager.jl")

println("="^70)
println("测试主网格管理器")
println("="^70)

# 模拟配置
config = (
    grid_spacing = 0.005,
    max_grid_levels = 6,
    ddown_factor = 1.5
)

# 创建管理器
mgr = MainGridManager(config)
println("\n✅ GridManager创建成功")

# 模拟信号
signal = (
    timestamp = now(),
    symbol = :BTCUSDT,
    signal_type = :LONG_ENTRY,
    strength = 0.8,
    grid_spacing = 0.005,
    max_levels = 6,
    ddown_factor = 1.5,
    indicators = Dict(:cci => -150.0, :adx => 35.0)
)

current_price = 90000.0

# 初始化网格
println("\n📊 初始化网格...")
grid = initialize_grid!(mgr, signal, current_price)

if !isnothing(grid)
    println("✅ 网格初始化成功")
    println("  符号: $(grid.symbol)")
    println("  方向: $(grid.side)")
    println("  网格层数: $(length(grid.levels))")
    println("  止盈层数: $(length(grid.take_profit_levels))")
    
    println("\n网格层级:")
    for level in grid.levels
        println("  Level $(level.level): \$$(round(level.price, digits=2)) x $(round(level.quantity, digits=4))")
    end
    
    println("\n止盈层级:")
    for tp in grid.take_profit_levels
        println("  TP $(tp.level): \$$(round(tp.price, digits=2))")
    end
else
    println("❌ 网格初始化失败")
    exit(1)
end

# 测试价格触发
println("\n🔍 测试价格触发...")

# 模拟价格下跌，触发第一层
test_price_1 = grid.levels[1].price
triggers = check_price_triggers(mgr, :BTCUSDT, test_price_1, now())

if length(triggers) > 0
    println("✅ 触发了 $(length(triggers)) 个网格层级")
    for trigger in triggers
        println("  Level $(trigger.grid_level): \$$(round(trigger.trigger_price, digits=2)) x $(trigger.order_quantity)")
    end
else
    println("❌ 未触发网格")
end

# 模拟成交
println("\n💰 模拟成交...")
fill = (
    timestamp = now(),
    symbol = :BTCUSDT,
    side = :BUY,
    quantity = grid.levels[1].quantity,
    fill_price = grid.levels[1].price,
    commission = 3.6,
    order_id = "TEST_001",
    client_order_id = "client_001",
    grid_level = 1,
    is_hedge = false
)

on_grid_fill!(mgr, fill)

println("✅ 成交处理完成")
println("  总持仓: $(round(grid.total_quantity, digits=4))")
println("  平均成本: \$$(round(grid.average_entry, digits=2))")

# 更新盈亏
println("\n📈 更新盈亏...")
update_grid_pnl!(grid, 91000.0)  # 价格上涨

println("✅ 盈亏更新完成")
println("  浮盈: \$$(round(grid.unrealized_pnl, digits=2))")

# 打印完整状态
print_grid_status(grid, 91000.0)

# 测试止盈检查
println("\n🎯 测试止盈检查...")
tp_event = check_take_profit(mgr, :BTCUSDT, grid.take_profit_levels[1].price, now())

if !isnothing(tp_event)
    println("✅ 止盈触发")
    println("  层级: $(tp_event.tp_level)")
    println("  价格: \$$(round(tp_event.tp_price, digits=2))")
    println("  数量: $(round(tp_event.close_quantity, digits=4))")
    println("  盈利: \$$(round(tp_event.profit_amount, digits=2))")
else
    println("⏳ 止盈未触发")
end

# 统计信息
println("\n📊 管理器统计:")
println("  活跃网格: $(length(mgr.active_grids))")
println("  历史网格: $(length(mgr.closed_grids))")
println("  总创建数: $(mgr.total_grids_created)")

println("\n✅ 所有测试完成！")