# src/execution/position_manager.jl

"""
持仓管理器

职责：
- 跟踪所有持仓
- 计算盈亏
- 区分主仓位和对冲仓位
- 提供持仓查询接口
"""

using Dates
using Logging

# 不要include events.jl，因为已经在主模块加载了
# include("../core/events.jl")  # ❌ 删除这行

# ============================================================================
# 持仓数据结构
# ============================================================================

"""
    PositionRecord

单个持仓记录（重命名以避免与PassivbotJL.Position冲突）
"""
mutable struct PositionRecord
    symbol::Symbol
    side::Symbol              # :BUY 或 :SELL
    size::Float64             # 持仓数量
    entry_price::Float64      # 平均入场价
    total_cost::Float64       # 总成本（含手续费）
    
    # 盈亏
    unrealized_pnl::Float64   # 未实现盈亏
    realized_pnl::Float64     # 已实现盈亏
    total_fees::Float64       # 总手续费
    
    # 时间
    open_time::DateTime
    last_update::DateTime
    
    # 标记
    is_hedge::Bool            # 是否为对冲仓位
    
    # 统计
    fills_count::Int          # 成交次数
    
    function PositionRecord(
        symbol::Symbol,
        side::Symbol,
        size::Float64,
        entry_price::Float64,
        fee::Float64,
        timestamp::DateTime;
        is_hedge::Bool=false
    )
        cost = size * entry_price + fee
        
        new(
            symbol,
            side,
            size,
            entry_price,
            cost,
            0.0,        # unrealized_pnl
            0.0,        # realized_pnl
            fee,        # total_fees
            timestamp,  # open_time
            timestamp,  # last_update
            is_hedge,
            1           # fills_count
        )
    end
end

# ============================================================================
# 持仓管理器
# ============================================================================

"""
    PositionManager

管理所有持仓
"""
mutable struct PositionManager
    # 主仓位（按symbol索引）
    main_positions::Dict{Symbol, PositionRecord}
    
    # 对冲仓位
    hedge_positions::Dict{Symbol, PositionRecord}
    
    # 当前价格（用于计算浮盈）
    current_prices::Dict{Symbol, Float64}
    
    # 历史持仓（已平仓）
    closed_positions::Vector{PositionRecord}
    
    # 统计
    total_realized_pnl::Float64
    total_fees::Float64
    total_trades::Int
    winning_trades::Int
    losing_trades::Int
    
    function PositionManager()
        new(
            Dict{Symbol, PositionRecord}(),
            Dict{Symbol, PositionRecord}(),
            Dict{Symbol, Float64}(),
            PositionRecord[],
            0.0,  # total_realized_pnl
            0.0,  # total_fees
            0,    # total_trades
            0,    # winning_trades
            0     # losing_trades
        )
    end
end

# ============================================================================
# 价格更新
# ============================================================================

"""
    update_price!(pm::PositionManager, symbol::Symbol, price::Float64, timestamp::DateTime)

更新价格并重新计算浮盈
"""
function update_price!(pm::PositionManager, symbol::Symbol, price::Float64, timestamp::DateTime)
    
    pm.current_prices[symbol] = price
    
    # 更新主仓位浮盈
    if haskey(pm.main_positions, symbol)
        update_unrealized_pnl!(pm.main_positions[symbol], price, timestamp)
    end
    
    # 更新对冲仓位浮盈
    if haskey(pm.hedge_positions, symbol)
        update_unrealized_pnl!(pm.hedge_positions[symbol], price, timestamp)
    end
end

"""
    update_unrealized_pnl!(position::PositionRecord, current_price::Float64, timestamp::DateTime)

更新单个持仓的浮盈
"""
function update_unrealized_pnl!(position::PositionRecord, current_price::Float64, timestamp::DateTime)
    
    if position.size == 0
        position.unrealized_pnl = 0.0
        return
    end
    
    # 计算浮盈
    if position.side == :BUY
        # 做多：当前价 - 入场价
        position.unrealized_pnl = (current_price - position.entry_price) * position.size
    else
        # 做空：入场价 - 当前价
        position.unrealized_pnl = (position.entry_price - current_price) * position.size
    end
    
    position.last_update = timestamp
