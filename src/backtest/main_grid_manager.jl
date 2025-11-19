# src/backtest/main_grid_manager.jl

"""
主网格管理器

职责：
- 根据信号初始化网格
- 生成网格价格层级
- 检查价格触发
- 管理止盈订单
- 动态调整网格参数
"""

using Dates
using Logging

# ============================================================================
# 网格层级
# ============================================================================

"""
    GridLevel

网格层级
"""
mutable struct GridLevel
    level::Int                          # 层级编号
    price::Float64                      # 目标价格
    quantity::Float64                   # 数量
    filled::Bool                        # 是否已成交
    fill_time::Union{DateTime, Nothing} # 成交时间
    order_id::Union{String, Nothing}    # 订单ID
end

# ============================================================================
# 主网格
# ============================================================================

"""
    MainGrid

主网格（一个方向的完整马丁格尔网格）
"""
mutable struct MainGrid
    # 基本信息
    symbol::Symbol
    side::Symbol                        # :LONG 或 :SHORT
    
    # 入场信号
    entry_signal::Any                   # 原始信号
    entry_time::DateTime
    entry_price::Float64                # 首次入场价格
    
    # 网格配置
    grid_spacing::Float64               # 网格间距（百分比）
    ddown_factor::Float64               # 马丁格尔倍数
    max_levels::Int                     # 最大层数
    
    # 网格层级
    levels::Vector{GridLevel}
    
    # 止盈层级
    take_profit_levels::Vector{GridLevel}
    
    # 仓位统计
    total_quantity::Float64             # 总持仓量
    average_entry::Float64              # 平均入场价
    total_cost::Float64                 # 总成本
    
    # 风险指标
    unrealized_pnl::Float64             # 未实现盈亏
    max_drawdown::Float64               # 最大回撤
    
    # 状态
    active::Bool                        # 是否活跃
    allow_new_entries::Bool             # 是否允许新增网格
    
    # 时间追踪
    last_fill_time::Union{DateTime, Nothing}
    
    function MainGrid(symbol::Symbol, side::Symbol, signal, entry_price::Float64, entry_time::DateTime)
        new(
            symbol,
            side,
            signal,
            entry_time,
            entry_price,
            signal.grid_spacing,
            signal.ddown_factor,
            signal.max_levels,
            GridLevel[],
            GridLevel[],
            0.0,  # total_quantity
            0.0,  # average_entry
            0.0,  # total_cost
            0.0,  # unrealized_pnl
            0.0,  # max_drawdown
            true, # active
            true, # allow_new_entries
            nothing
        )
    end
end

# ============================================================================
# 主网格管理器
# ============================================================================

"""
    MainGridManager

管理所有主网格
"""
mutable struct MainGridManager
    # 配置
    config::Any
    
    # 活跃网格（按symbol索引）
    active_grids::Dict{Symbol, MainGrid}
    
    # 历史网格
    closed_grids::Vector{MainGrid}
    
    # 统计
    total_grids_created::Int
    total_grids_closed::Int
    
    function MainGridManager(config)
        new(
            config,
            Dict{Symbol, MainGrid}(),
            MainGrid[],
            0,
            0
        )
    end
end

# ============================================================================
# 网格初始化
# ============================================================================

"""
    initialize_grid!(mgr::MainGridManager, signal, current_price::Float64)

根据信号初始化网格
"""
function initialize_grid!(
    mgr::MainGridManager,
    signal,
    current_price::Float64
)
    
    symbol = signal.symbol
    
    # 检查是否已有活跃网格
    if haskey(mgr.active_grids, symbol)
        @warn "Grid already exists for $symbol, skipping"
        return nothing
    end
    
    # 确定方向
    side = signal.signal_type == :LONG_ENTRY ? :LONG : :SHORT
    
    # 创建网格
    grid = MainGrid(symbol, side, signal, current_price, signal.timestamp)
    
    # 生成网格层级
    generate_grid_levels!(grid, current_price)
    
    # 生成止盈层级
    generate_take_profit_levels!(grid, current_price)
    
    # 保存网格
    mgr.active_grids[symbol] = grid
    mgr.total_grids_created += 1
    
    @info "Grid initialized" symbol=symbol side=side entry_price=current_price levels=length(grid.levels) tp_levels=length(grid.take_profit_levels)
    
    return grid
