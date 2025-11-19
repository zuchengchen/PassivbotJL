# src/live/live_broker.jl

"""
实盘Broker - 整合订单客户端与持仓管理

功能：
- 对接实盘订单客户端
- 实现与回测Broker相同的接口
- 订单状态跟踪
- 持仓实时同步
"""

using Dates
using Logging

include("live_order_client.jl")
include("../execution/position_manager.jl")
include("../core/events.jl")

# ============================================================================
# 实盘Broker
# ============================================================================

"""
    LiveBroker

实盘交易Broker

与BacktestBroker接口兼容，可以复用回测策略代码
"""
mutable struct LiveBroker
    # 订单客户端
    order_client::LiveOrderClient
    
    # 持仓管理器
    position_manager::PositionManager
    
    # 订单跟踪
    active_orders::Dict{Int64, Dict{Symbol, Any}}  # order_id => order_info
    order_fills::Vector{FillEvent}                  # 成交记录
    
    # 配置
    symbol::Symbol
    commission_rate::Float64
    slippage_bps::Float64
    
    # 统计
    total_orders::Int
    filled_orders::Int
    rejected_orders::Int
    
    # 同步状态
    last_position_sync::DateTime
    last_order_sync::DateTime
    
    function LiveBroker(
        api_key::String, 
        api_secret::String, 
        symbol::Symbol;
        market::Symbol=:futures,
        testnet::Bool=true,
        commission_rate::Float64=0.0004,
        slippage_bps::Float64=2.0
    )
        # 创建订单客户端
        order_client = LiveOrderClient(api_key, api_secret, market=market)
        
        # 设置测试网/主网
        if testnet
            order_client.base_url = "https://testnet.binancefuture.com"
        end
        
        # 创建持仓管理器
        position_manager = PositionManager()
        
        broker = new(
            order_client,
            position_manager,
            Dict{Int64, Dict{Symbol, Any}}(),
            FillEvent[],
            symbol,
            commission_rate,
            slippage_bps,
            0, 0, 0,
            DateTime(0),
            DateTime(0)
        )
        
        # 初始同步
        sync_positions!(broker)
        sync_orders!(broker)
        
        return broker
    end
end

# ============================================================================
# 持仓同步
# ============================================================================

"""
    sync_positions!(broker::LiveBroker)

同步交易所持仓到本地
"""
function sync_positions!(broker::LiveBroker)
    try
        positions = get_position(broker.order_client, string(broker.symbol))
        
        for pos in positions
            amt = parse(Float64, pos.positionAmt)
            
            if amt != 0
                entry_price = parse(Float64, pos.entryPrice)
                unrealized_pnl = parse(Float64, pos.unRealizedProfit)
                
                @info "Position synced" symbol=broker.symbol amount=amt entry_price=entry_price pnl=unrealized_pnl
                
                # 更新本地持仓管理器
                # 这里需要根据你的PositionManager实现来调整
                # broker.position_manager.positions[broker.symbol] = ...
            end
        end
        
        broker.last_position_sync = now(UTC)
        
    catch e
        @error "Failed to sync positions" exception=e
    end
end

"""
    sync_orders!(broker::LiveBroker)

同步未完成订单
"""
function sync_orders!(broker::LiveBroker)
    try
        orders = get_open_orders(broker.order_client, string(broker.symbol))
        
        # 清空本地订单缓存
        empty!(broker.active_orders)
        
        # 更新订单状态
        for order in orders
            order_id = order.orderId
            
            broker.active_orders[order_id] = Dict{Symbol, Any}(
                :symbol => Symbol(order.symbol),
                :side => Symbol(order.side),
                :quantity => parse(Float64, order.origQty),
                :price => parse(Float64, order.price),
                :status => Symbol(order.status),
                :filled_qty => parse(Float64, order.executedQty),
                :time => unix2datetime(order.time / 1000)
            )
        end
        
        broker.last_order_sync = now(UTC)
        
        @debug "Orders synced" count=length(broker.active_orders)
        
    catch e
        @error "Failed to sync orders" exception=e
    end
