# src/backtest/hedge_grid_manager.jl

"""
对冲网格管理器

职责：
- 检测被套条件
- 初始化对冲网格
- 管理对冲仓位
- 利润回收（用于减少主仓位成本）
- 动态调整对冲参数
"""

using Dates
using Logging

# 复用GridLevel定义
include("main_grid_manager.jl")

# ============================================================================
# 对冲网格
# ============================================================================

"""
    HedgeGrid

对冲网格（与主仓位相反方向的网格）
"""
mutable struct HedgeGrid
    # 关联的主网格symbol
    parent_symbol::Symbol
    
    # 激活信息
    activation_reason::Symbol           # :DRAWDOWN, :TREND_REVERSAL, :MANUAL
    activation_time::DateTime
    activation_price::Float64
    
    # 网格配置
    side::Symbol                        # 与主仓位相反
    grid_spacing::Float64               # 对冲网格间距
    max_levels::Int                     # 最大层数
    
    # 对冲参数
    initial_size_ratio::Float64         # 初始对冲仓位比例（相对主仓位）
    max_exposure_ratio::Float64         # 最大对冲敞口比例
    
    # 网格层级
    levels::Vector{GridLevel}
    
    # 仓位统计
    total_quantity::Float64
    average_entry::Float64
    total_cost::Float64
    
    # 盈亏
    unrealized_pnl::Float64
    realized_pnl::Float64               # 已实现利润（用于回收）
    
    # 利润回收
    recycling_enabled::Bool
    recycling_ratio::Float64            # 利润回收比例
    total_recycled::Float64             # 已回收总额
    
    # 状态
    active::Bool
    
    # 时间追踪
    last_fill_time::Union{DateTime, Nothing}
    
    function HedgeGrid(
        parent_symbol::Symbol,
        parent_side::Symbol,
        activation_reason::Symbol,
        activation_price::Float64,
        activation_time::DateTime
    )
        # 对冲方向与主仓位相反
        hedge_side = parent_side == :LONG ? :SHORT : :LONG
        
        new(
            parent_symbol,
            activation_reason,
            activation_time,
            activation_price,
            hedge_side,
            0.003,  # 对冲间距（比主网格小）
            4,      # 对冲层数（比主网格少）
            0.5,    # 初始对冲50%
            1.0,    # 最大对冲100%
            GridLevel[],
            0.0,    # total_quantity
            0.0,    # average_entry
            0.0,    # total_cost
            0.0,    # unrealized_pnl
            0.0,    # realized_pnl
            true,   # recycling_enabled
            0.7,    # 70%利润用于回收
            0.0,    # total_recycled
            true,   # active
            nothing
        )
    end
end

# ============================================================================
# 对冲网格管理器
# ============================================================================

"""
    HedgeGridManager

管理所有对冲网格
"""
mutable struct HedgeGridManager
    # 配置
    config::Any
    
    # 活跃对冲网格
    active_hedges::Dict{Symbol, HedgeGrid}
    
    # 历史对冲网格
    closed_hedges::Vector{HedgeGrid}
    
    # 对冲触发阈值
    drawdown_threshold::Float64         # 回撤阈值（触发对冲）
    time_threshold::Period              # 时间阈值（被套时间）
    
    # 统计
    total_hedges_created::Int
    total_hedges_closed::Int
    total_profit_recycled::Float64
    
    function HedgeGridManager(config)
        new(
            config,
            Dict{Symbol, HedgeGrid}(),
            HedgeGrid[],
            -0.05,      # -5%回撤触发对冲
            Hour(2),    # 被套2小时触发对冲
            0,
            0,
            0.0
        )
    end
end

# ============================================================================
# 对冲触发检查
# ============================================================================

