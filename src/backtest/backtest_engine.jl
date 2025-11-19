# src/backtest/backtest_engine.jl

"""
完整回测引擎

集成所有组件：
- BacktestBroker（模拟交易所）
- SignalGenerator（信号生成）
- MainGridManager（主网格）
- HedgeGridManager（对冲网格）
- PositionManager（持仓管理）
- EventQueue（事件驱动）
"""

using Dates
using DataFrames
using ProgressMeter
using Logging
using Statistics

include("../core/events.jl")
include("../data/tick_data.jl")
include("../execution/position_manager.jl")
include("backtest_broker.jl")
include("signal_generator.jl")
include("main_grid_manager.jl")
include("hedge_grid_manager.jl")

# ============================================================================
# 回测引擎
# ============================================================================

"""
    BacktestEngine

完整的事件驱动回测引擎
"""
mutable struct BacktestEngine
    # 配置
    config
    symbol::Symbol
    initial_capital::Float64
    
    # 数据
    tick_data::DataFrame
    bar_data::Dict{String, DataFrame}
    
    # 事件队列
    event_queue::EventQueue
    
    # 核心组件
    broker
    position_manager
    signal_generator
    main_grid_manager
    hedge_grid_manager
    
    # 状态
    current_time::DateTime
    current_bar_index::Dict{String, Int}
    is_running::Bool
    
    # 统计
    ticks_processed::Int
    events_processed::Int
    signals_generated::Int
    trades_executed::Int
    
    # 性能记录
    equity_curve::Vector{Tuple{DateTime, Float64}}
    trade_log::Vector{Dict}
end

# 构造函数
function BacktestEngine(
    config,
    symbol::Symbol,
    tick_data::DataFrame;
    initial_capital::Float64=10000.0
)
    BacktestEngine(
        config,
        symbol,
        initial_capital,
        tick_data,
        Dict{String, DataFrame}(),
        EventQueue(),
        nothing,
        nothing,
        nothing,
        nothing,
        nothing,
        DateTime(0),
        Dict{String, Int}(),
        false,
        0, 0, 0, 0,
        Tuple{DateTime, Float64}[],
        Dict[]
    )
end

# ============================================================================
# 事件转换辅助函数
# ============================================================================

"""
    wrap_signal_event(signal)::SignalEvent

将NamedTuple信号包装为SignalEvent
"""
function wrap_signal_event(signal)::SignalEvent
    return SignalEvent(
        signal.timestamp,
        signal.symbol,
        signal.signal_type,
        signal.strength,
        signal.grid_spacing,
        signal.max_levels,
        signal.ddown_factor,
        signal.indicators
    )
end

"""
    wrap_grid_trigger_event(trigger)::GridTriggerEvent

将NamedTuple触发包装为GridTriggerEvent
"""
function wrap_grid_trigger_event(trigger)::GridTriggerEvent
    return GridTriggerEvent(
        trigger.timestamp,
        trigger.symbol,
        trigger.grid_level,
        trigger.trigger_price,
        trigger.order_quantity,
        get(trigger, :is_hedge, false)
    )
end

"""
    wrap_hedge_trigger_event(trigger)::HedgeTriggerEvent

将NamedTuple对冲触发包装为HedgeTriggerEvent
"""
function wrap_hedge_trigger_event(trigger)::HedgeTriggerEvent
    return HedgeTriggerEvent(
        trigger.timestamp,
        trigger.symbol,
        trigger.reason,
        trigger.main_position_size,
        trigger.main_avg_entry,
        trigger.current_price,
        trigger.unrealized_pnl,
        trigger.unrealized_pnl_pct,
        trigger.hedge_ratio,
        trigger.hedge_grid_spacing
    )
end