end

# ============================================================================
# 成交处理
# ============================================================================

"""
    on_fill!(pm::PositionManager, fill::FillEvent)

处理成交事件
"""
function on_fill!(pm::PositionManager, fill)  # 不指定类型，避免FillEvent未定义
    
    # 选择仓位字典
    positions = fill.is_hedge ? pm.hedge_positions : pm.main_positions
    
    # 获取或创建持仓
    if haskey(positions, fill.symbol)
        position = positions[fill.symbol]
        
        # 检查是否为平仓
        if is_closing_fill(position, fill)
            close_position!(pm, position, fill)
        else
            add_to_position!(position, fill)
        end
    else
        # 新建持仓
        position = PositionRecord(
            fill.symbol,
            fill.side,
            fill.quantity,
            fill.fill_price,
            fill.commission,
            fill.timestamp,
            is_hedge=fill.is_hedge
        )
        
        positions[fill.symbol] = position
        
        @debug "Position opened" symbol=fill.symbol side=fill.side size=fill.quantity price=fill.fill_price is_hedge=fill.is_hedge
    end
    
    # 更新当前价格
    pm.current_prices[fill.symbol] = fill.fill_price
    
    # 更新浮盈
    update_unrealized_pnl!(position, fill.fill_price, fill.timestamp)
end

"""
    is_closing_fill(position::PositionRecord, fill)::Bool

判断是否为平仓成交
"""
function is_closing_fill(position::PositionRecord, fill)::Bool
    # 方向相反即为平仓
    return position.side != fill.side
end

"""
    add_to_position!(position::PositionRecord, fill)

加仓
"""
function add_to_position!(position::PositionRecord, fill)
    
    @debug "Adding to position" symbol=fill.symbol add_qty=fill.quantity current_size=position.size current_avg=position.entry_price
    
    # 加权平均计算新的平均入场价
    old_value = position.size * position.entry_price
    new_value = fill.quantity * fill.fill_price
    total_value = old_value + new_value
    
    new_size = position.size + fill.quantity
    
    if new_size > 0
        position.entry_price = total_value / new_size
    end
    
    # 更新持仓数量
    position.size = new_size
    
    # 更新总成本（包含手续费）
    position.total_cost += (new_value + fill.commission)
    position.total_fees += fill.commission
    position.last_update = fill.timestamp
    
    @debug "Position updated after add" symbol=fill.symbol new_size=position.size new_avg_price=position.entry_price
end

"""
    close_position!(pm::PositionManager, position::PositionRecord, fill)

平仓（全部或部分）
"""
function close_position!(pm::PositionManager, position::PositionRecord, fill)
    
    @info "Closing position" symbol=fill.symbol close_qty=fill.quantity current_size=position.size entry_price=position.entry_price
    
    # 计算实际平仓数量
    close_quantity = min(fill.quantity, position.size)
    
    # 计算已实现盈亏
    if position.side == :BUY
        # 平多仓：(卖出价 - 平均成本) * 数量
        pnl = (fill.fill_price - position.entry_price) * close_quantity
    else
        # 平空仓：(平均成本 - 买入价) * 数量
        pnl = (position.entry_price - fill.fill_price) * close_quantity
    end
    
    # 扣除手续费
    pnl -= fill.commission
    
    # ✅ 关键修复：减少持仓，但平均价保持不变
    position.size -= close_quantity
    position.realized_pnl += pnl
    position.total_fees += fill.commission
    position.last_update = fill.timestamp
    
    # 更新管理器统计
    pm.total_realized_pnl += pnl
    pm.total_fees += fill.commission
    pm.total_trades += 1
    
    if pnl > 0
        pm.winning_trades += 1
    elseif pnl < 0
        pm.losing_trades += 1
    end
    
    @info "Position closed" symbol=fill.symbol closed_qty=close_quantity pnl=round(pnl, digits=2) remaining_size=position.size avg_price_unchanged=position.entry_price
    
    # 如果完全平仓，删除持仓记录
    if position.size <= 0.0001  # 浮点数精度容差
        positions = fill.is_hedge ? pm.hedge_positions : pm.main_positions
        
        # 移到历史
        push!(pm.closed_positions, position)
        delete!(positions, fill.symbol)
        
        @info "Position fully closed" symbol=fill.symbol total_realized_pnl=round(position.realized_pnl, digits=2) total_fees=round(position.total_fees, digits=2)
    end
