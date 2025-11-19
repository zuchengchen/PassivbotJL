# src/backtest/event_engine.jl

"""
事件驱动回测引擎

基于真实Tick数据的事件驱动回测
"""

using Dates
using DataFrames
using ProgressMeter
using Logging

include("../core/events.jl")
include("../execution/position_manager.jl")

# ============================================================================
# 回测引擎
# ============================================================================

"""
    BacktestEngine

事件驱动回测引擎
"""
mutable struct BacktestEngine
    # 配置
    config::StrategyConfig
    initial_capital::Float64
    commission_rate::Float64
    slippage::Float64
    
    # 数据
    tick_data::DataFrame
    bar_data::Dict{String, DataFrame}
    current_symbol::Symbol
    
    # 事件队列
    event_queue::EventQueue
    
    # 组件
    broker::Any                      # BacktestBroker
    position_manager::PositionManager
    signal_generator::Any            # SignalGenerator
    main_grid_manager::Any           # MainGridManager
    hedge_grid_manager::Any          # HedgeGridManager
    
    # 状态
    current_time::DateTime
    current_bar_index::Dict{String, Int}  # 每个时间框架的当前索引
    is_running::Bool
    
    # 统计
    events_processed::Int
    ticks_processed::Int
    
    # 性能记录
    equity_curve::Vector{Tuple{DateTime, Float64}}
    trade_log::Vector{Dict}
    
    function BacktestEngine(
        config::StrategyConfig,
        tick_data::DataFrame,
        symbol::Symbol;
        initial_capital::Float64=10000.0,
        commission_rate::Float64=0.0004,
        slippage::Float64=0.0001
    )
        new(
            config,
            initial_capital,
            commission_rate,
            slippage,
            tick_data,
            Dict{String, DataFrame}(),
            symbol,
            EventQueue(),
            nothing, nothing, nothing, nothing, nothing,
            DateTime(0),
            Dict{String, Int}(),
            false,
            0, 0,
            Tuple{DateTime, Float64}[],
            Dict[]
        )
    end
end

# ============================================================================
# 初始化
# ============================================================================

"""
    initialize!(engine::BacktestEngine)

初始化回测引擎
"""
function initialize!(engine::BacktestEngine)
    
    @info "Initializing backtest engine..."
    
    # 1. 预处理K线数据
    @info "Preprocessing bar data..."
    engine.bar_data["1m"] = ticks_to_bars(engine.tick_data, "1m")
    engine.bar_data["5m"] = ticks_to_bars(engine.tick_data, "5m")
    engine.bar_data["15m"] = ticks_to_bars(engine.tick_data, "15m")
    
    # 初始化索引
    for tf in ["1m", "5m", "15m"]
        engine.current_bar_index[tf] = 1
    end
    
    @info "Bar data prepared" bars_1m=nrow(engine.bar_data["1m"]) bars_5m=nrow(engine.bar_data["5m"])
    
    # 2. 创建模拟交易所
    engine.broker = BacktestBroker(
        engine.initial_capital,
        engine.commission_rate,
        engine.slippage
    )
    
    # 3. 创建持仓管理器
    engine.position_manager = PositionManager()
    
    # 4. 创建信号生成器
    engine.signal_generator = SignalGenerator(engine.config, engine.bar_data)
    
    # 5. 创建网格管理器
    engine.main_grid_manager = MainGridManager(engine.config)
    engine.hedge_grid_manager = HedgeGridManager(engine.config)
    
    # 6. 记录初始权益
    push!(engine.equity_curve, (engine.tick_data[1, :timestamp], engine.initial_capital))
    
    @info "Backtest engine initialized successfully"
end

# ============================================================================
# 主回测循环
# ============================================================================

"""
    run!(engine::BacktestEngine)

运行回测
"""
function run!(engine::BacktestEngine)
    
    @info "Starting backtest..."
    @info "Ticks to process: $(nrow(engine.tick_data))"
    @info "Time range: $(engine.tick_data[1, :timestamp]) to $(engine.tick_data[end, :timestamp])"
    
    engine.is_running = true
    
    # 进度条
    progress = Progress(nrow(engine.tick_data), desc="Backtesting: ", barlen=50)
    
    # 遍历每个Tick
    for (idx, row) in enumerate(eachrow(engine.tick_data))
        
        if !engine.is_running
            @warn "Backtest interrupted"
            break
        end
        
        # 更新当前时间
        engine.current_time = row.timestamp
        
        # 创建Tick事件
        tick_event = TickEvent(
            row.timestamp,
            engine.current_symbol,
            row.price,
            row.quantity,
            row.is_buyer_maker,
            row.trade_id
        )
        
        # 处理Tick
        process_tick!(engine, tick_event)
        
        # 处理事件队列
        while !isempty(engine.event_queue)
            event = get!(engine.event_queue)
            process_event!(engine, event)
        end
        
        # 更新权益曲线（每100个tick记录一次）
        if idx % 100 == 0
            update_equity_curve!(engine)
        end
        
        # 更新进度
        engine.ticks_processed += 1
        if idx % 1000 == 0
            next!(progress)
        end
    end
    
    finish!(progress)
    
    # 最后更新权益曲线
    update_equity_curve!(engine)
    
    engine.is_running = false
    
    @info "Backtest completed" ticks=engine.ticks_processed events=engine.events_processed
