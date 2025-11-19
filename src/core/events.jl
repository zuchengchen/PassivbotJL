# src/core/events.jl

"""
事件驱动系统

所有交易行为都通过事件触发
"""

using Dates

# ============================================================================
# 事件类型枚举
# ============================================================================

@enum EventType begin
    # 市场事件
    TICK_EVENT          # Tick价格更新
    BAR_EVENT           # K线更新
    
    # 信号事件
    SIGNAL_EVENT        # 开仓信号
    
    # 订单事件
    ORDER_EVENT         # 下单请求
    FILL_EVENT          # 订单成交
    CANCEL_EVENT        # 撤单
    
    # 网格事件
    GRID_TRIGGER_EVENT  # 网格触发
    HEDGE_TRIGGER_EVENT # 对冲触发
    
    # 风控事件
    STOP_LOSS_EVENT     # 止损
    TAKE_PROFIT_EVENT   # 止盈
    RISK_WARNING_EVENT  # 风险警告
end

# ============================================================================
# 基础事件
# ============================================================================

"""
    Event

所有事件的抽象基类
"""
abstract type Event end

"""
    get_timestamp(event::Event)::DateTime

获取事件时间戳
"""
function get_timestamp(event::Event)::DateTime
    return event.timestamp
end

# ============================================================================
# 市场事件
# ============================================================================

"""
    TickEvent

Tick价格事件（最重要的事件）
"""
struct TickEvent <: Event
    timestamp::DateTime
    symbol::Symbol
    price::Float64
    quantity::Float64
    is_buyer_maker::Bool  # 是否为主动卖出
    trade_id::Int64
    
    function TickEvent(timestamp, symbol, price, quantity, is_buyer_maker, trade_id)
        new(timestamp, symbol, price, quantity, is_buyer_maker, trade_id)
    end
end

"""
    BarEvent

K线事件（用于计算指标）
"""
struct BarEvent <: Event
    timestamp::DateTime
    symbol::Symbol
    timeframe::String
    open::Float64
    high::Float64
    low::Float64
    close::Float64
    volume::Float64
    
    function BarEvent(timestamp, symbol, timeframe, o, h, l, c, v)
        new(timestamp, symbol, timeframe, o, h, l, c, v)
    end
end

# ============================================================================
# 信号事件
# ============================================================================

"""
    SignalEvent

交易信号事件
"""
struct SignalEvent <: Event
    timestamp::DateTime
    symbol::Symbol
    signal_type::Symbol  # :LONG_ENTRY, :SHORT_ENTRY, :CLOSE
    strength::Float64    # 信号强度 0-1
    
    # 策略参数
    grid_spacing::Float64
    max_levels::Int
    ddown_factor::Float64
    
    # 指标值（用于记录）
    indicators::Dict{Symbol, Any}  # ✅ 改为 Any
    
    function SignalEvent(timestamp, symbol, signal_type, strength, 
                        grid_spacing, max_levels, ddown_factor, indicators)
        new(timestamp, symbol, signal_type, strength,
            grid_spacing, max_levels, ddown_factor, indicators)
    end
end

# ============================================================================
# 订单事件
# ============================================================================

"""
    OrderEvent

下单事件
"""
struct OrderEvent <: Event
    timestamp::DateTime
    symbol::Symbol
    side::Symbol          # :BUY, :SELL
    order_type::Symbol    # :LIMIT, :MARKET
    quantity::Float64
    price::Union{Float64, Nothing}
    
    # 订单属性
    reduce_only::Bool
    post_only::Bool
    
    # 关联信息
    grid_level::Union{Int, Nothing}
    is_hedge::Bool
    
    # 客户端订单ID
    client_order_id::String
    
    function OrderEvent(timestamp, symbol, side, order_type, quantity, price;
                       reduce_only=false, post_only=false,
                       grid_level=nothing, is_hedge=false,
                       client_order_id=string(uuid4()))
        new(timestamp, symbol, side, order_type, quantity, price,
            reduce_only, post_only, grid_level, is_hedge, client_order_id)
    end
end

"""
    FillEvent

订单成交事件
"""
struct FillEvent <: Event
    timestamp::DateTime
    symbol::Symbol
    side::Symbol
    quantity::Float64
    fill_price::Float64
    commission::Float64
    
    # 订单信息
    order_id::String
    client_order_id::String
    
    # 关联信息
    grid_level::Union{Int, Nothing}
    is_hedge::Bool
    
    function FillEvent(timestamp, symbol, side, quantity, fill_price, commission,
                      order_id, client_order_id;
                      grid_level=nothing, is_hedge=false)
        new(timestamp, symbol, side, quantity, fill_price, commission,
            order_id, client_order_id, grid_level, is_hedge)
    end