"""
    should_activate_hedge(
        mgr::HedgeGridManager,
        position,
        current_price::Float64,
        timestamp::DateTime,
        config
    )::Union{Nothing, NamedTuple}

检查是否应该激活对冲
"""
function should_activate_hedge(
    mgr::HedgeGridManager,
    position,
    current_price::Float64,
    timestamp::DateTime,
    config
)::Union{Nothing, NamedTuple}
    
    symbol = position.symbol
    
    # 如果已有对冲，不重复创建
    if haskey(mgr.active_hedges, symbol)
        return nothing
    end
    
    # 计算未实现盈亏比例
    unrealized_pnl_pct = position.unrealized_pnl / position.total_cost
    
    # 检查回撤触发条件
    if unrealized_pnl_pct <= mgr.drawdown_threshold
        
        @warn "Hedge triggered by drawdown" symbol=symbol pnl_pct=unrealized_pnl_pct*100
        
        return (
            timestamp = timestamp,
            symbol = symbol,
            reason = :DRAWDOWN,
            main_position_size = position.size,
            main_avg_entry = position.entry_price,
            current_price = current_price,
            unrealized_pnl = position.unrealized_pnl,
            unrealized_pnl_pct = unrealized_pnl_pct * 100,
            hedge_ratio = 0.5,
            hedge_grid_spacing = 0.003
        )
    end
    
    # 检查时间触发条件
    if !isnothing(position.open_time)
        time_held = timestamp - position.open_time
        
        if time_held >= mgr.time_threshold && unrealized_pnl_pct < 0
            
            @warn "Hedge triggered by time" symbol=symbol time_held=time_held pnl_pct=unrealized_pnl_pct*100
            
            return (
                timestamp = timestamp,
                symbol = symbol,
                reason = :TIME_LIMIT,
                main_position_size = position.size,
                main_avg_entry = position.entry_price,
                current_price = current_price,
                unrealized_pnl = position.unrealized_pnl,
                unrealized_pnl_pct = unrealized_pnl_pct * 100,
                hedge_ratio = 0.3,  # 时间触发用较小的对冲比例
                hedge_grid_spacing = 0.003
            )
        end
    end
    
    return nothing
end

# ============================================================================
# 对冲网格初始化
# ============================================================================

"""
    initialize_hedge_grid!(
        mgr::HedgeGridManager,
        trigger,
        current_price::Float64
    )

初始化对冲网格
"""
function initialize_hedge_grid!(
    mgr::HedgeGridManager,
    trigger,
    current_price::Float64
)
    
    symbol = trigger.symbol
    
    # 检查是否已有对冲
    if haskey(mgr.active_hedges, symbol)
        @warn "Hedge already exists for $symbol"
        return nothing
    end
    
    # 确定主仓位方向（需要从trigger推断）
    # 假设trigger包含main_position信息
    parent_side = :LONG  # 这里需要从实际主仓位获取
    
    # 创建对冲网格
    hedge = HedgeGrid(
        symbol,
        parent_side,
        trigger.reason,
        current_price,
        trigger.timestamp
    )
    
    # 设置对冲比例
    hedge.initial_size_ratio = trigger.hedge_ratio
    
    # 生成对冲网格层级
    generate_hedge_levels!(hedge, current_price, trigger.main_position_size)
    
    # 保存对冲网格
    mgr.active_hedges[symbol] = hedge
    mgr.total_hedges_created += 1
    
    @info "Hedge grid initialized" symbol=symbol side=hedge.side reason=trigger.reason levels=length(hedge.levels)
    
    return hedge
end

"""
    generate_hedge_levels!(hedge::HedgeGrid, current_price::Float64, main_position_size::Float64)

生成对冲网格层级
"""
function generate_hedge_levels!(
    hedge::HedgeGrid,
    current_price::Float64,
    main_position_size::Float64
)
    
    # 基础对冲数量（主仓位的一定比例）
    base_quantity = main_position_size * hedge.initial_size_ratio / hedge.max_levels
    
    for level in 1:hedge.max_levels
        
        # 对冲网格价格
        price_offset = hedge.grid_spacing * level
        
        price = if hedge.side == :LONG
            # 对冲做多：往下设置买单（价格继续下跌时加仓对冲）
            current_price * (1.0 - price_offset)
        else
            # 对冲做空：往上设置卖单（价格继续上涨时加仓对冲）
            current_price * (1.0 + price_offset)
        end
        
        # 对冲数量（均匀分布，不使用马丁格尔）
        quantity = base_quantity
        
        grid_level = GridLevel(
            level,
            price,
            quantity,
            false,
            nothing,
            nothing
        )
        
        push!(hedge.levels, grid_level)
        
        @debug "Hedge level created" level=level price=price quantity=quantity
    end
end

# ============================================================================
# 对冲价格触发
# ============================================================================