"""
    wrap_take_profit_event(tp)::TakeProfitEvent

将NamedTuple止盈包装为TakeProfitEvent
"""
function wrap_take_profit_event(tp)::TakeProfitEvent
    return TakeProfitEvent(
        tp.timestamp,
        tp.symbol,
        tp.tp_level,
        tp.close_quantity,
        tp.tp_price,
        tp.profit_amount,
        tp.profit_pct
    )
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
    
    # 检查并修复列名
    if hasproperty(engine.tick_data, :agg_trade_id) && !hasproperty(engine.tick_data, :trade_id)
        rename!(engine.tick_data, :agg_trade_id => :trade_id)
    end
    
    # 确保必需的列存在
    required_columns = [:timestamp, :price, :quantity, :is_buyer_maker, :trade_id]
    for col in required_columns
        if !hasproperty(engine.tick_data, col)
            error("Missing required column: $col")
        end
    end
    
    # 预处理K线数据
    @info "Preprocessing bar data..."
    engine.bar_data["1m"] = ticks_to_bars(engine.tick_data, "1m")
    engine.bar_data["5m"] = ticks_to_bars(engine.tick_data, "5m")
    engine.bar_data["15m"] = ticks_to_bars(engine.tick_data, "15m")
    
    for tf in ["1m", "5m", "15m"]
        engine.current_bar_index[tf] = 1
    end
    
    @info "Bar data prepared" bars_1m=nrow(engine.bar_data["1m"]) bars_5m=nrow(engine.bar_data["5m"]) bars_15m=nrow(engine.bar_data["15m"])
    
    # 创建组件
    engine.broker = BacktestBroker(engine.initial_capital)
    engine.position_manager = PositionManager()
    engine.signal_generator = SignalGenerator(engine.config, engine.bar_data)
    engine.main_grid_manager = MainGridManager(engine.config)
    engine.hedge_grid_manager = HedgeGridManager(engine.config)
    
    # 记录初始权益
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
    @info "Time range" start=engine.tick_data[1, :timestamp] finish=engine.tick_data[end, :timestamp]
    @info "Ticks to process" count=nrow(engine.tick_data)
    
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
        
        # 获取trade_id
        trade_id = if hasproperty(row, :trade_id)
            row.trade_id
        elseif hasproperty(row, :agg_trade_id)
            row.agg_trade_id
        else
            idx
        end
        
        # 创建Tick事件
        tick_event = TickEvent(
            row.timestamp,
            engine.symbol,
            row.price,
            row.quantity,
            row.is_buyer_maker,
            trade_id
        )
        
        # 处理Tick
        process_tick!(engine, tick_event)
        
        # 处理事件队列
        while !isempty(engine.event_queue)
            event = get!(engine.event_queue)
            process_event!(engine, event)
            engine.events_processed += 1
        end
        
        # 更新权益曲线（每1000个tick）
        if idx % 1000 == 0
            update_equity_curve!(engine)
            next!(progress, step=1000)
        end
        
        engine.ticks_processed += 1
    end
    
    finish!(progress)
    
    # 最后更新
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
    
    # 更新broker价格
    update_price!(engine.broker, tick.symbol, tick.price)
    
    # 更新持仓
    update_price!(engine.position_manager, tick.symbol, tick.price, tick.timestamp)
    
    # 更新主网格盈亏
    if has_active_grid(engine.main_grid_manager, tick.symbol)
        grid = get_active_grid(engine.main_grid_manager, tick.symbol)
        update_grid_pnl!(grid, tick.price)
    end
    
    # 更新对冲网格盈亏
    if has_active_hedge(engine.hedge_grid_manager, tick.symbol)
        hedge = get_active_hedge(engine.hedge_grid_manager, tick.symbol)
        update_hedge_pnl!(hedge, tick.price)
    end
    
    # 检查K线更新（生成信号）
    check_bar_updates!(engine, tick)
    
    # 检查网格触发
    check_grid_triggers!(engine, tick)
    
    # 检查对冲触发
    check_hedge_activation!(engine, tick)
    
    # 检查止盈
    check_take_profit!(engine, tick)
end

# ============================================================================
# K线更新
# ============================================================================

"""
    check_bar_updates!(engine::BacktestEngine, tick::TickEvent)

检查K线更新并生成信号
"""
function check_bar_updates!(engine::BacktestEngine, tick::TickEvent)
    
    # 只在15分钟K线完成时生成信号
    timeframe = "15m"
    
    if !should_update_bar(engine, tick.timestamp, timeframe)
        return
    end
    
    idx = engine.current_bar_index[timeframe]
    bars = engine.bar_data[timeframe]
    
    if idx > nrow(bars)
        return
    end
    
    bar = bars[idx, :]
    
    # 创建Bar事件
    bar_event = (
        timestamp = bar.timestamp,
        symbol = tick.symbol,
        timeframe = timeframe,
        open = bar.open,
        high = bar.high,
        low = bar.low,
        close = bar.close,
        volume = bar.volume
    )
    
    # 生成信号
    signal = generate_signal(engine.signal_generator, bar_event, tick.timestamp)
    
    if !isnothing(signal)
        # 包装为SignalEvent
        signal_event = wrap_signal_event(signal)
        put!(engine.event_queue, signal_event)
        engine.signals_generated += 1
    end
    
    # 移动到下一根K线
    engine.current_bar_index[timeframe] += 1
