# src/backtest/backtest_broker.jl

"""
模拟交易所（回测用）

职责：
- 模拟订单成交
- 计算滑点
- 计算手续费
- 检查保证金
- 模拟强平
- 维护账户余额
"""

using Dates
using Logging

# ============================================================================
# 模拟交易所
# ============================================================================

"""
    BacktestBroker

模拟交易所
"""
mutable struct BacktestBroker
    # 账户
    initial_balance::Float64
    balance::Float64              # 可用余额
    equity::Float64               # 权益（余额+浮盈）
    
    # 费率
    maker_fee::Float64            # Maker手续费率
    taker_fee::Float64            # Taker手续费率
    
    # 滑点
    slippage_pct::Float64         # 滑点百分比
    
    # 杠杆
    max_leverage::Int             # 最大杠杆
    
    # 当前价格（用于计算保证金）
    current_prices::Dict{Symbol, Float64}
    
    # 统计
    total_fees_paid::Float64
    total_orders::Int
    filled_orders::Int
    rejected_orders::Int
    
    # 订单簿（pending orders）
    pending_orders::Dict{String, Any}
    order_id_counter::Int
    
    function BacktestBroker(
        initial_balance::Float64;
        maker_fee::Float64=0.0002,    # 0.02%
        taker_fee::Float64=0.0004,    # 0.04%
        slippage_pct::Float64=0.0001, # 0.01%
        max_leverage::Int=20
    )
        new(
            initial_balance,
            initial_balance,
            initial_balance,
            maker_fee,
            taker_fee,
            slippage_pct,
            max_leverage,
            Dict{Symbol, Float64}(),
            0.0,
            0, 0, 0,
            Dict{String, Any}(),
            1
        )
    end
end

# ============================================================================
# 价格更新
# ============================================================================

"""
    update_price!(broker::BacktestBroker, symbol::Symbol, price::Float64)

更新当前价格
"""
function update_price!(broker::BacktestBroker, symbol::Symbol, price::Float64)
    broker.current_prices[symbol] = price
end

"""
    get_current_price(broker::BacktestBroker, symbol::Symbol)::Float64

获取当前价格
"""
function get_current_price(broker::BacktestBroker, symbol::Symbol)::Float64
    return get(broker.current_prices, symbol, 0.0)
end

# ============================================================================
# 订单执行
# ============================================================================

"""
    execute_order(broker::BacktestBroker, order, timestamp::DateTime)::Union{Nothing, Any}

执行订单（返回FillEvent或Nothing）
"""
function execute_order(broker::BacktestBroker, order, timestamp::DateTime)
    
    broker.total_orders += 1
    
    # 获取当前价格
    current_price = get_current_price(broker, order.symbol)
    
    if current_price == 0.0
        @warn "No price available for $(order.symbol), rejecting order"
        broker.rejected_orders += 1
        return nothing
    end
    
    # 检查订单类型
    if order.order_type == :MARKET
        return execute_market_order(broker, order, current_price, timestamp)
        
    elseif order.order_type == :LIMIT
        return execute_limit_order(broker, order, current_price, timestamp)
        
    else
        @warn "Unknown order type: $(order.order_type)"
        broker.rejected_orders += 1
        return nothing
    end
end

"""
    execute_market_order(broker::BacktestBroker, order, current_price::Float64, timestamp::DateTime)

执行市价单（立即成交）
"""
function execute_market_order(
    broker::BacktestBroker,
    order,
    current_price::Float64,
    timestamp::DateTime
)
    
    # 计算滑点
    slippage = current_price * broker.slippage_pct
    
    fill_price = if order.side == :BUY
        current_price + slippage  # 买入时价格更高
    else
        current_price - slippage  # 卖出时价格更低
    end
    
    # 计算手续费（市价单用taker费率）
    notional_value = order.quantity * fill_price
    commission = notional_value * broker.taker_fee
    
    # 检查余额（开仓时）
    if !order.reduce_only
        if !check_balance(broker, order.side, order.quantity, fill_price, commission)
            @warn "Insufficient balance" required=notional_value+commission available=broker.balance
            broker.rejected_orders += 1
            return nothing
        end
    end
    
    # 生成订单ID
    order_id = "FILL_$(broker.order_id_counter)"
    broker.order_id_counter += 1
    
    # 更新余额
    update_balance!(broker, order.side, order.quantity, fill_price, commission, order.reduce_only)
    
    # 更新统计
    broker.filled_orders += 1
    broker.total_fees_paid += commission
    
    @debug "Market order filled" symbol=order.symbol side=order.side qty=order.quantity price=fill_price commission=commission
    
    # 返回FillEvent（使用NamedTuple避免依赖问题）
    return (
        timestamp = timestamp,
        symbol = order.symbol,
        side = order.side,
        quantity = order.quantity,
        fill_price = fill_price,
        commission = commission,
        order_id = order_id,
        client_order_id = get(order, :client_order_id, ""),
        grid_level = get(order, :grid_level, nothing),
        is_hedge = get(order, :is_hedge, false)
    )
end

