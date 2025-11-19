# src/execution/trading_engine.jl

"""
交易引擎

整合市场分析、网格管理、订单执行的核心引擎
"""

using Dates

# ============================================================================
# 交易引擎
# ============================================================================

"""
    TradingEngine

主交易引擎
"""
mutable struct TradingEngine
    # 配置
    config::StrategyConfig
    
    # 组件
    exchange::AbstractExchange
    executor::OrderExecutor
    
    # 活跃网格
    active_grids::Dict{Symbol, MartingaleGrid}
    
    # 状态
    is_running::Bool
    last_update::DateTime
    
    # 统计
    total_trades::Int
    total_pnl::Float64
    
    function TradingEngine(config::StrategyConfig, exchange::AbstractExchange)
        executor = OrderExecutor(exchange, config.exchange.max_retries)
        
        new(
            config,
            exchange,
            executor,
            Dict{Symbol, MartingaleGrid}(),
            false,
            now(),
            0,
            0.0
        )
    end
end

# ============================================================================
# 主循环
# ============================================================================

"""
    start_engine(engine::TradingEngine; max_iterations::Union{Int, Nothing}=nothing)

启动交易引擎主循环

参数：
- max_iterations: 最大迭代次数（用于测试），nothing表示无限循环
"""
function start_engine(engine::TradingEngine; max_iterations::Union{Int, Nothing}=nothing)
    
    @info "🚀 Trading engine starting..."
    @info "Loop interval: $(engine.config.loop_interval_seconds) seconds"
    
    engine.is_running = true
    iteration = 0
    
    try
        while engine.is_running
            iteration += 1
            
            if !isnothing(max_iterations) && iteration > max_iterations
                @info "Max iterations reached, stopping..."
                break
            end
            
            @info "="^70
            @info "Iteration #$iteration - $(now())"
            @info "="^70
            
            # 执行主循环
            try
                main_loop_iteration(engine)
            catch e
                @error "Error in main loop iteration" exception=(e, catch_backtrace())
            end
            
            # 更新时间戳
            engine.last_update = now()
            
            # 休眠
            @debug "Sleeping for $(engine.config.loop_interval_seconds) seconds..."
            sleep(engine.config.loop_interval_seconds)
        end
        
    catch e
        @error "Trading engine crashed" exception=(e, catch_backtrace())
        engine.is_running = false
    finally
        @info "Trading engine stopped"
        cleanup(engine)
    end
end

"""
    main_loop_iteration(engine::TradingEngine)

主循环的一次迭代
"""
function main_loop_iteration(engine::TradingEngine)
    
    # ========================================================================
    # 1. 更新挂单状态
    # ========================================================================
    
    @debug "Updating pending orders..."
    update_pending_orders(engine.executor)
    
    # ========================================================================
    # 2. 检查现有网格
    # ========================================================================
    
    @debug "Checking existing grids..."
    manage_existing_grids(engine)
    
    # ========================================================================
    # 3. 寻找新的交易机会
    # ========================================================================
    
    @debug "Scanning for new opportunities..."
    scan_for_opportunities(engine)
    
    # ========================================================================
    # 4. 风险管理
    # ========================================================================
    
    @debug "Performing risk checks..."
    perform_risk_checks(engine)
    
    # ========================================================================
    # 5. 打印状态
    # ========================================================================
    
    print_engine_status(engine)
end

# ============================================================================
# 网格管理
# ============================================================================

"""
    manage_existing_grids(engine::TradingEngine)

管理现有网格
"""
function manage_existing_grids(engine::TradingEngine)
    
    if isempty(engine.active_grids)
        @debug "No active grids"
        return
    end
    
    for (symbol, grid) in engine.active_grids
        try
            # 获取当前价格
            current_price = get_ticker_price(engine.exchange, symbol)
            
            # 获取账户余额
            balance = get_account_balance(engine.exchange)
            account_balance = balance.balance
            
            # 更新网格指标
            update_grid_metrics(grid, current_price, account_balance)
            
            # 检查健康状态
            health = check_grid_health(
                grid,
                current_price,
                grid.side == LONG ? engine.config.long.risk : engine.config.short.risk
            )
            
            # 如果需要关闭
            if health.should_close
                @warn "Grid requires closure" symbol=symbol warnings=health.warnings
                close_grid(engine, symbol, "Risk threshold exceeded")
                continue
            end
            
            # 检查是否需要添加新层级
            if should_add_grid_level(
                grid,
                current_price,
                grid.side == LONG ? engine.config.long.grid : engine.config.short.grid
            )
                add_new_grid_level(engine, grid, current_price)
            end
            
            # 更新止盈订单（如果价格变化大）
            update_take_profit_orders(engine, grid, current_price)
            
        catch e
            @error "Error managing grid" symbol=symbol error=e
        end
    end