end

"""
    generate_grid_levels!(grid::MainGrid, current_price::Float64)

生成网格价格层级
"""
function generate_grid_levels!(grid::MainGrid, current_price::Float64)
    
    base_quantity = 0.01  # 基础数量（可配置）
    
    for level in 1:grid.max_levels
        
        # 计算价格
        price_offset = grid.grid_spacing * level
        
        price = if grid.side == :LONG
            # 做多：往下设置买单
            current_price * (1.0 - price_offset)
        else
            # 做空：往上设置卖单
            current_price * (1.0 + price_offset)
        end
        
        # 计算数量（马丁格尔）
        quantity = base_quantity * (grid.ddown_factor ^ (level - 1))
        
        # 创建层级
        grid_level = GridLevel(
            level,
            price,
            quantity,
            false,
            nothing,
            nothing
        )
        
        push!(grid.levels, grid_level)
        
        @debug "Grid level created" level=level price=price quantity=quantity
    end
end

"""
    generate_take_profit_levels!(grid::MainGrid, current_price::Float64)

生成止盈层级
"""
function generate_take_profit_levels!(grid::MainGrid, current_price::Float64)
    
    # 止盈目标（可配置）
    tp_targets = [0.005, 0.01, 0.015]  # 0.5%, 1%, 1.5%
    tp_quantities = [0.4, 0.3, 0.3]    # 分批止盈比例
    
    for (i, target) in enumerate(tp_targets)
        
        price = if grid.side == :LONG
            # 做多：往上设置卖单
            current_price * (1.0 + target)
        else
            # 做空：往下设置买单
            current_price * (1.0 - target)
        end
        
        # 数量将在仓位建立后动态计算
        tp_level = GridLevel(
            i,
            price,
            0.0,  # 暂时为0，后续更新
            false,
            nothing,
            nothing
        )
        
        push!(grid.take_profit_levels, tp_level)
        
        @debug "TP level created" level=i price=price target_pct=target*100
    end
end

# ============================================================================
# 价格触发检查
# ============================================================================

"""
    check_price_triggers(mgr::MainGridManager, symbol::Symbol, current_price::Float64, timestamp::DateTime)::Vector

检查价格触发（返回GridTriggerEvent数组）
"""
function check_price_triggers(
    mgr::MainGridManager,
    symbol::Symbol,
    current_price::Float64,
    timestamp::DateTime
)::Vector
    
    triggers = []
    
    if !haskey(mgr.active_grids, symbol)
        return triggers
    end
    
    grid = mgr.active_grids[symbol]
    
    if !grid.active || !grid.allow_new_entries
        return triggers
    end
    
    # ✅ 只检查下一个未成交的层级
    for level in grid.levels
        
        if level.filled
            continue
        end
        
        is_triggered = if grid.side == :LONG
            # 做多：价格跌到或低于目标价
            current_price <= level.price
        else
            # 做空：价格涨到或高于目标价
            current_price >= level.price
        end
        
        if is_triggered
            # 生成GridTriggerEvent
            trigger = (
                timestamp = timestamp,
                symbol = symbol,
                grid_level = level.level,
                trigger_price = level.price,
                order_quantity = level.quantity,
                is_hedge = false
            )
            
            push!(triggers, trigger)
            
            @debug "Grid level triggered" symbol=symbol level=level.level price=level.price
            
            # ✅ 只触发一层就退出
            break
        end
    end
    
    return triggers
end

"""
    check_take_profit(mgr::MainGridManager, symbol::Symbol, current_price::Float64, timestamp::DateTime)

检查止盈触发
"""
function check_take_profit(
    mgr::MainGridManager,
    symbol::Symbol,
    current_price::Float64,
    timestamp::DateTime
)
    
    if !haskey(mgr.active_grids, symbol)
        return nothing
    end
    
    grid = mgr.active_grids[symbol]
    
    if grid.total_quantity == 0
        return nothing
    end
    
    # 检查止盈层级
    for tp_level in grid.take_profit_levels
        
        if tp_level.filled  # ✅ 已触发的跳过
            continue
        end
        
        is_triggered = if grid.side == :LONG
            current_price >= tp_level.price
        else
            current_price <= tp_level.price
        end
        
        if is_triggered
            
            # ✅ 立即标记为已触发，防止重复
            tp_level.filled = true
            tp_level.fill_time = timestamp
            
            # 计算止盈数量
            close_quantity = grid.total_quantity * 0.4
            
            # 计算盈利
            profit = if grid.side == :LONG
                (tp_level.price - grid.average_entry) * close_quantity
            else
                (grid.average_entry - tp_level.price) * close_quantity
            end
            
            profit_pct = (profit / (grid.average_entry * close_quantity)) * 100
            
            @info "Take profit triggered" symbol=symbol level=tp_level.level price=tp_level.price profit=profit
            
            return (
                timestamp = timestamp,
                symbol = symbol,
                tp_level = tp_level.level,
                close_quantity = close_quantity,
                tp_price = tp_level.price,
                profit_amount = profit,
                profit_pct = profit_pct
            )
        end
    end
    
    return nothing