end

# ============================================================================
# Tick处理
# ============================================================================

"""
    process_tick!(engine::BacktestEngine, tick::TickEvent)

处理Tick事件
"""
function process_tick!(engine::BacktestEngine, tick::TickEvent)
    
    # 1. 更新broker价格
    update_price!(engine.broker, tick.symbol, tick.price)
    
    # 2. 更新持仓管理器
    update_price!(engine.position_manager, tick.symbol, tick.price, tick.timestamp)
    
    # 3. 检查K线完成（生成信号）
    check_bar_updates!(engine, tick)
    
    # 4. 检查网格触发
    check_grid_triggers!(engine, tick)
    
    # 5. 检查对冲触发
    check_hedge_triggers!(engine, tick)
    
    # 6. 检查止盈止损
    check_stop_conditions!(engine, tick)
end

# ============================================================================
# K线更新
# ============================================================================

"""
    check_bar_updates!(engine::BacktestEngine, tick::TickEvent)

检查K线更新并生成信号
"""
function check_bar_updates!(engine::BacktestEngine, tick::TickEvent)
    
    # 检查各个时间框架
    for (timeframe, bars) in engine.bar_data
        
        if should_update_signal(engine, tick.timestamp, timeframe)
            
            # 获取当前K线索引
            idx = engine.current_bar_index[timeframe]
            
            if idx <= nrow(bars)
                bar = bars[idx, :]
                
                # 创建Bar事件
                bar_event = BarEvent(
                    bar.timestamp,
                    tick.symbol,
                    timeframe,
                    bar.open,
                    bar.high,
                    bar.low,
                    bar.close,
                    bar.volume
                )
                
                # 生成信号
                signal = generate_signal(engine.signal_generator, bar_event, tick.timestamp)
                
                if !isnothing(signal)
                    put!(engine.event_queue, signal)
                end
                
                # 移动到下一根K线
                engine.current_bar_index[timeframe] += 1
            end
        end
    end
end

"""
    should_update_signal(engine::BacktestEngine, timestamp::DateTime, timeframe::String)::Bool

判断是否应该更新信号
"""
function should_update_signal(engine::BacktestEngine, timestamp::DateTime, timeframe::String)::Bool
    
    idx = engine.current_bar_index[timeframe]
    bars = engine.bar_data[timeframe]
    
    if idx > nrow(bars)
        return false
    end
    
    bar_time = bars[idx, :timestamp]
    
    # 当tick时间超过当前K线时间时，触发更新
    return timestamp >= bar_time
end

# ============================================================================
# 网格触发检查
# ============================================================================

"""
    check_grid_triggers!(engine::BacktestEngine, tick::TickEvent)

检查网格触发
"""
function check_grid_triggers!(engine::BacktestEngine, tick::TickEvent)
    
    # 检查主网格
    if has_active_grid(engine.main_grid_manager, tick.symbol)
        triggers = check_price_triggers(
            engine.main_grid_manager,
            tick.symbol,
            tick.price,
            tick.timestamp
        )
        
        for trigger in triggers
            put!(engine.event_queue, trigger)
        end
    end
    
    # 检查对冲网格
    if has_active_grid(engine.hedge_grid_manager, tick.symbol)
        triggers = check_price_triggers(
            engine.hedge_grid_manager,
            tick.symbol,
            tick.price,
            tick.timestamp
        )
        
        for trigger in triggers
            put!(engine.event_queue, trigger)
        end
    end
end

# ============================================================================
# 对冲检查
# ============================================================================

"""
    check_hedge_triggers!(engine::BacktestEngine, tick::TickEvent)

检查是否需要启动对冲
"""
function check_hedge_triggers!(engine::BacktestEngine, tick::TickEvent)
    
    # 获取主仓位
    position = get_position(engine.position_manager, tick.symbol, false)
    
    if isnothing(position) || position.size == 0
        return
    end
    
    # 检查是否需要对冲
    hedge_event = should_activate_hedge(
        engine.hedge_grid_manager,
        position,
        tick.price,
        tick.timestamp,
        engine.config
    )
    
    if !isnothing(hedge_event)
        put!(engine.event_queue, hedge_event)
    end