end

"""
    should_update_bar(engine::BacktestEngine, timestamp::DateTime, timeframe::String)::Bool

判断是否应该更新K线
"""
function should_update_bar(engine::BacktestEngine, timestamp::DateTime, timeframe::String)::Bool
    
    idx = engine.current_bar_index[timeframe]
    bars = engine.bar_data[timeframe]
    
    if idx > nrow(bars)
        return false
    end
    
    bar_time = bars[idx, :timestamp]
    
    # 当tick时间超过K线时间时触发
    return timestamp >= bar_time
end

# ============================================================================
# 网格触发
# ============================================================================

"""
    check_grid_triggers!(engine::BacktestEngine, tick::TickEvent)

检查网格触发
"""
function check_grid_triggers!(engine::BacktestEngine, tick::TickEvent)
    
    # 主网格
    if has_active_grid(engine.main_grid_manager, tick.symbol)
        triggers = check_price_triggers(
            engine.main_grid_manager,
            tick.symbol,
            tick.price,
            tick.timestamp
        )
        
        for trigger in triggers
            # 包装为GridTriggerEvent
            trigger_event = wrap_grid_trigger_event(trigger)
            put!(engine.event_queue, trigger_event)
        end
    end
    
    # 对冲网格
    if has_active_hedge(engine.hedge_grid_manager, tick.symbol)
        triggers = check_hedge_triggers(
            engine.hedge_grid_manager,
            tick.symbol,
            tick.price,
            tick.timestamp
        )
        
        for trigger in triggers
            # 包装为GridTriggerEvent
            trigger_event = wrap_grid_trigger_event(trigger)
            put!(engine.event_queue, trigger_event)
        end
    end
end

# ============================================================================
# 对冲检查
# ============================================================================

"""
    check_hedge_activation!(engine::BacktestEngine, tick::TickEvent)

检查是否应该启动对冲
"""
function check_hedge_activation!(engine::BacktestEngine, tick::TickEvent)
    
    # 获取主仓位
    position = get_position_record(engine.position_manager, tick.symbol, false)
    
    if isnothing(position) || position.size == 0
        return
    end
    
    # 检查对冲触发
    hedge_event = should_activate_hedge(
        engine.hedge_grid_manager,
        position,
        tick.price,
        tick.timestamp,
        engine.config
    )
    
    if !isnothing(hedge_event)
        # 包装为HedgeTriggerEvent
        hedge_trigger = wrap_hedge_trigger_event(hedge_event)
        put!(engine.event_queue, hedge_trigger)
    end
end

# ============================================================================
# 止盈检查
# ============================================================================

"""
    check_take_profit!(engine::BacktestEngine, tick::TickEvent)

检查止盈
"""
function check_take_profit!(engine::BacktestEngine, tick::TickEvent)
    
    # 主网格止盈
    if has_active_grid(engine.main_grid_manager, tick.symbol)
        tp_event = check_take_profit(
            engine.main_grid_manager,
            tick.symbol,
            tick.price,
            tick.timestamp
        )
        
        if !isnothing(tp_event)
            # 包装为TakeProfitEvent
            tp = wrap_take_profit_event(tp_event)
            put!(engine.event_queue, tp)
        end
    end
    
    # 对冲网格利润回收（不需要事件，直接处理）
    if has_active_hedge(engine.hedge_grid_manager, tick.symbol)
        hedge = get_active_hedge(engine.hedge_grid_manager, tick.symbol)
        recycle_event = check_hedge_profit_taking(
            engine.hedge_grid_manager,
            hedge,
            tick.price
        )
        
        if !isnothing(recycle_event)
            # 处理利润回收
            recycle_hedge_profit!(
                engine.hedge_grid_manager,
                tick.symbol,
                recycle_event.recycle_amount
            )
        end
    end
end

# ============================================================================
# 事件处理
# ============================================================================