end

# ============================================================================
# 网格事件
# ============================================================================

"""
    GridTriggerEvent

网格触发事件
"""
struct GridTriggerEvent <: Event
    timestamp::DateTime
    symbol::Symbol
    grid_level::Int
    trigger_price::Float64
    order_quantity::Float64
    is_hedge::Bool
    
    function GridTriggerEvent(timestamp, symbol, level, price, qty, is_hedge=false)
        new(timestamp, symbol, level, price, qty, is_hedge)
    end
end

"""
    HedgeTriggerEvent

对冲触发事件
"""
struct HedgeTriggerEvent <: Event
    timestamp::DateTime
    symbol::Symbol
    reason::Symbol  # :DRAWDOWN, :TREND_REVERSAL, :MANUAL
    
    # 主仓位信息
    main_position_size::Float64
    main_avg_entry::Float64
    current_price::Float64
    unrealized_pnl::Float64
    unrealized_pnl_pct::Float64
    
    # 对冲参数
    hedge_ratio::Float64
    hedge_grid_spacing::Float64
    
    function HedgeTriggerEvent(timestamp, symbol, reason,
                              main_pos_size, main_avg_entry, current_price,
                              unrealized_pnl, unrealized_pnl_pct,
                              hedge_ratio, hedge_grid_spacing)
        new(timestamp, symbol, reason,
            main_pos_size, main_avg_entry, current_price,
            unrealized_pnl, unrealized_pnl_pct,
            hedge_ratio, hedge_grid_spacing)
    end
end

# ============================================================================
# 风控事件
# ============================================================================

"""
    StopLossEvent

止损事件
"""
struct StopLossEvent <: Event
    timestamp::DateTime
    symbol::Symbol
    reason::Symbol  # :MAX_LOSS, :TREND_REVERSAL, :TIME_LIMIT
    
    position_size::Float64
    avg_entry::Float64
    current_price::Float64
    loss_amount::Float64
    loss_pct::Float64
    
    function StopLossEvent(timestamp, symbol, reason,
                          pos_size, avg_entry, current_price,
                          loss_amount, loss_pct)
        new(timestamp, symbol, reason,
            pos_size, avg_entry, current_price,
            loss_amount, loss_pct)
    end
end

"""
    TakeProfitEvent

止盈事件
"""
struct TakeProfitEvent <: Event
    timestamp::DateTime
    symbol::Symbol
    tp_level::Int
    
    close_quantity::Float64
    tp_price::Float64
    profit_amount::Float64
    profit_pct::Float64
    
    function TakeProfitEvent(timestamp, symbol, tp_level,
                            close_qty, tp_price, profit_amt, profit_pct)
        new(timestamp, symbol, tp_level,
            close_qty, tp_price, profit_amt, profit_pct)
    end
end

# ============================================================================
# 事件队列
# ============================================================================

"""
    EventQueue

事件队列（优先队列，按时间排序）
"""
mutable struct EventQueue
    events::Vector{Event}
    
    function EventQueue()
        new(Event[])
    end
end

"""
    put!(queue::EventQueue, event::Event)

添加事件到队列
"""
function Base.put!(queue::EventQueue, event::Event)
    push!(queue.events, event)
    
    # 按时间排序（保持时间顺序）
    sort!(queue.events, by=e -> get_timestamp(e))
end

"""
    get!(queue::EventQueue)::Union{Event, Nothing}

从队列取出最早的事件
"""
function Base.get!(queue::EventQueue)::Union{Event, Nothing}
    if isempty(queue.events)
        return nothing
    end
    
    return popfirst!(queue.events)
end

"""
    isempty(queue::EventQueue)::Bool

检查队列是否为空
"""
function Base.isempty(queue::EventQueue)::Bool
    return isempty(queue.events)
end

"""
    length(queue::EventQueue)::Int

获取队列长度
"""
function Base.length(queue::EventQueue)::Int
    return length(queue.events)
end

"""
    clear!(queue::EventQueue)

清空队列
"""
function clear!(queue::EventQueue)
    empty!(queue.events)
end