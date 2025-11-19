# src/strategy/grid_manager.jl

"""
网格管理器

负责网格的创建、维护和订单管理
"""

using DataFrames
using Dates

# ============================================================================
# 网格创建
# ============================================================================

"""
    create_martingale_grid(
        symbol::Symbol,
        side::Side,
        entry_signal::CCISignal,
        trend::TrendState,
        volatility::VolatilityMetrics,
        config::DirectionalConfig,
        initial_capital::Float64
    )::MartingaleGrid

创建新的马丁格尔网格

参数：
- symbol: 交易对
- side: 方向
- entry_signal: 入场信号
- trend: 趋势状态
- volatility: 波动率
- config: 方向性配置
- initial_capital: 初始资金

返回：
- MartingaleGrid
"""
function create_martingale_grid(
    symbol::Symbol,
    side::Side,
    entry_signal::CCISignal,
    trend::TrendState,
    volatility::VolatilityMetrics,
    config::DirectionalConfig,
    initial_capital::Float64
)::MartingaleGrid
    
    @info "Creating martingale grid" symbol=symbol side=side
    
    # ========================================================================
    # 1. 计算网格间距
    # ========================================================================
    
    current_spacing = calculate_grid_spacing(
        volatility,
        0.0,  # 初始仓位为0
        config.grid,
        symbol in [:BTCUSDT, :ETHUSDT]
    )
    
    # ========================================================================
    # 2. 创建空网格
    # ========================================================================
    
    grid = MartingaleGrid(
        symbol,
        side,
        entry_signal,
        trend,
        config.grid.base_spacing,
        current_spacing,
        config.grid.ddown_factor,
        config.grid.max_levels,
        GridLevel[],  # 空的层级列表
        0.0,  # total_quantity
        0.0,  # average_entry
        0.0,  # unrealized_pnl
        0.0,  # wallet_exposure
        0.0,  # liquidation_price
        true,  # active
        true,  # allow_new_entries
        now(),  # creation_time
        nothing,  # last_fill_time
        GridLevel[]  # take_profit_orders
    )
    
    @info "Grid created" spacing_pct=round(current_spacing*100, digits=2)
    
    return grid
end

"""
    add_grid_entry(
        grid::MartingaleGrid,
        entry_price::Float64,
        base_quantity::Float64,
        current_price::Float64
    )::Union{GridLevel, Nothing}

向网格添加新的入场层级

返回：
- GridLevel: 新创建的层级，如果不应该添加则返回 nothing
"""
function add_grid_entry(
    grid::MartingaleGrid,
    entry_price::Float64,
    base_quantity::Float64,
    current_price::Float64
)::Union{GridLevel, Nothing}
    
    # 检查是否应该添加
    if !grid.allow_new_entries
        @debug "New entries not allowed"
        return nothing
    end
    
    # 检查层数限制
    if length(grid.levels) >= grid.max_levels
        @warn "Maximum grid levels reached"
        grid.allow_new_entries = false
        return nothing
    end
    
    # 计算新层级
    level_number = length(grid.levels) + 1
    
    # 计算数量（马丁格尔）
    quantity = calculate_next_grid_quantity(grid, base_quantity)
    
    # 创建新层级
    new_level = GridLevel(
        level_number,
        entry_price,
        quantity,
        false,  # 未成交
        nothing,
        nothing
    )
    
    push!(grid.levels, new_level)
    
    @info "Grid level added" level=level_number price=entry_price quantity=quantity
    
    return new_level
end

"""
    mark_level_filled(
        grid::MartingaleGrid,
        level_number::Int,
        order_id::String,
        fill_price::Float64
    )

标记网格层级为已成交
"""
function mark_level_filled(
    grid::MartingaleGrid,
    level_number::Int,
    order_id::String,
    fill_price::Float64
)
    
    # 找到对应层级
    level_idx = findfirst(l -> l.level == level_number, grid.levels)
    
    if isnothing(level_idx)
        @error "Level not found" level=level_number
        return
    end
    
    # 更新层级状态
    level = grid.levels[level_idx]
    grid.levels[level_idx] = GridLevel(
        level.level,
        fill_price,  # 使用实际成交价
        level.quantity,
        true,  # 已成交
        order_id,
        now()
    )
    
    # 更新网格统计
    grid.total_quantity += level.quantity
    grid.average_entry = calculate_average_entry_price(grid.levels)
    grid.last_fill_time = now()
    
    @info "Grid level filled" level=level_number price=fill_price quantity=level.quantity avg_entry=grid.average_entry
end

"""
    update_grid_metrics(
        grid::MartingaleGrid,
        current_price::Float64,
        account_balance::Float64
    )

更新网格的统计指标
"""
function update_grid_metrics(
    grid::MartingaleGrid,
    current_price::Float64,
    account_balance::Float64
)
    
    # 更新未实现盈亏
    grid.unrealized_pnl = calculate_unrealized_pnl(
        grid.levels,
        current_price,
        grid.side
    )
    
    # 计算钱包敞口（假设使用的保证金）
    if grid.total_quantity > 0
        position_value = grid.total_quantity * grid.average_entry
        # 简化计算：不考虑杠杆的实际保证金占用
        margin_used = position_value / 10  # 假设10倍杠杆
        grid.wallet_exposure = margin_used / account_balance
    end
    
    @debug "Grid metrics updated" pnl=grid.unrealized_pnl exposure=round(grid.wallet_exposure*100, digits=1)
end