end

# ============================================================================
# 订单提交
# ============================================================================

"""
    submit_order(broker::LiveBroker, signal::SignalEvent)::Union{Int64, Nothing}

提交订单（基于信号）
"""
function submit_order(broker::LiveBroker, signal::SignalEvent)::Union{Int64, Nothing}
    
    @info "Submitting order from signal" direction=signal.direction quantity=signal.quantity
    
    # 转换方向
    side = signal.direction == :LONG ? "BUY" : "SELL"
    
    # 提交订单
    return submit_market_order(
        broker,
        broker.symbol,
        Symbol(side),
        signal.quantity
    )
end

"""
    submit_market_order(broker::LiveBroker, symbol::Symbol, side::Symbol, quantity::Float64)::Union{Int64, Nothing}

提交市价单
"""
function submit_market_order(
    broker::LiveBroker,
    symbol::Symbol,
    side::Symbol,
    quantity::Float64
)::Union{Int64, Nothing}
    
    try
        @info "Placing market order" symbol=symbol side=side quantity=quantity
        
        result = place_market_order(
            broker.order_client,
            string(symbol),
            string(side),
            quantity
        )
        
        broker.total_orders += 1
        
        order_id = result.orderId
        
        # 记录订单
        broker.active_orders[order_id] = Dict{Symbol, Any}(
            :symbol => symbol,
            :side => side,
            :quantity => quantity,
            :price => nothing,  # 市价单无价格
            :status => Symbol(result.status),
            :filled_qty => 0.0,
            :time => now(UTC)
        )
        
        @info "Market order placed" order_id=order_id
        
        return order_id
        
    catch e
        @error "Failed to place market order" exception=e
        broker.rejected_orders += 1
        return nothing
    end
end

"""
    submit_limit_order(broker::LiveBroker, symbol::Symbol, side::Symbol, quantity::Float64, price::Float64)::Union{Int64, Nothing}

提交限价单
"""
function submit_limit_order(
    broker::LiveBroker,
    symbol::Symbol,
    side::Symbol,
    quantity::Float64,
    price::Float64
)::Union{Int64, Nothing}
    
    try
        @info "Placing limit order" symbol=symbol side=side quantity=quantity price=price
        
        result = place_limit_order(
            broker.order_client,
            string(symbol),
            string(side),
            quantity,
            price
        )
        
        broker.total_orders += 1
        
        order_id = result.orderId
        
        # 记录订单
        broker.active_orders[order_id] = Dict{Symbol, Any}(
            :symbol => symbol,
            :side => side,
            :quantity => quantity,
            :price => price,
            :status => Symbol(result.status),
            :filled_qty => 0.0,
            :time => now(UTC)
        )
        
        @info "Limit order placed" order_id=order_id
        
        return order_id
        
    catch e
        @error "Failed to place limit order" exception=e
        broker.rejected_orders += 1
        return nothing
    end
end

# ============================================================================
# 订单管理
# ============================================================================

"""
    cancel_order(broker::LiveBroker, order_id::Int64)::Bool

撤销订单
"""
function cancel_order(broker::LiveBroker, order_id::Int64)::Bool
    
    if !haskey(broker.active_orders, order_id)
        @warn "Order not found" order_id=order_id
        return false
    end
    
    order_info = broker.active_orders[order_id]
    
    try
        cancel_order(
            broker.order_client,
            string(order_info[:symbol]),
            order_id
        )
        
        # 更新状态
        order_info[:status] = :CANCELED
        delete!(broker.active_orders, order_id)
        
        @info "Order canceled" order_id=order_id
        
        return true
        
    catch e
        @error "Failed to cancel order" order_id=order_id exception=e
        return false
    end
end