end

# ============================================================================
# 查询接口（重命名以避免冲突）
# ============================================================================

"""
    get_position_record(pm::PositionManager, symbol::Symbol, is_hedge::Bool=false)::Union{PositionRecord, Nothing}

获取持仓记录
"""
function get_position_record(pm::PositionManager, symbol::Symbol, is_hedge::Bool=false)::Union{PositionRecord, Nothing}
    
    positions = is_hedge ? pm.hedge_positions : pm.main_positions
    
    return get(positions, symbol, nothing)
end

"""
    has_position(pm::PositionManager, symbol::Symbol, is_hedge::Bool=false)::Bool

检查是否有持仓
"""
function has_position(pm::PositionManager, symbol::Symbol, is_hedge::Bool=false)::Bool
    
    positions = is_hedge ? pm.hedge_positions : pm.main_positions
    
    return haskey(positions, symbol) && positions[symbol].size > 0
end

"""
    get_all_positions(pm::PositionManager)::Vector{PositionRecord}

获取所有活跃持仓
"""
function get_all_positions(pm::PositionManager)::Vector{PositionRecord}
    
    all_positions = PositionRecord[]
    
    append!(all_positions, values(pm.main_positions))
    append!(all_positions, values(pm.hedge_positions))
    
    return all_positions
end

"""
    get_total_exposure(pm::PositionManager)::Float64

获取总敞口（所有持仓的名义价值）
"""
function get_total_exposure(pm::PositionManager)::Float64
    
    total = 0.0
    
    for position in get_all_positions(pm)
        current_price = get(pm.current_prices, position.symbol, position.entry_price)
        total += position.size * current_price
    end
    
    return total
end

"""
    get_total_unrealized_pnl(pm::PositionManager)::Float64

获取总浮盈
"""
function get_total_unrealized_pnl(pm::PositionManager)::Float64
    
    total = 0.0
    
    for position in get_all_positions(pm)
        total += position.unrealized_pnl
    end
    
    return total
end

"""
    get_position_summary(pm::PositionManager)::Dict

获取持仓摘要
"""
function get_position_summary(pm::PositionManager)::Dict
    
    main_count = length(pm.main_positions)
    hedge_count = length(pm.hedge_positions)
    
    total_unrealized = get_total_unrealized_pnl(pm)
    total_exposure = get_total_exposure(pm)
    
    win_rate = pm.total_trades > 0 ? pm.winning_trades / pm.total_trades * 100 : 0.0
    
    return Dict(
        "main_positions" => main_count,
        "hedge_positions" => hedge_count,
        "total_positions" => main_count + hedge_count,
        "total_unrealized_pnl" => total_unrealized,
        "total_realized_pnl" => pm.total_realized_pnl,
        "total_pnl" => total_unrealized + pm.total_realized_pnl,
        "total_exposure" => total_exposure,
        "total_fees" => pm.total_fees,
        "total_trades" => pm.total_trades,
        "winning_trades" => pm.winning_trades,
        "losing_trades" => pm.losing_trades,
        "win_rate" => win_rate
    )
end