end

# ============================================================================
# 网格成交处理
# ============================================================================

"""
    on_grid_fill!(mgr::MainGridManager, fill)

处理网格成交
"""
function on_grid_fill!(mgr::MainGridManager, fill)
    
    symbol = fill.symbol
    
    if !haskey(mgr.active_grids, symbol)
        @warn "No active grid for $symbol"
        return
    end
    
    grid = mgr.active_grids[symbol]
    
    # 查找对应层级
    grid_level_num = get(fill, :grid_level, nothing)
    
    if isnothing(grid_level_num)
        @warn "Fill event missing grid_level"
        return
    end
    
    # 更新层级状态
    for level in grid.levels
        if level.level == grid_level_num
            level.filled = true
            level.fill_time = fill.timestamp
            level.order_id = fill.order_id
            
            @debug "Grid level filled" symbol=symbol level=level.level price=fill.fill_price quantity=fill.quantity
            break
        end
    end
    
    # 更新仓位统计
    update_grid_position!(grid, fill)
    
    # 更新止盈订单数量
    update_take_profit_quantities!(grid)
    
    grid.last_fill_time = fill.timestamp
end

"""
    update_grid_position!(grid::MainGrid, fill)

更新网格仓位统计
"""
function update_grid_position!(grid::MainGrid, fill)
    
    # ✅ 正确计算：手续费不计入均价
    position_value = fill.quantity * fill.fill_price
    
    # 加权平均计算新的平均入场价
    old_total_value = grid.total_quantity * grid.average_entry
    new_total_value = old_total_value + position_value
    new_quantity = grid.total_quantity + fill.quantity
    
    if new_quantity > 0
        grid.average_entry = new_total_value / new_quantity
    end
    
    # 更新持仓数量
    grid.total_quantity = new_quantity
    
    # 总成本包含手续费（用于计算总盈亏）
    grid.total_cost += (position_value + fill.commission)
    
    @debug "Grid position updated" symbol=grid.symbol total_qty=grid.total_quantity avg_entry=grid.average_entry total_cost=grid.total_cost
end

"""
    update_take_profit_quantities!(grid::MainGrid)

更新止盈订单数量
"""
function update_take_profit_quantities!(grid::MainGrid)
    
    # 按比例分配止盈数量
    tp_ratios = [0.4, 0.3, 0.3]
    
    for (i, tp_level) in enumerate(grid.take_profit_levels)
        if !tp_level.filled
            tp_level.quantity = grid.total_quantity * tp_ratios[i]
        end
    end
end

# ============================================================================
# 盈亏计算
# ============================================================================

"""
    update_grid_pnl!(grid::MainGrid, current_price::Float64)

更新网格盈亏
"""
function update_grid_pnl!(grid::MainGrid, current_price::Float64)
    
    if grid.total_quantity == 0
        grid.unrealized_pnl = 0.0
        return
    end
    
    # 计算未实现盈亏
    if grid.side == :LONG
        grid.unrealized_pnl = (current_price - grid.average_entry) * grid.total_quantity
    else
        grid.unrealized_pnl = (grid.average_entry - current_price) * grid.total_quantity
    end
    
    # 更新最大回撤
    if grid.unrealized_pnl < grid.max_drawdown
        grid.max_drawdown = grid.unrealized_pnl
    end
end

# ============================================================================
# 网格查询
# ============================================================================

