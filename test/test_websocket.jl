# test/test_websocket.jl

using Pkg
Pkg.activate(".")

using Dates

include("../src/live/websocket_client.jl")

println("="^70)
println("WebSocket实时数据流测试")
println("="^70)

# 创建WebSocket客户端
ws = BinanceWebSocket(market=:futures)

# 订阅BTCUSDT的Tick和K线
subscribe_ticks!(ws, "BTCUSDT")
subscribe_klines!(ws, "BTCUSDT", "1m")

# 设置回调函数
tick_count = Ref(0)
kline_count = Ref(0)

ws.on_tick = function(tick)
    tick_count[] += 1
    
    if tick_count[] <= 5  # 只打印前5个
        println("\n📊 Tick #$(tick_count[]):")
        println("  时间: $(tick.timestamp)")
        println("  价格: \$$(tick.price)")
        println("  数量: $(tick.quantity)")
        println("  买方: $(tick.is_buyer_maker ? "做市商" : "吃单")")
    elseif tick_count[] == 6
        println("\n... (后续Tick将不再打印) ...")
    end
end

ws.on_kline = function(kline)
    kline_count[] += 1
    
    println("\n📈 K线完成 #$(kline_count[]):")
    println("  时间: $(kline.timestamp)")
    println("  开: \$$(kline.open)")
    println("  高: \$$(kline.high)")
    println("  低: \$$(kline.low)")
    println("  收: \$$(kline.close)")
    println("  量: $(kline.volume)")
end

# 启动WebSocket
println("\n🚀 启动WebSocket...")
start!(ws)

println("\n⏳ 运行30秒后停止...")
println("(按 Ctrl+C 可提前停止)\n")

# 运行30秒
try
    for i in 1:30
        sleep(1)
        
        # 每10秒显示一次统计
        if i % 10 == 0
            stats = get_stats(ws)
            println("\n📊 运行 $(i) 秒:")
            println("  接收消息数: $(stats["messages_received"])")
            println("  连接状态: $(stats["is_connected"] ? "✅ 正常" : "❌ 断开")")
        end
    end
catch e
    if isa(e, InterruptException)
        println("\n\n⚠️  用户中断")
    else
        rethrow(e)
    end
end

# 停止
println("\n🛑 停止WebSocket...")
stop!(ws)

sleep(1)

println("\n" * "="^70)
println("测试统计")
println("="^70)
println("  接收Tick数: $(tick_count[])")
println("  接收K线数: $(kline_count[])")
println("  总消息数: $(ws.messages_received)")
println("\n✅ 测试完成！")