"""
    print_positions(pm::PositionManager)

打印所有持仓
"""
function print_positions(pm::PositionManager)
    
    println("\n" * "="^70)
    println("持仓情况")
    println("="^70)
    
    # 主仓位
    if !isempty(pm.main_positions)
        println("\n📊 主仓位:")
        for (symbol, pos) in pm.main_positions
            pnl_pct = pos.size > 0 ? (pos.unrealized_pnl / pos.total_cost) * 100 : 0.0
            pnl_indicator = pos.unrealized_pnl >= 0 ? "🟢" : "🔴"
            
            println("  $symbol $(pos.side):")
            println("    数量: $(pos.size)")
            println("    入场价: \$$(round(pos.entry_price, digits=2))")
            println("    浮盈: $pnl_indicator \$$(round(pos.unrealized_pnl, digits=2)) ($(round(pnl_pct, digits=2))%)")
            println("    手续费: \$$(round(pos.total_fees, digits=2))")
        end
    else
        println("\n📊 主仓位: 无")
    end
    
    # 对冲仓位
    if !isempty(pm.hedge_positions)
        println("\n🛡️  对冲仓位:")
        for (symbol, pos) in pm.hedge_positions
            pnl_pct = pos.size > 0 ? (pos.unrealized_pnl / pos.total_cost) * 100 : 0.0
            pnl_indicator = pos.unrealized_pnl >= 0 ? "🟢" : "🔴"
            
            println("  $symbol $(pos.side):")
            println("    数量: $(pos.size)")
            println("    入场价: \$$(round(pos.entry_price, digits=2))")
            println("    浮盈: $pnl_indicator \$$(round(pos.unrealized_pnl, digits=2))")
            println("    浮盈: $pnl_indicator \$$(round(pos.unrealized_pnl, digits=2)) ($(round(pnl_pct, digits=2))%)")
            println("    手续费: \$$(round(pos.total_fees, digits=2))")
        end
    else
        println("\n🛡️  对冲仓位: 无")
end

# 统计摘要
summary = get_position_summary(pm)

println("\n📈 统计摘要:")
println("  总浮盈: \$$(round(summary["total_unrealized_pnl"], digits=2))")
println("  已实现盈亏: \$$(round(summary["total_realized_pnl"], digits=2))")
println("  总盈亏: \$$(round(summary["total_pnl"], digits=2))")
println("  总敞口: \$$(round(summary["total_exposure"], digits=2))")
println("  总手续费: \$$(round(summary["total_fees"], digits=2))")
println("  总交易次数: $(summary["total_trades"])")
println("  胜率: $(round(summary["win_rate"], digits=1))%")

println("="^70)
end

# ============================================================================
# 风险指标
# ============================================================================

"""
get_position_risk(pm::PositionManager, symbol::Symbol, is_hedge::Bool=false)::Dict

获取持仓风险指标
"""
function get_position_risk(pm::PositionManager, symbol::Symbol, is_hedge::Bool=false)::Dict

position = get_position(pm, symbol, is_hedge)

if isnothing(position)
return Dict(
"has_position" => false
)
end

current_price = get(pm.current_prices, symbol, position.entry_price)

# 计算盈亏百分比
pnl_pct = if position.size > 0
(position.unrealized_pnl / position.total_cost) * 100
else
0.0
end

# 计算距离入场价的百分比
price_change_pct = if position.side == :BUY
((current_price - position.entry_price) / position.entry_price) * 100
else
((position.entry_price - current_price) / position.entry_price) * 100
end

return Dict(
"has_position" => true,
"symbol" => symbol,
"side" => position.side,
"size" => position.size,
"entry_price" => position.entry_price,
"current_price" => current_price,
"unrealized_pnl" => position.unrealized_pnl,
"pnl_pct" => pnl_pct,
"price_change_pct" => price_change_pct,
"total_cost" => position.total_cost,
"total_fees" => position.total_fees,
"is_hedge" => position.is_hedge
)
end