end

# ============================================================================
# 止盈止损检查
# ============================================================================

"""
    check_stop_conditions!(engine::BacktestEngine, tick::TickEvent)

检查止盈止损条件
"""
function check_stop_conditions!(engine::BacktestEngine, tick::TickEvent)
    
    # 检查主仓位
    position = get_position(engine.position_manager, tick.symbol, false)
    
    if !isnothing(position) && position.size > 0
        
        # 止损检查
        stop_event = check_stop_loss(
            position,
            tick.price,
            tick.timestamp,
            engine.config
        )
        
        if !isnothing(stop_event)
            put!(engine.event_queue, stop_event)
        end
        
        # 止盈检查
        tp_event = check_take_profit(
            engine.main_grid_manager,
            tick.symbol,
            tick.price,
            tick.timestamp
        )
        
        if !isnothing(tp_event)
            put!(engine.event_queue, tp_event)
        end
    end
end

# ============================================================================
# 事件处理
# ============================================================================

"""
    process_event!(engine::BacktestEngine, event::Event)

处理事件
"""
function process_event!(engine::BacktestEngine, event::Event)
    
    engine.events_processed += 1
    
    if event isa SignalEvent
        handle_signal!(engine, event)
        
    elseif event isa GridTriggerEvent
        handle_grid_trigger!(engine, event)
        
    elseif event isa OrderEvent
        handle_order!(engine, event)
        
    elseif event isa FillEvent
        handle_fill!(engine, event)
        
    elseif event isa HedgeTriggerEvent
        handle_hedge_trigger!(engine, event)
        
    elseif event isa StopLossEvent
        handle_stop_loss!(engine, event)
        
    elseif event isa TakeProfitEvent
        handle_take_profit!(engine, event)
    end
end

"""
    handle_signal!(engine::BacktestEngine, signal::SignalEvent)

处理信号事件
"""
function handle_signal!(engine::BacktestEngine, signal::SignalEvent)
    
    @debug "Signal received" type=signal.signal_type strength=signal.strength
    
    if signal.signal_type == :LONG_ENTRY
        # 初始化做多网格
        initialize_grid!(
            engine.main_grid_manager,
            signal,
            engine.broker.current_prices[signal.symbol]
        )
        
    elseif signal.signal_type == :SHORT_ENTRY
        # 初始化做空网格
        initialize_grid!(
            engine.main_grid_manager,
            signal,
            engine.broker.current_prices[signal.symbol]
        )
        
    elseif signal.signal_type == :CLOSE
        # 关闭所有持仓
        close_all_positions!(engine, signal.symbol)
    end
end

"""
    handle_grid_trigger!(engine::BacktestEngine, trigger::GridTriggerEvent)

处理网格触发
"""
function handle_grid_trigger!(engine::BacktestEngine, trigger::GridTriggerEvent)
    
    # 创建订单事件
    side = trigger.is_hedge ? 
           (get_grid_side(engine.hedge_grid_manager, trigger.symbol) == LONG ? :BUY : :SELL) :
           (get_grid_side(engine.main_grid_manager, trigger.symbol) == LONG ? :BUY : :SELL)
    
    order = OrderEvent(
        trigger.timestamp,
        trigger.symbol,
        side,
        :LIMIT,
        trigger.order_quantity,
        trigger.trigger_price,
        grid_level=trigger.grid_level,
        is_hedge=trigger.is_hedge
    )
    
    put!(engine.event_queue, order)
end

"""
    handle_order!(engine::BacktestEngine, order::OrderEvent)

处理订单事件
"""
function handle_order!(engine::BacktestEngine, order::OrderEvent)
    
    # 提交到模拟交易所
    fill = execute_order(engine.broker, order, engine.current_time)
    
    if !isnothing(fill)
        put!(engine.event_queue, fill)
    end
end

"""
    handle_fill!(engine::BacktestEngine, fill::FillEvent)

处理成交事件
"""
function handle_fill!(engine::BacktestEngine, fill::FillEvent)
    
    @debug "Fill received" symbol=fill.symbol side=fill.side qty=fill.quantity price=fill.fill_price
    
    # 更新持仓
    on_fill!(engine.position_manager, fill)
    
    # 通知网格管理器
    if fill.is_hedge
        on_grid_fill!(engine.hedge_grid_manager, fill)
    else
        on_grid_fill!(engine.main_grid_manager, fill)
    end
    
    # 记录交易
    log_trade!(engine, fill)