"""
    process_event!(engine::BacktestEngine, event)

处理事件
"""
function process_event!(engine::BacktestEngine, event)
    
    # 根据事件类型分发
    if isa(event, SignalEvent)
        handle_signal!(engine, event)
        
    elseif isa(event, GridTriggerEvent)
        handle_grid_trigger!(engine, event)
        
    elseif isa(event, HedgeTriggerEvent)
        handle_hedge_trigger!(engine, event)
        
    elseif isa(event, TakeProfitEvent)
        handle_take_profit!(engine, event)
    end
end

"""
    handle_signal!(engine::BacktestEngine, signal::SignalEvent)

处理信号事件
"""
function handle_signal!(engine::BacktestEngine, signal::SignalEvent)
    
    @info "Signal received" type=signal.signal_type strength=signal.strength
    
    # 检查是否已有活跃网格
    if has_active_grid(engine.main_grid_manager, signal.symbol)
        @debug "Grid already active, skipping signal"
        return
    end
    
    # 获取当前价格
    current_price = get_current_price(engine.broker, signal.symbol)
    
    # 将SignalEvent转换为NamedTuple（供grid manager使用）
    signal_tuple = (
        timestamp = signal.timestamp,
        symbol = signal.symbol,
        signal_type = signal.signal_type,
        strength = signal.strength,
        grid_spacing = signal.grid_spacing,
        max_levels = signal.max_levels,
        ddown_factor = signal.ddown_factor,
        indicators = signal.indicators
    )
    
    # 初始化网格
    grid = initialize_grid!(
        engine.main_grid_manager,
        signal_tuple,
        current_price
    )
    
    if !isnothing(grid)
        # 立即下第一层订单（市价单）
        place_initial_order!(engine, grid, current_price)
    end
end

"""
    place_initial_order!(engine::BacktestEngine, grid, current_price::Float64)

下初始订单
"""
function place_initial_order!(engine::BacktestEngine, grid, current_price::Float64)
    
    # 第一层使用市价单立即成交
    side = grid.side == :LONG ? :BUY : :SELL
    quantity = grid.levels[1].quantity
    
    order = (
        timestamp = engine.current_time,
        symbol = grid.symbol,
        side = side,
        order_type = :MARKET,
        quantity = quantity,
        price = nothing,
        reduce_only = false,
        post_only = false,
        grid_level = 1,
        is_hedge = false,
        client_order_id = "grid_$(grid.symbol)_L1"
    )
    
    # 立即执行
    fill = execute_order(engine.broker, order, engine.current_time)
    
    if !isnothing(fill)
        # 处理成交
        on_fill!(engine.position_manager, fill)
        on_grid_fill!(engine.main_grid_manager, fill)
        
        log_trade!(engine, fill)
        engine.trades_executed += 1
    end
end

"""
    handle_grid_trigger!(engine::BacktestEngine, trigger::GridTriggerEvent)

处理网格触发
"""
function handle_grid_trigger!(engine::BacktestEngine, trigger::GridTriggerEvent)
    
    # 创建限价单
    is_hedge = trigger.is_hedge
    
    side = if is_hedge
        hedge = get_active_hedge(engine.hedge_grid_manager, trigger.symbol)
        hedge.side == :LONG ? :BUY : :SELL
    else
        grid = get_active_grid(engine.main_grid_manager, trigger.symbol)
        grid.side == :LONG ? :BUY : :SELL
    end
    
    order = (
        timestamp = trigger.timestamp,
        symbol = trigger.symbol,
        side = side,
        order_type = :LIMIT,
        quantity = trigger.order_quantity,
        price = trigger.trigger_price,
        reduce_only = false,
        post_only = true,
        grid_level = trigger.grid_level,
        is_hedge = is_hedge,
        client_order_id = "grid_$(trigger.symbol)_L$(trigger.grid_level)"
    )
    
    # 执行订单
    fill = execute_order(engine.broker, order, trigger.timestamp)
    
    if !isnothing(fill)
        # 处理成交
        on_fill!(engine.position_manager, fill)
        
        if is_hedge
            on_hedge_fill!(engine.hedge_grid_manager, fill)
        else
            on_grid_fill!(engine.main_grid_manager, fill)
        end
        
        log_trade!(engine, fill)
        engine.trades_executed += 1
    end
end

