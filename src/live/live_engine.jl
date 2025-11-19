# src/live/live_engine.jl

"""
实盘交易引擎（监控模式）
"""

using Dates
using Logging

include("websocket_client.jl")
include("live_broker.jl")
include("../config/config_loader.jl")

# ============================================================================
# 实盘引擎
# ============================================================================

mutable struct LiveEngine
    config::Dict
    symbol::Symbol
    ws_client::BinanceWebSocket
    broker::LiveBroker
    tick_buffer::Vector{NamedTuple}
    kline_buffer::Dict{String, Vector{NamedTuple}}
    is_running::Bool
    start_time::DateTime
    last_tick::Union{NamedTuple, Nothing}
    ticks_received::Int
    
    function LiveEngine(config_path::String)
        @info "Initializing Live Engine" config=config_path
        
        config = load_config(config_path)
        creds = get_api_credentials(config)
        symbol = Symbol(config["portfolio"]["symbol_selection"]["universe"][1])
        
        @info "Creating components" symbol=symbol testnet=creds.testnet
        
        ws_client = BinanceWebSocket(market=:futures)
        
        broker = LiveBroker(
            creds.api_key,
            creds.api_secret,
            symbol,
            market=:futures,
            testnet=creds.testnet
        )
        
        engine = new(
            config,
            symbol,
            ws_client,
            broker,
            NamedTuple[],
            Dict{String, Vector{NamedTuple}}(),
            false,
            DateTime(0),
            nothing,
            0
        )
        
        setup_callbacks!(engine)
        
        @info "Live Engine initialized successfully"
        
        return engine
    end
end

# ============================================================================
# 回调设置
# ============================================================================

function setup_callbacks!(engine::LiveEngine)
    # 设置Tick回调
    engine.ws_client.on_tick = tick -> handle_tick!(engine, tick)
    
    # 设置K线回调
    engine.ws_client.on_kline = kline -> handle_kline!(engine, kline)
    
    # ✅ 设置账户更新回调（使用正确的字段名）
    engine.ws_client.on_account = account -> handle_account_update!(engine, account)
    
    # ✅ 设置订单更新回调
    engine.ws_client.on_order = order -> handle_order_update!(engine, order)
    
    @debug "Callbacks configured"
end

# ============================================================================
# 引擎控制
# ============================================================================

function start!(engine::LiveEngine)
    @info "Starting Live Engine" symbol=engine.symbol
    
    println("\n" * "="^70)
    println("🚀 PassivbotJL Live Engine 启动")
    println("="^70)
    println("  交易对: $(engine.symbol)")
    println("  模式: $(engine.broker.order_client.base_url)")
    println("  启动时间: $(now())")
    println("="^70)
    
    println("\n📊 同步初始状态...")
    sync_positions!(engine.broker)
    sync_orders!(engine.broker)
    print_broker_stats(engine.broker)
    
    println("\n📡 订阅数据流...")
    subscribe_ticks!(engine.ws_client, string(engine.symbol))
    subscribe_klines!(engine.ws_client, string(engine.symbol), "5m")
    
    println("\n🔌 连接WebSocket...")
    start!(engine.ws_client)
    
    engine.is_running = true
    engine.start_time = now(UTC)
    
    println("\n✅ 引擎已启动（监控模式）")
    println("⚠️  自动交易功能暂未启用")
    println("按 Ctrl+C 停止\n")
    
    run_main_loop!(engine)
end

function stop!(engine::LiveEngine)
    @info "Stopping Live Engine..."
    
    println("\n" * "="^70)
    println("⏹️  停止实盘引擎")
    println("="^70)
    
    engine.is_running = false
    
    println("\n🗑️  撤销所有订单...")
    cancel_all_orders(engine.broker)
    
    println("\n🔌 断开WebSocket...")
    stop!(engine.ws_client)
    
    println("\n📊 最终状态同步...")
    sync_positions!(engine.broker)
    
    print_engine_stats(engine)
    
    println("\n✅ 引擎已安全停止")
    println("="^70)
end

# ============================================================================
# 主循环
# ============================================================================

function run_main_loop!(engine::LiveEngine)
    last_sync = now(UTC)
    last_stats = now(UTC)
    
    try
        while engine.is_running
            # 定期同步（每30秒）
            if now(UTC) - last_sync > Second(30)
                sync_positions!(engine.broker)
                sync_orders!(engine.broker)
                check_order_fills!(engine.broker)
                last_sync = now(UTC)
            end
            
            # 定期打印统计（每5分钟）
            if now(UTC) - last_stats > Minute(5)
                print_engine_stats(engine)
                last_stats = now(UTC)
            end
            
            sleep(1)
        end
    catch e
        if isa(e, InterruptException)
            @info "Received interrupt signal"
        else
            @error "Main loop error" exception=e
            rethrow(e)
        end
    finally
        stop!(engine)
    end
end

# ============================================================================
# 事件处理
# ============================================================================

function handle_tick!(engine::LiveEngine, tick::NamedTuple)
    engine.last_tick = tick
    engine.ticks_received += 1
    
    push!(engine.tick_buffer, tick)
    if length(engine.tick_buffer) > 1000
        popfirst!(engine.tick_buffer)
    end
    
    if engine.ticks_received % 100 == 0
        @info "Ticks received" count=engine.ticks_received price=tick.price
    end
end

function handle_kline!(engine::LiveEngine, kline::NamedTuple)
    if !kline.is_closed
        return
    end
    
    @info "K-line closed" time=kline.close_time close=kline.close
    
    interval = kline.interval
    if !haskey(engine.kline_buffer, interval)
        engine.kline_buffer[interval] = NamedTuple[]
    end
    
    push!(engine.kline_buffer[interval], kline)
    if length(engine.kline_buffer[interval]) > 100
        popfirst!(engine.kline_buffer[interval])
    end
end

function handle_account_update!(engine::LiveEngine, account::Any)
    @info "Account update received"
    
    # 同步持仓
    sync_positions!(engine.broker)
end

function handle_order_update!(engine::LiveEngine, order::Any)
    @info "Order update received"
    
    # 同步订单状态
    sync_orders!(engine.broker)
    check_order_fills!(engine.broker)
end

# ============================================================================
# 统计与报告
# ============================================================================

function print_engine_stats(engine::LiveEngine)
    uptime = now(UTC) - engine.start_time
    
    println("\n" * "="^70)
    println("📊 实盘引擎统计")
    println("="^70)
    println("  运行时间: $(uptime)")
    println("  交易对: $(engine.symbol)")
    println()
    println("  数据统计:")
    println("    Tick接收: $(engine.ticks_received)")
    println("    K线缓存: $(length(get(engine.kline_buffer, "5m", [])))")
    
    if !isnothing(engine.last_tick)
        println("    最新价格: \$$(engine.last_tick.price)")
    end
    println()
    
    print_broker_stats(engine.broker)
end