"""
    create_take_profit_orders(
        grid::MartingaleGrid,
        config::TakeProfitConfig
    )::Vector{GridLevel}

创建止盈订单
"""
function create_take_profit_orders(
    grid::MartingaleGrid,
    config::TakeProfitConfig
)::Vector{GridLevel}
    
    if grid.total_quantity == 0.0
        @warn "Cannot create TP orders: no position"
        return GridLevel[]
    end
    
    # 计算止盈层级
    tp_levels = calculate_take_profit_levels(
        grid.average_entry,
        grid.total_quantity,
        grid.side,
        config
    )
    
    # 转换为GridLevel
    tp_orders = GridLevel[]
    
    for (i, tp) in enumerate(tp_levels)
        push!(tp_orders, GridLevel(
            i,
            tp.price,
            tp.quantity,
            false,
            nothing,
            nothing
        ))
    end
    
    grid.take_profit_orders = tp_orders
    
    @info "Take profit orders created" num_orders=length(tp_orders)
    
    return tp_orders
end

# ============================================================================
# 网格状态检查
# ============================================================================

"""
    check_grid_health(
        grid::MartingaleGrid,
        current_price::Float64,
        config::RiskConfig
    )::NamedTuple

检查网格健康状态

返回：
- (is_healthy, warnings, should_close)
"""
function check_grid_health(
    grid::MartingaleGrid,
    current_price::Float64,
    config::RiskConfig
)::NamedTuple{(:is_healthy, :warnings, :should_close), Tuple{Bool, Vector{String}, Bool}}
    
    warnings = String[]
    should_close = false
    
    # 1. 检查持仓时间
    if !isnothing(grid.last_fill_time)
        hold_hours = Dates.value(now() - grid.last_fill_time) / (1000 * 3600)
        
        if hold_hours > config.max_hold_hours
            push!(warnings, "持仓时间过长 ($(round(hold_hours, digits=1))小时)")
            should_close = true
        end
    end
    
    # 2. 检查止损
    if grid.total_quantity > 0.0
        pnl_pct = grid.unrealized_pnl / (grid.average_entry * grid.total_quantity) * 100
        
        if pnl_pct < -config.stop_loss_pct
            push!(warnings, "触发止损 (亏损$(round(abs(pnl_pct), digits=1))%)")
            should_close = true
        end
    end
    
    # 3. 检查清算风险（如果有清算价）
    if grid.liquidation_price > 0.0
        liq_distance = calculate_liquidation_distance(
            grid.average_entry,
            grid.liquidation_price,
            grid.side
        ) * 100
        
        if liq_distance < config.liquidation_critical_distance
            push!(warnings, "清算风险极高 (距离$(round(liq_distance, digits=1))%)")
            should_close = true
        elseif liq_distance < config.liquidation_danger_distance
            push!(warnings, "清算风险较高 (距离$(round(liq_distance, digits=1))%)")
        elseif liq_distance < config.liquidation_warning_distance
            push!(warnings, "接近清算价 (距离$(round(liq_distance, digits=1))%)")
        end
    end
    
    # 4. 检查敞口
    if grid.wallet_exposure > 0.8
        push!(warnings, "钱包敞口过大 ($(round(grid.wallet_exposure*100, digits=1))%)")
    end
    
    is_healthy = isempty(warnings)
    
    return (
        is_healthy = is_healthy,
        warnings = warnings,
        should_close = should_close
    )
end

"""
    print_grid_status(grid::MartingaleGrid, current_price::Float64)

打印网格状态
"""
function print_grid_status(grid::MartingaleGrid, current_price::Float64)
    println("\n" * "="^70)
    println("网格状态 - $(grid.symbol) $(grid.side)")
    println("="^70)
    
    println("创建时间: $(grid.creation_time)")
    println("最后成交: $(grid.last_fill_time)")
    println()
    
    println("📊 持仓信息:")
    println("  总数量: $(round(grid.total_quantity, digits=4))")
    println("  平均入场价: \$$(round(grid.average_entry, digits=2))")
    println("  当前价格: \$$(round(current_price, digits=2))")
    println("  未实现盈亏: \$$(round(grid.unrealized_pnl, digits=2))")
    
    if grid.total_quantity > 0.0
        pnl_pct = grid.unrealized_pnl / (grid.average_entry * grid.total_quantity) * 100
        println("  盈亏比例: $(round(pnl_pct, digits=2))%")
    end
    println()
    
    println("📈 网格配置:")
    println("  当前间距: $(round(grid.current_spacing*100, digits=2))%")
    println("  马丁系数: $(grid.martingale_factor)")
    println("  最大层数: $(grid.max_levels)")
    println("  当前层数: $(length(grid.levels))")
    println("  已成交: $(count(l -> l.filled, grid.levels))")
    println()
    
    println("📋 网格层级:")
    println("  " * rpad("层级", 6) * rpad("价格", 12) * rpad("数量", 12) * "状态")
    println("  " * "-"^40)
    
    for level in grid.levels
        status = level.filled ? "✅ 已成交" : "⏸️  待成交"
        println("  " * 
                rpad(string(level.level), 6) *
                rpad("\$$(round(level.price, digits=2))", 12) *
                rpad(string(round(level.quantity, digits=4)), 12) *
                status)
    end
    
    if !isempty(grid.take_profit_orders)
        println()
        println("🎯 止盈订单:")
        println("  " * rpad("序号", 6) * rpad("价格", 12) * rpad("数量", 12) * "状态")
        println("  " * "-"^40)
        
        for (i, tp) in enumerate(grid.take_profit_orders)
            status = tp.filled ? "✅ 已成交" : "⏸️  待成交"
            println("  " *
                    rpad(string(i), 6) *
                    rpad("\$$(round(tp.price, digits=2))", 12) *
                    rpad(string(round(tp.quantity, digits=4)), 12) *
                    status)
        end
    end
    
    println("="^70)
end