"""
    check_hedge_triggers(
        mgr::HedgeGridManager,
        symbol::Symbol,
        current_price::Float64,
        timestamp::DateTime
    )::Vector

检查对冲网格触发
"""
function check_hedge_triggers(
    mgr::HedgeGridManager,
    symbol::Symbol,
    current_price::Float64,
    timestamp::DateTime
)::Vector
    
    triggers = []
    
    if !haskey(mgr.active_hedges, symbol)
        return triggers
    end
    
    hedge = mgr.active_hedges[symbol]
    
    if !hedge.active
        return triggers
    end
    
    # 检查对冲层级触发
    for level in hedge.levels
        
        if level.filled
            continue
        end
        
        is_triggered = if hedge.side == :LONG
            current_price <= level.price
        else
            current_price >= level.price
        end
        
        if is_triggered
            trigger = (
                timestamp = timestamp,
                symbol = symbol,
                grid_level = level.level,
                trigger_price = level.price,
                order_quantity = level.quantity,
                is_hedge = true  # ✅ 标记为对冲订单
            )
            
            push!(triggers, trigger)
            
            @debug "Hedge level triggered" symbol=symbol level=level.level price=level.price
        end
    end
    
    return triggers
end

# ============================================================================
# 对冲成交处理
# ============================================================================

"""
    on_hedge_fill!(mgr::HedgeGridManager, fill)

处理对冲成交
"""
function on_hedge_fill!(mgr::HedgeGridManager, fill)
    
    symbol = fill.symbol
    
    if !haskey(mgr.active_hedges, symbol)
        @warn "No active hedge for $symbol"
        return
    end
    
    hedge = mgr.active_hedges[symbol]
    
    # 查找对应层级
    grid_level_num = get(fill, :grid_level, nothing)
    
    if isnothing(grid_level_num)
        @warn "Fill event missing grid_level"
        return
    end
    
    # 更新层级状态
    for level in hedge.levels
        if level.level == grid_level_num
            level.filled = true
            level.fill_time = fill.timestamp
            level.order_id = fill.order_id
            
            @debug "Hedge level filled" symbol=symbol level=level.level price=fill.fill_price
            break
        end
    end
    
    # 更新对冲仓位
    update_hedge_position!(hedge, fill)
    
    hedge.last_fill_time = fill.timestamp
end

"""
    update_hedge_position!(hedge::HedgeGrid, fill)

更新对冲仓位
"""
function update_hedge_position!(hedge::HedgeGrid, fill)
    
    # ✅ 正确计算：手续费不计入均价
    position_value = fill.quantity * fill.fill_price
    
    # 加权平均计算新的平均入场价
    old_total_value = hedge.total_quantity * hedge.average_entry
    new_total_value = old_total_value + position_value
    new_quantity = hedge.total_quantity + fill.quantity
    
    if new_quantity > 0
        hedge.average_entry = new_total_value / new_quantity
    end
    
    # 更新持仓数量
    hedge.total_quantity = new_quantity
    
    # 总成本包含手续费
    hedge.total_cost += (position_value + fill.commission)
    
    @debug "Hedge position updated" symbol=hedge.parent_symbol total_qty=hedge.total_quantity avg_entry=hedge.average_entry total_cost=hedge.total_cost
end

# ============================================================================
# 对冲盈亏和利润回收
# ============================================================================

"""
    update_hedge_pnl!(hedge::HedgeGrid, current_price::Float64)

更新对冲盈亏
"""
function update_hedge_pnl!(hedge::HedgeGrid, current_price::Float64)
    
    if hedge.total_quantity == 0
        hedge.unrealized_pnl = 0.0
        return
    end
    
    if hedge.side == :LONG
        hedge.unrealized_pnl = (current_price - hedge.average_entry) * hedge.total_quantity
    else
        hedge.unrealized_pnl = (hedge.average_entry - current_price) * hedge.total_quantity
    end
end

"""
    check_hedge_profit_taking(
        mgr::HedgeGridManager,
        hedge::HedgeGrid,
        current_price::Float64
    )::Union{Nothing, NamedTuple}

检查对冲止盈（利润回收）
"""
function check_hedge_profit_taking(
    mgr::HedgeGridManager,
    hedge::HedgeGrid,
    current_price::Float64
)::Union{Nothing, NamedTuple}
    
    if hedge.total_quantity == 0
        return nothing
    end
    
    # 计算盈利比例
    profit_pct = hedge.unrealized_pnl / hedge.total_cost
    
    # 对冲盈利目标（相对保守）
    profit_target = 0.02  # 2%
    
    if profit_pct >= profit_target
        
        # 计算止盈数量（部分平仓）
        close_quantity = hedge.total_quantity * 0.5  # 平掉50%
        
        # 计算利润
        profit = hedge.unrealized_pnl * 0.5
        
        # 计算回收金额
        recycle_amount = profit * hedge.recycling_ratio
        
        @info "Hedge profit taking" symbol=hedge.parent_symbol profit=profit recycle=recycle_amount
        
        return (
            timestamp = now(),
            symbol = hedge.parent_symbol,
            close_quantity = close_quantity,
            close_price = current_price,
            profit = profit,
            recycle_amount = recycle_amount
        )
    end
    
    return nothing