"""
    cancel_all_orders(broker::LiveBroker)

撤销所有订单
"""
function cancel_all_orders(broker::LiveBroker)
    
    @warn "Canceling all orders" symbol=broker.symbol
    
    try
        cancel_all_orders(broker.order_client, string(broker.symbol))
        
        # 清空本地订单
        empty!(broker.active_orders)
        
        @info "All orders canceled"
        
    catch e
        @error "Failed to cancel all orders" exception=e
    end
end

# ============================================================================
# 订单状态检查
# ============================================================================

"""
    check_order_fills!(broker::LiveBroker)

检查订单成交情况
"""
function check_order_fills!(broker::LiveBroker)
    
    # 获取所有活跃订单ID
    order_ids = collect(keys(broker.active_orders))
    
    for order_id in order_ids
        try
            # 查询订单状态
            order_status = get_order(
                broker.order_client,
                string(broker.symbol),
                order_id
            )
            
            status = Symbol(order_status.status)
            filled_qty = parse(Float64, order_status.executedQty)
            
            # 更新本地订单信息
            order_info = broker.active_orders[order_id]
            old_filled = order_info[:filled_qty]
            
            if filled_qty > old_filled
                # 有新的成交
                new_fill_qty = filled_qty - old_filled
                avg_price = parse(Float64, order_status.avgPrice)
                
                @info "Order partially/fully filled" order_id=order_id filled=new_fill_qty price=avg_price
                
                # 创建成交事件
                fill_event = FillEvent(
                    now(UTC),
                    broker.symbol,
                    order_info[:side] == :BUY ? :LONG : :SHORT,
                    new_fill_qty,
                    avg_price,
                    broker.commission_rate
                )
                
                push!(broker.order_fills, fill_event)
                broker.filled_orders += 1
                
                # 更新持仓
                update_position!(broker.position_manager, fill_event)
            end
            
            # 更新订单状态
            order_info[:filled_qty] = filled_qty
            order_info[:status] = status
            
            # 如果订单完全成交或取消，从活跃列表移除
            if status in [:FILLED, :CANCELED, :REJECTED, :EXPIRED]
                delete!(broker.active_orders, order_id)
            end
            
        catch e
            @error "Failed to check order" order_id=order_id exception=e
        end
    end
end

# ============================================================================
# 持仓查询
# ============================================================================

"""
    get_position(broker::LiveBroker)::Union{Position, Nothing}

获取当前持仓
"""
function get_position(broker::LiveBroker)::Union{Position, Nothing}
    return get_position(broker.position_manager, broker.symbol)
end

"""
    get_position_quantity(broker::LiveBroker)::Float64

获取持仓数量（正数=多仓，负数=空仓）
"""
function get_position_quantity(broker::LiveBroker)::Float64
    pos = get_position(broker)
    return isnothing(pos) ? 0.0 : pos.quantity
end

# ============================================================================
# 统计与报告
# ============================================================================

"""
    print_broker_stats(broker::LiveBroker)

打印Broker统计
"""
function print_broker_stats(broker::LiveBroker)
    println("\n" * "="^70)
    println("Live Broker 统计")
    println("="^70)
    println("  交易对: $(broker.symbol)")
    println("  总订单: $(broker.total_orders)")
    println("  已成交: $(broker.filled_orders)")
    println("  被拒绝: $(broker.rejected_orders)")
    println("  活跃订单: $(length(broker.active_orders))")
    println("  成交记录: $(length(broker.order_fills))")
    
    # 持仓信息（安全版本）
    println("\n  当前持仓:")
    
    # 方法1：直接查询交易所
    try
        positions = get_position(broker.order_client, string(broker.symbol))
        
        has_position = false
        for pos in positions
            amt = parse(Float64, pos.positionAmt)
            if amt != 0
                has_position = true
                println("    数量: $amt")
                println("    入场价: \$$(pos.entryPrice)")
                println("    未实现盈亏: \$$(pos.unRealizedProfit)")
            end
        end
        
        if !has_position
            println("    无持仓")
        end
        
    catch e
        println("    查询失败")
        @debug "Position query error" exception=e
    end
    
    println("="^70)
end