"""
    handle_hedge_trigger!(engine::BacktestEngine, trigger::HedgeTriggerEvent)

处理对冲触发
"""
function handle_hedge_trigger!(engine::BacktestEngine, trigger::HedgeTriggerEvent)
    
    @info "Activating hedge" symbol=trigger.symbol reason=trigger.reason
    
    current_price = get_current_price(engine.broker, trigger.symbol)
    
    # 转换为NamedTuple
    trigger_tuple = (
        timestamp = trigger.timestamp,
        symbol = trigger.symbol,
        reason = trigger.reason,
        main_position_size = trigger.main_position_size,
        main_avg_entry = trigger.main_avg_entry,
        current_price = trigger.current_price,
        unrealized_pnl = trigger.unrealized_pnl,
        unrealized_pnl_pct = trigger.unrealized_pnl_pct,
        hedge_ratio = trigger.hedge_ratio,
        hedge_grid_spacing = trigger.hedge_grid_spacing
    )
    
    # 初始化对冲网格
    hedge = initialize_hedge_grid!(
        engine.hedge_grid_manager,
        trigger_tuple,
        current_price
    )
end

"""
    handle_take_profit!(engine::BacktestEngine, tp::TakeProfitEvent)

处理止盈
"""
function handle_take_profit!(engine::BacktestEngine, tp::TakeProfitEvent)
    
    @info "Take profit triggered" symbol=tp.symbol level=tp.tp_level profit=tp.profit_amount
    
    # 获取网格
    grid = get_active_grid(engine.main_grid_manager, tp.symbol)
    
    if isnothing(grid)
        return
    end
    
    # 平仓方向相反
    side = grid.side == :LONG ? :SELL : :BUY
    
    order = (
        timestamp = tp.timestamp,
        symbol = tp.symbol,
        side = side,
        order_type = :LIMIT,
        quantity = tp.close_quantity,
        price = tp.tp_price,
        reduce_only = true,
        post_only = false,
        grid_level = nothing,
        is_hedge = false,
        client_order_id = "tp_$(tp.symbol)_$(tp.tp_level)"
    )
    
    # 执行订单
    fill = execute_order(engine.broker, order, tp.timestamp)
    
    if !isnothing(fill)
        on_fill!(engine.position_manager, fill)
        log_trade!(engine, fill)
        engine.trades_executed += 1
    end
end

# ============================================================================
# 辅助函数
# ============================================================================

"""
    update_equity_curve!(engine::BacktestEngine)

更新权益曲线
"""
function update_equity_curve!(engine::BacktestEngine)
    
    unrealized_pnl = get_total_unrealized_pnl(engine.position_manager)
    
    # ✅ 同时更新broker权益
    update_equity!(engine.broker, unrealized_pnl)
    
    current_equity = engine.broker.balance + unrealized_pnl
    
    push!(engine.equity_curve, (engine.current_time, current_equity))
end

"""
    log_trade!(engine::BacktestEngine, fill)

记录交易
"""
function log_trade!(engine::BacktestEngine, fill)
    
    trade = Dict(
        "timestamp" => fill.timestamp,
        "symbol" => fill.symbol,
        "side" => fill.side,
        "quantity" => fill.quantity,
        "price" => fill.fill_price,
        "commission" => fill.commission,
        "is_hedge" => get(fill, :is_hedge, false),
        "grid_level" => get(fill, :grid_level, nothing)
    )
    
    push!(engine.trade_log, trade)
end

# ============================================================================
# 性能分析
# ============================================================================

