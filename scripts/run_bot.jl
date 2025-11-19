#!/usr/bin/env julia

# scripts/run_bot.jl

"""
PassivbotJL 主启动脚本

用法：
    julia --project=. scripts/run_bot.jl [config_file]

参数：
    config_file: 配置文件路径（可选，默认为 config/strategy.yaml）
"""

using PassivbotJL
using Dates
using Logging

# ============================================================================
# 信号处理
# ============================================================================

# 全局引擎引用
global_engine = nothing

"""
    signal_handler(signal)

处理系统信号（Ctrl+C等）
"""
function signal_handler(signal)
    @warn "Received signal: $signal"
    
    if !isnothing(global_engine)
        @info "Initiating graceful shutdown..."
        stop(global_engine)
    else
        @info "No active engine, exiting..."
        exit(0)
    end
end

# 注册信号处理器
if Sys.isunix()
    # Unix系统（Linux/Mac）
    ccall(:signal, Ptr{Cvoid}, (Cint, Ptr{Cvoid}), 2, @cfunction(signal_handler, Cvoid, (Cint,)))  # SIGINT
    ccall(:signal, Ptr{Cvoid}, (Cint, Ptr{Cvoid}), 15, @cfunction(signal_handler, Cvoid, (Cint,))) # SIGTERM
end

# ============================================================================
# 主函数
# ============================================================================

function main()
    
    # 打印启动横幅
    println("\n" * "="^70)
    println("""
    ╔════════════════════════════════════════════════════════════╗
    ║                   PassivbotJL v0.1.0                       ║
    ║          Trend Following Martingale Grid System            ║
    ║                                                            ║
    ║  🚀 Production Mode                                        ║
    ╚════════════════════════════════════════════════════════════╝
    """)
    println("="^70)
    
    # ========================================================================
    # 1. 加载配置
    # ========================================================================
    
    config_file = if length(ARGS) >= 1
        ARGS[1]
    else
        "config/strategy.yaml"
    end
    
    @info "Loading configuration from: $config_file"
    
    config = try
        load_config(config_file)
    catch e
        @error "Failed to load configuration" exception=e
        exit(1)
    end
    
    # 打印配置摘要
    print_config_summary(config)
    
    # ========================================================================
    # 2. 安全检查
    # ========================================================================
    
    println("\n" * "="^70)
    println("⚠️  SAFETY CHECKS")
    println("="^70)
    
    # 检查是否为测试网
    if config.exchange.testnet
        println("✅ Running on TESTNET")
    else
        println("⚠️  WARNING: Running on MAINNET (REAL MONEY!)")
        
        # 要求用户确认
        print("\nType 'YES' to confirm you want to run on mainnet: ")
        confirmation = readline()
        
        if confirmation != "YES"
            @warn "Mainnet operation not confirmed. Exiting."
            exit(0)
        end
        
        println("\n⚠️  MAINNET MODE CONFIRMED")
    end
    
    # 检查API密钥
    if isempty(config.exchange.api_key) || isempty(config.exchange.api_secret)
        @error "API credentials not configured"
        println("\nPlease set environment variables:")
        println("  export EXCHANGE_API_KEY=\"your_api_key\"")
        println("  export EXCHANGE_API_SECRET=\"your_api_secret\"")
        exit(1)
    end
    
    println("\n✅ API credentials configured")
    
    # ========================================================================
    # 3. 创建交易所连接
    # ========================================================================
    
    @info "Connecting to exchange..."
    
    exchange = try
        BinanceFutures(config.exchange)
    catch e
        @error "Failed to connect to exchange" exception=e
        exit(1)
    end
    
    # 测试连接
    try
        server_time = get_server_time(exchange)
        @info "Exchange connection successful" server_time=server_time
    catch e
        @error "Exchange connection test failed" exception=e
        exit(1)
    end
    
    # 获取账户信息
    try
        balance = get_account_balance(exchange)
        account_info = get_account_info(exchange)
        
        println("\n" * "="^70)
        println("📊 ACCOUNT STATUS")
        println("="^70)
        println("Total Balance: \$$(round(balance.balance, digits=2))")
        println("Available: \$$(round(balance.available, digits=2))")
        println("Unrealized PNL: \$$(round(balance.cross_unrealized_pnl, digits=2))")
        println("Can Trade: $(account_info.can_trade)")
        println("="^70)
        
        if !account_info.can_trade
            @error "Trading is not enabled on this account"
            exit(1)
        end
        
        if balance.available < 10.0
            @warn "Low available balance: \$$(balance.available)"
            
            if !config.exchange.testnet
                @error "Insufficient funds for mainnet trading"
                exit(1)
            end
        end
        
    catch e
        @error "Failed to get account information" exception=e
        exit(1)
    end
    
    # ========================================================================
    # 4. 创建交易引擎
    # ========================================================================
    
    @info "Initializing trading engine..."
    
    global global_engine = TradingEngine(config, exchange)
    
    println("\n" * "="^70)
    println("🤖 ENGINE CONFIGURATION")
    println("="^70)
    println("Loop Interval: $(config.loop_interval_seconds) seconds")
    println("Max Symbols: $(config.portfolio.max_symbols)")
    println("Symbol Universe: $(config.portfolio.symbol_universe)")
    println("Long Trading: $(config.long.enabled ? "✅" : "❌")")
    println("Short Trading: $(config.short.enabled ? "✅" : "❌")")
    println("="^70)
    
    # ========================================================================
    # 5. 最后确认
    # ========================================================================
    
    println("\n" * "="^70)
    println("🚀 READY TO START")
    println("="^70)
    println("Press Ctrl+C to stop the bot gracefully")
    println()
    
    if !config.exchange.testnet
        print("Type 'START' to begin trading: ")
        start_confirmation = readline()
        
        if start_confirmation != "START"
            @warn "Start not confirmed. Exiting."
            exit(0)
        end
    end
    
    # ========================================================================
    # 6. 启动引擎
    # ========================================================================
    
    @info "🚀 Starting trading engine..."
    println()
    
    try
        start_engine(global_engine)
    catch e
        if isa(e, InterruptException)
            @info "Received interrupt signal"
        else
            @error "Engine crashed" exception=(e, catch_backtrace())
        end
    end
    
    @info "Bot stopped"
end

# ============================================================================
# 运行
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end