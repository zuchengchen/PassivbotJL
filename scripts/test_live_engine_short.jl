# scripts/test_live_engine_short.jl

"""
实盘引擎短时测试（60秒）

测试完整的引擎功能：
- 引擎初始化
- 数据流订阅
- 实时数据接收
- 状态同步
"""

using Pkg
Pkg.activate(".")

using Dates
using Logging

# 设置日志级别（隐藏调试信息）
global_logger(ConsoleLogger(stderr, Logging.Info))

include("../src/live/live_engine.jl")

println("="^70)
println("🚀 实盘引擎短时测试（60秒）")
println("="^70)

# 创建引擎
println("\n🔧 创建引擎...")
engine = LiveEngine("config/strategy.yaml")

println("\n✅ 引擎创建成功")
println("  交易对: $(engine.symbol)")
println("  WebSocket: $(engine.ws_client.base_url)")
println("  API: $(engine.broker.order_client.base_url)")

# 同步状态
println("\n📊 同步初始状态...")
sync_positions!(engine.broker)
sync_orders!(engine.broker)

print_broker_stats(engine.broker)

# 订阅数据
println("\n📡 订阅数据流...")
subscribe_ticks!(engine.ws_client, string(engine.symbol))
subscribe_klines!(engine.ws_client, string(engine.symbol), "1m")

println("  订阅流: $(engine.ws_client.streams)")

# 启动WebSocket
println("\n🔌 启动WebSocket...")
start!(engine.ws_client)

engine.is_running = true
engine.start_time = now(UTC)

println("\n⏳ 运行60秒测试...")
println("  (每20秒打印一次状态)\n")

# 运行60秒
for i in 1:60
    sleep(1)
    
    if i % 20 == 0
        println("📊 运行状态 ($(i)秒):")
        println("  Tick接收: $(engine.ticks_received)")
        println("  K线缓存: $(length(get(engine.kline_buffer, "1m", [])))")
        
        if !isnothing(engine.last_tick)
            println("  最新价格: \$$(engine.last_tick.price)")
            println("  最新时间: $(engine.last_tick.timestamp)")
        end
        
        # WebSocket状态
        ws_stats = get_stats(engine.ws_client)
        println("  WebSocket消息: $(ws_stats["messages_received"])")
        println("  连接状态: $(ws_stats["is_connected"] ? "✅ 正常" : "❌ 断开")")
        println()
    end
end

# 停止
println("⏹️  停止引擎...")
stop!(engine.ws_client)

# 等待清理
sleep(2)

# 最终统计
println("\n" * "="^70)
println("测试完成")
println("="^70)

ws_stats = get_stats(engine.ws_client)

println("运行统计:")
println("  运行时间: 60秒")
println("  Tick接收: $(engine.ticks_received)")
println("  K线接收: $(length(get(engine.kline_buffer, "1m", [])))")
println("  WebSocket消息: $(ws_stats["messages_received"])")
println("  平均速率: $(round(engine.ticks_received / 60, digits=1)) tick/秒")

if !isnothing(engine.last_tick)
    println("\n最后一个Tick:")
    println("  价格: \$$(engine.last_tick.price)")
    println("  时间: $(engine.last_tick.timestamp)")
end

println()

if engine.ticks_received > 0
    println("✅ 实盘引擎工作正常！")
    println()
    println("🎉 所有测试通过！")
    println()
    println("下一步:")
    println("  1. 运行完整启动脚本: julia --project=. scripts/start_live_trading.jl")
    println("  2. 或者继续开发自动交易策略")
else
    println("⚠️  引擎未接收到数据")
    println()
    println("请检查:")
    println("  1. 网络连接")
    println("  2. WebSocket配置")
    println("  3. 防火墙设置")
end

println("="^70)