end

"""
    recycle_hedge_profit!(mgr::HedgeGridManager, symbol::Symbol, amount::Float64)

回收对冲利润（用于减少主仓位成本）
"""
function recycle_hedge_profit!(mgr::HedgeGridManager, symbol::Symbol, amount::Float64)
    
    if !haskey(mgr.active_hedges, symbol)
        return
    end
    
    hedge = mgr.active_hedges[symbol]
    
    hedge.total_recycled += amount
    mgr.total_profit_recycled += amount
    
    @info "Profit recycled" symbol=symbol amount=amount total_recycled=hedge.total_recycled
end

# ============================================================================
# 对冲网格关闭
# ============================================================================

"""
    close_hedge!(mgr::HedgeGridManager, symbol::Symbol)

关闭对冲网格
"""
function close_hedge!(mgr::HedgeGridManager, symbol::Symbol)
    
    if !haskey(mgr.active_hedges, symbol)
        return
    end
    
    hedge = mgr.active_hedges[symbol]
    hedge.active = false
    
    # 移到历史
    push!(mgr.closed_hedges, hedge)
    delete!(mgr.active_hedges, symbol)
    
    mgr.total_hedges_closed += 1
    
    @info "Hedge closed" symbol=symbol total_recycled=hedge.total_recycled realized_pnl=hedge.realized_pnl
end

# ============================================================================
# 查询接口
# ============================================================================

"""
    has_active_hedge(mgr::HedgeGridManager, symbol::Symbol)::Bool

检查是否有活跃对冲
"""
function has_active_hedge(mgr::HedgeGridManager, symbol::Symbol)::Bool
    return haskey(mgr.active_hedges, symbol) && mgr.active_hedges[symbol].active
end

"""
    get_active_hedge(mgr::HedgeGridManager, symbol::Symbol)::Union{HedgeGrid, Nothing}

获取活跃对冲
"""
function get_active_hedge(mgr::HedgeGridManager, symbol::Symbol)::Union{HedgeGrid, Nothing}
    return get(mgr.active_hedges, symbol, nothing)
end

# ============================================================================
# 统计信息
# ============================================================================

"""
    print_hedge_status(hedge::HedgeGrid, current_price::Float64)

打印对冲状态
"""
function print_hedge_status(hedge::HedgeGrid, current_price::Float64)
    
    println("\n" * "="^70)
    println("对冲网格状态: $(hedge.parent_symbol)")
    println("="^70)
    
    println("\n激活信息:")
    println("  原因: $(hedge.activation_reason)")
    println("  时间: $(hedge.activation_time)")
    println("  激活价: \$$(round(hedge.activation_price, digits=2))")
    
    println("\n对冲方向: $(hedge.side)")
    println("  当前价格: \$$(round(current_price, digits=2))")
    println("  平均成本: \$$(round(hedge.average_entry, digits=2))")
    
    println("\n仓位信息:")
    println("  总持仓: $(round(hedge.total_quantity, digits=4))")
    println("  总成本: \$$(round(hedge.total_cost, digits=2))")
    
    pnl_indicator = hedge.unrealized_pnl >= 0 ? "🟢" : "🔴"
    pnl_pct = hedge.total_quantity > 0 ? (hedge.unrealized_pnl / hedge.total_cost) * 100 : 0.0
    
    println("\n盈亏:")
    println("  浮盈: $pnl_indicator \$$(round(hedge.unrealized_pnl, digits=2)) ($(round(pnl_pct, digits=2))%)")
    println("  已回收: \$$(round(hedge.total_recycled, digits=2))")
    
    filled_count = count(l -> l.filled, hedge.levels)
    
    println("\n对冲层级: ($filled_count/$(length(hedge.levels)) 已成交)")
    for level in hedge.levels
        status = level.filled ? "✅" : "⏳"
        println("  $status Level $(level.level): \$$(round(level.price, digits=2)) x $(round(level.quantity, digits=4))")
    end
    
    println("="^70)
end