"""
    execute_limit_order(broker::BacktestBroker, order, current_price::Float64, timestamp::DateTime)

执行限价单（检查价格是否触及）
"""
function execute_limit_order(
    broker::BacktestBroker,
    order,
    current_price::Float64,
    timestamp::DateTime
)
    
    # 检查价格是否触及
    is_triggered = if order.side == :BUY
        current_price <= order.price  # 买入：当前价 <= 限价
    else
        current_price >= order.price  # 卖出：当前价 >= 限价
    end
    
    if !is_triggered
        # 价格未触及，订单pending
        return nothing
    end
    
    # 价格触及，成交
    fill_price = order.price  # 限价单按限价成交
    
    # 计算手续费（假设post_only=true，用maker费率）
    notional_value = order.quantity * fill_price
    commission = notional_value * broker.maker_fee
    
    # 检查余额
    if !order.reduce_only
        if !check_balance(broker, order.side, order.quantity, fill_price, commission)
            @warn "Insufficient balance for limit order"
            broker.rejected_orders += 1
            return nothing
        end
    end
    
    # 生成订单ID
    order_id = "FILL_$(broker.order_id_counter)"
    broker.order_id_counter += 1
    
    # 更新余额
    update_balance!(broker, order.side, order.quantity, fill_price, commission, order.reduce_only)
    
    # 更新统计
    broker.filled_orders += 1
    broker.total_fees_paid += commission
    
    @debug "Limit order filled" symbol=order.symbol side=order.side qty=order.quantity price=fill_price commission=commission
    
    # 返回FillEvent
    return (
        timestamp = timestamp,
        symbol = order.symbol,
        side = order.side,
        quantity = order.quantity,
        fill_price = fill_price,
        commission = commission,
        order_id = order_id,
        client_order_id = get(order, :client_order_id, ""),
        grid_level = get(order, :grid_level, nothing),
        is_hedge = get(order, :is_hedge, false)
    )
end

# ============================================================================
# 余额管理
# ============================================================================

"""
    check_balance(broker::BacktestBroker, side::Symbol, quantity::Float64, price::Float64, commission::Float64)::Bool

检查余额是否足够
"""
function check_balance(
    broker::BacktestBroker,
    side::Symbol,
    quantity::Float64,
    price::Float64,
    commission::Float64
)::Bool
    
    # 计算所需保证金（假设全仓模式）
    notional_value = quantity * price
    required_margin = notional_value / broker.max_leverage
    total_required = required_margin + commission
    
    return broker.balance >= total_required
end

"""
    update_balance!(broker::BacktestBroker, side::Symbol, quantity::Float64, price::Float64, commission::Float64, reduce_only::Bool)

更新余额
"""
function update_balance!(
    broker::BacktestBroker,
    side::Symbol,
    quantity::Float64,
    price::Float64,
    commission::Float64,
    reduce_only::Bool
)
    
    if reduce_only
        # 平仓：释放保证金，扣除手续费
        # 实际盈亏由PositionManager计算
        broker.balance -= commission
        
    else
        # 开仓：占用保证金，扣除手续费
        notional_value = quantity * price
        margin_used = notional_value / broker.max_leverage
        
        broker.balance -= (margin_used + commission)
    end
    
    @debug "Balance updated" balance=broker.balance commission=commission
end

"""
    update_equity!(broker::BacktestBroker, unrealized_pnl::Float64)

更新权益（余额+浮盈）
"""
function update_equity!(broker::BacktestBroker, unrealized_pnl::Float64)
    broker.equity = broker.balance + unrealized_pnl
end

# ============================================================================
# 强平检查
# ============================================================================

"""
    check_liquidation(broker::BacktestBroker, position, current_price::Float64)::Bool

检查是否触发强平
"""
function check_liquidation(
    broker::BacktestBroker,
    position,
    current_price::Float64
)::Bool
    
    # 计算维持保证金率（假设为0.5%）
    maintenance_margin_rate = 0.005
    
    # 计算仓位价值
    notional_value = position.size * current_price
    
    # 计算所需维持保证金
    required_margin = notional_value * maintenance_margin_rate
    
    # 计算当前保证金（权益）
    available_margin = broker.equity
    
    # 如果权益 < 维持保证金，触发强平
    return available_margin < required_margin
end

# ============================================================================
# 统计信息
# ============================================================================

"""
    get_broker_stats(broker::BacktestBroker)::Dict

获取broker统计信息
"""
function get_broker_stats(broker::BacktestBroker)::Dict
    
    fill_rate = broker.total_orders > 0 ? 
                broker.filled_orders / broker.total_orders * 100 : 0.0
    
    return Dict(
        "initial_balance" => broker.initial_balance,
        "current_balance" => broker.balance,
        "current_equity" => broker.equity,
        "total_fees_paid" => broker.total_fees_paid,
        "total_orders" => broker.total_orders,
        "filled_orders" => broker.filled_orders,
        "rejected_orders" => broker.rejected_orders,
        "fill_rate" => fill_rate,
        "profit_loss" => broker.equity - broker.initial_balance,
        "return_pct" => (broker.equity - broker.initial_balance) / broker.initial_balance * 100
    )
end

"""
    print_broker_stats(broker::BacktestBroker)

打印broker统计
"""
function print_broker_stats(broker::BacktestBroker)
    
    stats = get_broker_stats(broker)
    
    println("\n" * "="^70)
    println("模拟交易所统计")
    println("="^70)
    
    println("\n💰 账户:")
    println("  初始余额: \$$(round(stats["initial_balance"], digits=2))")
    println("  当前余额: \$$(round(stats["current_balance"], digits=2))")
    println("  当前权益: \$$(round(stats["current_equity"], digits=2))")
    
    pnl_indicator = stats["profit_loss"] >= 0 ? "🟢" : "🔴"
    println("  盈亏: $pnl_indicator \$$(round(stats["profit_loss"], digits=2)) ($(round(stats["return_pct"], digits=2))%)")
    
    println("\n📊 订单:")
    println("  总订单数: $(stats["total_orders"])")
    println("  成交订单: $(stats["filled_orders"])")
    println("  拒绝订单: $(stats["rejected_orders"])")
    println("  成交率: $(round(stats["fill_rate"], digits=1))%")
    
    println("\n💸 费用:")
    println("  总手续费: \$$(round(stats["total_fees_paid"], digits=2))")
    
    println("="^70)
end