end

"""
    add_new_grid_level(engine::TradingEngine, grid::MartingaleGrid, current_price::Float64)

添加新的网格层级
"""
function add_new_grid_level(engine::TradingEngine, grid::MartingaleGrid, current_price::Float64)
    
    @info "Adding new grid level" symbol=grid.symbol
    
    # 计算基础数量（根据配置）
    config = grid.side == LONG ? engine.config.long : engine.config.short
    
    # 简化：使用固定基础数量
    base_quantity = 0.001  # 需要根据实际资金和风险计算
    
    # 添加层级
    new_level = add_grid_entry(grid, current_price, base_quantity, current_price)
    
    if !isnothing(new_level)
        # 执行订单
        result = execute_limit_order(
            engine.executor,
            grid.symbol,
            grid.side,
            new_level.price,
            new_level.quantity
        )
        
        if result.success
            @info "Grid level order placed" order_id=result.order_id
        else
            @error "Failed to place grid level order" error=result.error_message
        end
    end
end

"""
    update_take_profit_orders(engine::TradingEngine, grid::MartingaleGrid, current_price::Float64)

更新止盈订单
"""
function update_take_profit_orders(engine::TradingEngine, grid::MartingaleGrid, current_price::Float64)
    
    # 简化：只在平均入场价变化超过一定幅度时更新
    # 实际实现中需要更复杂的逻辑
    
    @debug "Take profit orders update check" symbol=grid.symbol
end

# ============================================================================
# 机会扫描
# ============================================================================

"""
    scan_for_opportunities(engine::TradingEngine)

扫描新的交易机会
"""
function scan_for_opportunities(engine::TradingEngine)
    
    # 检查是否已达到最大交易对数量
    if length(engine.active_grids) >= engine.config.portfolio.max_symbols
        @debug "Max symbols reached, skipping scan"
        return
    end
    
    # 从配置的交易对池中选择
    available_symbols = filter(
        sym -> !haskey(engine.active_grids, sym),
        engine.config.portfolio.symbol_universe
    )
    
    if isempty(available_symbols)
        @debug "No available symbols to scan"
        return
    end
    
    # 分析每个交易对
    analyses = analyze_multiple_symbols(engine.exchange, available_symbols, engine.config)
    
    # 找出交易机会
    opportunities = find_trading_opportunities(analyses, 0.6)  # 最小信号强度60%
    
    if isempty(opportunities)
        @debug "No trading opportunities found"
        return
    end
    
    # 选择最佳机会
    for symbol in opportunities
        if length(engine.active_grids) >= engine.config.portfolio.max_symbols
            break
        end
        
        analysis = analyses[symbol]
        
        # 创建新网格
        try
            create_new_grid(engine, symbol, analysis)
        catch e
            @error "Failed to create grid" symbol=symbol error=e
        end
    end
end

"""
    create_new_grid(engine::TradingEngine, symbol::Symbol, analysis::MarketAnalysis)

创建新网格
"""
function create_new_grid(engine::TradingEngine, symbol::Symbol, analysis::MarketAnalysis)
    
    @info "Creating new grid" symbol=symbol side=analysis.recommended_side
    
    # 获取账户余额
    balance = get_account_balance(engine.exchange)
    available_capital = balance.available
    
    # 选择配置
    config = if analysis.recommended_side == LONG
        engine.config.long
    else
        engine.config.short
    end
    
    # 设置杠杆
    set_leverage(engine.exchange, symbol, config.leverage)
    
    # 创建网格
    grid = create_martingale_grid(
        symbol,
        analysis.recommended_side,
        analysis.cci_signal,
        analysis.trend,
        analysis.volatility,
        config,
        available_capital
    )
    
    # 添加初始入场层级
    current_price = analysis.current_price
    base_quantity = 0.001  # 简化，需要根据风险计算
    
    # 添加第一层
    first_level = add_grid_entry(grid, current_price, base_quantity, current_price)
    
    if !isnothing(first_level)
        # 执行订单
        result = execute_limit_order(
            engine.executor,
            symbol,
            analysis.recommended_side,
            first_level.price,
            first_level.quantity
        )
        
        if result.success
            # 保存网格
            engine.active_grids[symbol] = grid
            @info "Grid created and first order placed" symbol=symbol order_id=result.order_id
        else
            @error "Failed to place first grid order" error=result.error_message
        end
    end
end

# ============================================================================
# 风险管理
# ============================================================================

