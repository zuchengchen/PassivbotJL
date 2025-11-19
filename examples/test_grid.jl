# examples/test_grid.jl

"""
测试网格管理功能
"""

using PassivbotJL
using Dates

println("\n" * "="^70)
println("测试网格管理系统")
println("="^70)

# 加载配置
config = load_config("config/strategy.yaml")

# 创建交易所连接
exchange = BinanceFutures(config.exchange)

# ============================================================================
# 测试1: 动态网格间距计算
# ============================================================================
println("\n📊 测试1: 动态网格间距计算")

try
    # 获取BTC市场分析
    analysis = PassivbotJL.analyze_market(exchange, :BTCUSDT, config)
    
    # 测试不同仓位下的间距
    println("\n不同仓位比例下的网格间距:")
    println(rpad("仓位比例", 15) * "网格间距")
    println("-"^30)
    
    for position_ratio in [0.0, 0.2, 0.4, 0.6, 0.8]
        spacing = calculate_grid_spacing(
            analysis.volatility,
            position_ratio,
            config.long.grid,
            true  # BTC是主流币
        )
        
        println(rpad("$(round(position_ratio*100, digits=0))%", 15) * 
                "$(round(spacing*100, digits=2))%")
    end
    
    println("\n✅ 动态间距计算成功")
    
catch e
    println("❌ 失败: $e")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试2: 网格层级计算
# ============================================================================
println("\n\n📈 测试2: 网格层级计算")

try
    current_price = get_ticker_price(exchange, :BTCUSDT)
    
    # 计算做多网格层级
    levels = calculate_grid_levels(
        current_price,
        LONG,
        0.015,  # 1.5% 间距
        5,      # 5层
        1.5     # 1.5倍马丁
    )
    
    println("\n做多网格层级 (入场价: \$$(round(current_price, digits=2))):")
    println(rpad("层级", 8) * rpad("价格", 15) * "数量倍数")
    println("-"^35)
    
    for level in levels
        println(rpad(string(level.level), 8) *
                rpad("\$$(round(level.price, digits=2))", 15) *
                "$(round(level.quantity_multiplier, digits=2))x")
    end
    
    println("\n✅ 网格层级计算成功")
    
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试3: 止盈层级计算
# ============================================================================
println("\n\n🎯 测试3: 止盈层级计算")

try
    average_entry = 95000.0
    total_quantity = 0.1
    
    tp_levels = calculate_take_profit_levels(
        average_entry,
        total_quantity,
        LONG,
        config.long.take_profit
    )
    
    println("\n止盈层级 (平均入场: \$$(average_entry)):")
    println(rpad("序号", 8) * rpad("价格", 15) * rpad("数量", 12) * "利润%")
    println("-"^45)
    
    for (i, tp) in enumerate(tp_levels)
        println(rpad(string(i), 8) *
                rpad("\$$(round(tp.price, digits=2))", 15) *
                rpad(string(round(tp.quantity, digits=4)), 12) *
                "$(round(tp.profit_pct, digits=2))%")
    end
    
    println("\n✅ 止盈层级计算成功")
    
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试4: 创建模拟网格
# ============================================================================
println("\n\n🔧 测试4: 创建模拟网格")

try
    # 获取市场分析
    analysis = PassivbotJL.analyze_market(exchange, :BTCUSDT, config)
    
    # 创建网格
    grid = create_martingale_grid(
        :BTCUSDT,
        LONG,
        analysis.cci_signal,
        analysis.trend,
        analysis.volatility,
        config.long,
        10000.0  # 初始资金$10000
    )
    
    println("\n✅ 网格创建成功")
    
    # 模拟添加入场
    current_price = analysis.current_price
    base_quantity = 0.01
    
    println("\n添加网格入场层级:")
    for i in 1:3
        entry_price = current_price * (1.0 - grid.current_spacing * i)
        level = add_grid_entry(grid, entry_price, base_quantity, current_price)
        
        if !isnothing(level)
            println("  层级 $i: \$$(round(entry_price, digits=2)), 数量: $(round(level.quantity, digits=4))")
        end
    end
    
    # 模拟成交第一层
    println("\n模拟第一层成交...")
    mark_level_filled(grid, 1, "TEST_ORDER_1", grid.levels[1].price)
    
    # 更新指标
    update_grid_metrics(grid, current_price, 10000.0)
    
    # 创建止盈订单
    create_take_profit_orders(grid, config.long.take_profit)
    
    # 打印网格状态
    print_grid_status(grid, current_price)
    
    # 检查健康状态
    health = check_grid_health(grid, current_price, config.long.risk)
    
    println("\n🏥 网格健康检查:")
    println("  健康状态: $(health.is_healthy ? "✅ 正常" : "⚠️  异常")")
    
    if !isempty(health.warnings)
        println("  警告:")
        for warning in health.warnings
            println("    - $warning")
        end
    end
    
    println("  应该关闭: $(health.should_close ? "是" : "否")")
    
catch e
    println("❌ 失败: $e")
    showerror(stdout, e, catch_backtrace())
end

println("\n" * "="^70)
println("✅ 网格测试完成！")
println("="^70)