"""
    analyze_performance(engine::BacktestEngine)::Dict

分析回测性能
"""
function analyze_performance(engine::BacktestEngine)::Dict
    
    if isempty(engine.equity_curve)
        return Dict()
    end
    
    # 提取权益数据
    times = [t[1] for t in engine.equity_curve]
    equities = [t[2] for t in engine.equity_curve]
    
    # 基本统计
    final_equity = equities[end]
    total_return = final_equity - engine.initial_capital
    total_return_pct = (total_return / engine.initial_capital) * 100
    
    # 最大回撤
    peak = engine.initial_capital
    max_dd = 0.0
    max_dd_pct = 0.0
    
    for equity in equities
        if equity > peak
            peak = equity
        end
        
        dd = peak - equity
        dd_pct = (dd / peak) * 100
        
        if dd > max_dd
            max_dd = dd
            max_dd_pct = dd_pct
        end
    end
    
    # 交易统计
    total_trades = length(engine.trade_log)
    
    # 持仓统计
    pos_summary = get_position_summary(engine.position_manager)
    
    # 时间
    start_time = times[1]
    end_time = times[end]
    duration = end_time - start_time
    
    return Dict(
        "initial_capital" => engine.initial_capital,
        "final_equity" => final_equity,
        "total_return" => total_return,
        "total_return_pct" => total_return_pct,
        "max_drawdown" => max_dd,
        "max_drawdown_pct" => max_dd_pct,
        "total_trades" => total_trades,
        "winning_trades" => pos_summary["winning_trades"],
        "losing_trades" => pos_summary["losing_trades"],
        "win_rate" => pos_summary["win_rate"],
        "total_fees" => engine.broker.total_fees_paid,
        "signals_generated" => engine.signals_generated,
        "ticks_processed" => engine.ticks_processed,
        "events_processed" => engine.events_processed,
        "start_time" => start_time,
        "end_time" => end_time,
        "duration" => duration
    )
end

"""
    print_performance_report(engine::BacktestEngine)

打印性能报告
"""
function print_performance_report(engine::BacktestEngine)
    
    perf = analyze_performance(engine)
    
    if isempty(perf)
        println("No performance data available")
        return
    end
    
    println("\n" * "="^70)
    println("回测性能报告")
    println("="^70)
    
    println("\n📅 时间:")
    println("  开始: $(perf["start_time"])")
    println("  结束: $(perf["end_time"])")
    println("  时长: $(perf["duration"])")
    
    println("\n💰 资金:")
    println("  初始资金: \$$(round(perf["initial_capital"], digits=2))")
    println("  最终权益: \$$(round(perf["final_equity"], digits=2))")
    
    return_indicator = perf["total_return"] >= 0 ? "🟢" : "🔴"
    println("  总收益: $return_indicator \$$(round(perf["total_return"], digits=2)) ($(round(perf["total_return_pct"], digits=2))%)")
    
    println("  最大回撤: \$$(round(perf["max_drawdown"], digits=2)) ($(round(perf["max_drawdown_pct"], digits=2))%)")
    
    println("\n📊 交易:")
    println("  总交易数: $(perf["total_trades"])")
    println("  盈利交易: $(perf["winning_trades"])")
    println("  亏损交易: $(perf["losing_trades"])")
    println("  胜率: $(round(perf["win_rate"], digits=1))%")
    println("  总手续费: \$$(round(perf["total_fees"], digits=2))")
    
    println("\n📈 信号:")
    println("  生成信号: $(perf["signals_generated"])")
    
    println("\n⚙️  处理:")
    println("  处理Tick数: $(perf["ticks_processed"])")
    println("  处理事件数: $(perf["events_processed"])")
    
    println("="^70)
end

# ============================================================================
# 缺失的辅助函数
# ============================================================================

"""
    get_position_summary(pm::PositionManager)::Dict

获取持仓总结
"""
function get_position_summary(pm::PositionManager)::Dict
    
    total_trades = pm.total_trades
    winning = pm.winning_trades
    losing = pm.losing_trades
    
    win_rate = total_trades > 0 ? (winning / total_trades) * 100 : 0.0
    
    return Dict(
        "total_trades" => total_trades,
        "winning_trades" => winning,
        "losing_trades" => losing,
        "win_rate" => win_rate,
        "total_realized_pnl" => pm.total_realized_pnl,
        "total_fees" => pm.total_fees
    )
end

"""
    print_positions(pm::PositionManager)

打印所有持仓
"""
function print_positions(pm::PositionManager)
    
    all_positions = get_all_positions(pm)
    
    if isempty(all_positions)
        println("\n当前无持仓")
        return
    end
    
    println("\n" * "="^70)
    println("当前持仓")
    println("="^70)
    
    for pos in all_positions
        side_str = pos.side == :BUY ? "做多" : "做空"
        pnl_indicator = pos.unrealized_pnl >= 0 ? "🟢" : "🔴"
        
        println("\n$(pos.symbol) ($side_str):")
        println("  数量: $(round(pos.size, digits=4))")
        println("  入场价: \$$(round(pos.entry_price, digits=2))")
        println("  浮盈: $pnl_indicator \$$(round(pos.unrealized_pnl, digits=2))")
    end
    
    println("="^70)
end