"""
    perform_risk_checks(engine::TradingEngine)

执行风险检查
"""
function perform_risk_checks(engine::TradingEngine)
    
    # 获取账户信息
    try
        account_info = get_account_info(engine.exchange)
        
        # 检查总敞口
        total_exposure = 0.0
        for (symbol, grid) in engine.active_grids
            total_exposure += grid.wallet_exposure
        end
        
        # 检查是否超过限制
        max_exposure = engine.config.long.wallet_exposure_limit + 
                      engine.config.short.wallet_exposure_limit
        
        if total_exposure > max_exposure
            @warn "Total exposure exceeds limit" current=total_exposure limit=max_exposure
            # 可以选择关闭部分仓位
        end
        
        # 检查账户余额
        if account_info.available_balance < account_info.total_wallet_balance * 0.1
            @warn "Low available balance" available=account_info.available_balance
        end
        
    catch e
        @error "Risk check failed" error=e
    end
end

# ============================================================================
# 网格关闭
# ============================================================================

"""
    close_grid(engine::TradingEngine, symbol::Symbol, reason::String)

关闭网格
"""
function close_grid(engine::TradingEngine, symbol::Symbol, reason::String)
    
    @info "Closing grid" symbol=symbol reason=reason
    
    if !haskey(engine.active_grids, symbol)
        @warn "Grid not found" symbol=symbol
        return
    end
    
    grid = engine.active_grids[symbol]
    
    # 取消所有挂单
    cancel_all_pending_orders(engine.executor, symbol)
    
    # 如果有持仓，平仓
    if grid.total_quantity > 0.0
        result = emergency_close_position(
            engine.executor,
            symbol,
            grid.total_quantity,
            grid.side
        )
        
        if result.success
            # 记录盈亏
            engine.total_pnl += grid.unrealized_pnl
            engine.total_trades += 1
            
            @info "Grid closed" symbol=symbol pnl=grid.unrealized_pnl
        else
            @error "Failed to close grid position" symbol=symbol
        end
    end
    
    # 从活跃网格中移除
    delete!(engine.active_grids, symbol)
end

# ============================================================================
# 清理和关闭
# ============================================================================

"""
    cleanup(engine::TradingEngine)

清理资源
"""
function cleanup(engine::TradingEngine)
    
    @info "Cleaning up trading engine..."
    
    # 关闭所有网格
    symbols = collect(keys(engine.active_grids))
    for symbol in symbols
        close_grid(engine, symbol, "Engine shutdown")
    end
    
    # 打印最终统计
    print_final_stats(engine)
end

"""
    stop(engine::TradingEngine)

停止交易引擎
"""
function stop(engine::TradingEngine)
    @info "Stop signal received"
    engine.is_running = false
end

# ============================================================================
# 状态和统计
# ============================================================================

"""
    print_engine_status(engine::TradingEngine)

打印引擎状态
"""
function print_engine_status(engine::TradingEngine)
    
    println("\n" * "="^70)
    println("交易引擎状态")
    println("="^70)
    
    println("活跃网格: $(length(engine.active_grids))")
    println("总交易次数: $(engine.total_trades)")
    println("总盈亏: \$$(round(engine.total_pnl, digits=2))")
    
    if !isempty(engine.active_grids)
        println("\n活跃网格详情:")
        for (symbol, grid) in engine.active_grids
            pnl_pct = if grid.total_quantity > 0.0
                grid.unrealized_pnl / (grid.average_entry * grid.total_quantity) * 100
            else
                0.0
            end
            
            println("  $symbol ($(grid.side)): 盈亏 \$$(round(grid.unrealized_pnl, digits=2)) ($(round(pnl_pct, digits=1))%)")
        end
    end
    
    # 订单执行统计
    exec_stats = get_execution_stats(engine.executor)
    println("\n订单统计:")
    println("  已成交: $(exec_stats.total_filled)")
    println("  挂单中: $(exec_stats.total_pending)")
    println("  失败: $(exec_stats.total_failed)")
    
    println("="^70)
end

"""
    print_final_stats(engine::TradingEngine)

打印最终统计
"""
function print_final_stats(engine::TradingEngine)
    
    println("\n" * "="^70)
    println("最终统计")
    println("="^70)
    
    println("总交易次数: $(engine.total_trades)")
    println("总盈亏: \$$(round(engine.total_pnl, digits=2))")
    
    if engine.total_trades > 0
        avg_pnl = engine.total_pnl / engine.total_trades
        println("平均盈亏: \$$(round(avg_pnl, digits=2))")
    end
    
    print_execution_summary(engine.executor)
    
    println("="^70)
end