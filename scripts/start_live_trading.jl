# scripts/start_live_trading.jl

"""
启动实盘交易引擎

用法:
    julia --project=. scripts/start_live_trading.jl

停止:
    按 Ctrl+C
"""

using Pkg
Pkg.activate(".")

using Dates
using Logging

# 设置日志级别
global_logger(ConsoleLogger(stderr, Logging.Info))

# 加载引擎
include("../src/live/live_engine.jl")

# ============================================================================
# 主程序
# ============================================================================

function main()
    println("\n" * "="^70)
    println("🚀 PassivbotJL - 实盘交易系统")
    println("="^70)
    println("  版本: 0.1.0")
    println("  启动时间: $(now())")
    println("="^70)
    
    # 配置文件路径
    config_path = "config/strategy.yaml"
    
    if !isfile(config_path)
        println("\n❌ 配置文件不存在: $config_path")
        println("请先创建配置文件")
        exit(1)
    end
    
    println("\n📋 配置文件: $config_path")
    
    # 创建引擎
    println("\n🔧 初始化引擎...")
    
    try
        engine = LiveEngine(config_path)
        
        # 显示配置信息
        println("\n" * "="^70)
        println("配置确认")
        println("="^70)
        println("  交易对: $(engine.symbol)")
        println("  WebSocket: $(engine.ws_client.base_url)")
        println("  API: $(engine.broker.order_client.base_url)")
        
        is_testnet = contains(engine.broker.order_client.base_url, "testnet")
        
        if is_testnet
            println("\n✅ 测试网模式")
            println("  - 使用虚拟资金")
            println("  - 可以安全测试")
        else
            println("\n⚠️⚠️⚠️  主网模式 - 真实资金！⚠️⚠️⚠️")
            println("\n确认启动主网交易？")
            print("输入 'START LIVE TRADING' 继续: ")
            
            confirm = readline()
            
            if confirm != "START LIVE TRADING"
                println("\n已取消")
                exit(0)
            end
        end
        
        println("\n" * "="^70)
        
        # 最后确认
        if is_testnet
            print("\n按 Enter 启动，或 Ctrl+C 取消: ")
            readline()
        end
        
        # 启动引擎
        start!(engine)
        
    catch e
        if isa(e, InterruptException)
            println("\n\n👋 已取消启动")
        else
            println("\n\n❌ 启动失败:")
            showerror(stdout, e, catch_backtrace())
            println()
        end
        exit(1)
    end
end

# 运行主程序
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end