end

"""
    handle_hedge_trigger!(engine::BacktestEngine, trigger::HedgeTriggerEvent)

处理对冲触发
"""
function handle_hedge_trigger!(engine::BacktestEngine, trigger::HedgeTriggerEvent)
    
    @info "Hedge activated" symbol=trigger.symbol reason=trigger.reason pnl_pct=trigger.unrealized_pnl_pct
    
    # 初始化对冲网格
    initialize_hedge_grid!(
        engine.hedge_grid_manager,
        trigger,
        engine.broker.current_prices[trigger.symbol]
    )
end

"""
    handle_stop_loss!(engine::BacktestEngine, stop::StopLossEvent)

处理止损
"""
function handle_stop_loss!(engine::BacktestEngine, stop::StopLossEvent)
    
    @warn "Stop loss triggered" symbol=stop.symbol reason=stop.reason loss=stop.loss_amount
    
    # 市价平仓
    close_position_market!(engine, stop.symbol, stop.position_size)
end

"""
    handle_take_profit!(engine::BacktestEngine, tp::TakeProfitEvent)

处理止盈
"""
function handle_take_profit!(engine::BacktestEngine, tp::TakeProfitEvent)
    
    @info "Take profit" symbol=tp.symbol level=tp.tp_level profit=tp.profit_amount
    
    # 部分平仓
    close_position_limit!(engine, tp.symbol, tp.close_quantity, tp.tp_price)
end

# ============================================================================
# 辅助函数
# ============================================================================

"""
    update_equity_curve!(engine::BacktestEngine)

更新权益曲线
"""
function update_equity_curve!(engine::BacktestEngine)
    
    current_equity = engine.broker.balance + get_total_unrealized_pnl(engine.position_manager)
    
    push!(engine.equity_curve, (engine.current_time, current_equity))
end

"""
    log_trade!(engine::BacktestEngine, fill::FillEvent)

记录交易
"""
function log_trade!(engine::BacktestEngine, fill::FillEvent)
    
    trade = Dict(
        "timestamp" => fill.timestamp,
        "symbol" => fill.symbol,
        "side" => fill.side,
        "quantity" => fill.quantity,
        "price" => fill.fill_price,
        "commission" => fill.commission,
        "is_hedge" => fill.is_hedge,
        "grid_level" => fill.grid_level
    )
    
    push!(engine.trade_log, trade)
end

"""
    close_all_positions!(engine::BacktestEngine, symbol::Symbol)

关闭所有持仓
"""
function close_all_positions!(engine::BacktestEngine, symbol::Symbol)
    
    # 关闭主仓位
    main_pos = get_position(engine.position_manager, symbol, false)
    if !isnothing(main_pos) && main_pos.size > 0
        close_position_market!(engine, symbol, main_pos.size, false)
    end
    
    # 关闭对冲仓位
    hedge_pos = get_position(engine.position_manager, symbol, true)
    if !isnothing(hedge_pos) && hedge_pos.size > 0
        close_position_market!(engine, symbol, hedge_pos.size, true)
    end
end

"""
    close_position_market!(engine::BacktestEngine, symbol::Symbol, quantity::Float64, is_hedge::Bool=false)

市价平仓
"""
function close_position_market!(engine::BacktestEngine, symbol::Symbol, quantity::Float64, is_hedge::Bool=false)
    
    position = get_position(engine.position_manager, symbol, is_hedge)
    
    if isnothing(position)
        return
    end
    
    # 平仓方向相反
    side = position.side == :BUY ? :SELL : :BUY
    
    order = OrderEvent(
        engine.current_time,
        symbol,
        side,
        :MARKET,
        quantity,
        nothing,
        reduce_only=true,
        is_hedge=is_hedge
    )
    
    put!(engine.event_queue, order)
end

"""
    close_position_limit!(engine::BacktestEngine, symbol::Symbol, quantity::Float64, price::Float64, is_hedge::Bool=false)

限价平仓
"""
function close_position_limit!(engine::BacktestEngine, symbol::Symbol, quantity::Float64, price::Float64, is_hedge::Bool=false)
    
    position = get_position(engine.position_manager, symbol, is_hedge)
    
    if isnothing(position)
        return
    end
    
    side = position.side == :BUY ? :SELL : :BUY
    
    order = OrderEvent(
        engine.current_time,
        symbol,
        side,
        :LIMIT,
        quantity,
        price,
        reduce_only=true,
        is_hedge=is_hedge
    )
    
    put!(engine.event_queue, order)
end