"""
    has_active_grid(mgr::MainGridManager, symbol::Symbol)::Bool

检查是否有活跃网格
"""
function has_active_grid(mgr::MainGridManager, symbol::Symbol)::Bool
    return haskey(mgr.active_grids, symbol) && mgr.active_grids[symbol].active
end

"""
    get_active_grid(mgr::MainGridManager, symbol::Symbol)::Union{MainGrid, Nothing}

获取活跃网格
"""
function get_active_grid(mgr::MainGridManager, symbol::Symbol)::Union{MainGrid, Nothing}
    return get(mgr.active_grids, symbol, nothing)
end

"""
    get_grid_side(mgr::MainGridManager, symbol::Symbol)::Union{Symbol, Nothing}

获取网格方向
"""
function get_grid_side(mgr::MainGridManager, symbol::Symbol)::Union{Symbol, Nothing}
    grid = get_active_grid(mgr, symbol)
    return isnothing(grid) ? nothing : grid.side
end

# ============================================================================
# 网格关闭
# ============================================================================

"""
    close_grid!(mgr::MainGridManager, symbol::Symbol)

关闭网格
"""
function close_grid!(mgr::MainGridManager, symbol::Symbol)
    
    if !haskey(mgr.active_grids, symbol)
        return
    end
    
    grid = mgr.active_grids[symbol]
    grid.active = false
    
    # 移到历史
    push!(mgr.closed_grids, grid)
    delete!(mgr.active_grids, symbol)
    
    mgr.total_grids_closed += 1
    
    @info "Grid closed" symbol=symbol final_pnl=grid.unrealized_pnl max_drawdown=grid.max_drawdown
end

# ============================================================================
# 统计信息
# ============================================================================

"""
    get_grid_stats(grid::MainGrid)::Dict

获取单个网格统计
"""
function get_grid_stats(grid::MainGrid)::Dict
    
    filled_levels = count(l -> l.filled, grid.levels)
    
    return Dict(
        "symbol" => grid.symbol,
        "side" => grid.side,
        "entry_time" => grid.entry_time,
        "entry_price" => grid.entry_price,
        "average_entry" => grid.average_entry,
        "total_quantity" => grid.total_quantity,
        "total_cost" => grid.total_cost,
        "unrealized_pnl" => grid.unrealized_pnl,
        "max_drawdown" => grid.max_drawdown,
        "filled_levels" => filled_levels,
        "total_levels" => length(grid.levels),
        "active" => grid.active
    )
end

"""
    print_grid_status(grid::MainGrid, current_price::Float64)

打印网格状态
"""
function print_grid_status(grid::MainGrid, current_price::Float64)
    
    println("\n" * "="^70)
    println("网格状态: $(grid.symbol) $(grid.side)")
    println("="^70)
    
    println("\n基本信息:")
    println("  入场时间: $(grid.entry_time)")
    println("  入场价格: \$$(round(grid.entry_price, digits=2))")
    println("  当前价格: \$$(round(current_price, digits=2))")
    println("  平均成本: \$$(round(grid.average_entry, digits=2))")
    
    println("\n仓位信息:")
    println("  总持仓: $(round(grid.total_quantity, digits=4))")
    println("  总成本: \$$(round(grid.total_cost, digits=2))")
    
    pnl_indicator = grid.unrealized_pnl >= 0 ? "🟢" : "🔴"
    pnl_pct = grid.total_quantity > 0 ? (grid.unrealized_pnl / grid.total_cost) * 100 : 0.0
    
    println("\n盈亏:")
    println("  浮盈: $pnl_indicator \$$(round(grid.unrealized_pnl, digits=2)) ($(round(pnl_pct, digits=2))%)")
    println("  最大回撤: \$$(round(grid.max_drawdown, digits=2))")
    
    filled_count = count(l -> l.filled, grid.levels)
    
    println("\n网格层级: ($filled_count/$(length(grid.levels)) 已成交)")
    for level in grid.levels
        status = level.filled ? "✅" : "⏳"
        println("  $status Level $(level.level): \$$(round(level.price, digits=2)) x $(round(level.quantity, digits=4))")
    end
    
    println("\n止盈层级:")
    for tp in grid.take_profit_levels
        status = tp.filled ? "✅" : "⏳"
        println("  $status TP $(tp.level): \$$(round(tp.price, digits=2)) x $(round(tp.quantity, digits=4))")
    end
    
    println("="^70)
end