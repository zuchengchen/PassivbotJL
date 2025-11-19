# test/test_websocket_client.jl

using Pkg
Pkg.activate(".")

include("../src/live/websocket_client.jl")

println("="^70)
println("测试 BinanceWebSocket 客户端")
println("="^70)

# 创建客户端
println("\n🔧 创建WebSocket客户端...")
ws = BinanceWebSocket(market=:futures)

println("✅ 客户端创建成功")
println("  Base URL: $(ws.base_url)")

# 订阅数据流
println("\n📡 订阅数据流...")
subscribe_ticks!(ws, "BTCUSDT")
subscribe_klines!(ws, "BTCUSDT", "1m")

println("  订阅流: $(ws.streams)")

# 设置回调
println("\n⚙️  设置回调函数...")

tick_count = Ref(0)
kline_count = Ref(0)

ws.on_tick = function(tick)
    tick_count[] += 1
    
    if tick_count[] <= 5
        println("  📈 Tick #$(tick_count[]): \$$(tick.price) @ $(tick.timestamp)")
    elseif tick_count[] == 6
        println("  ... (后续Tick不再打印)")
    end
    
    if tick_count[] % 100 == 0
        println("  📊 已接收 $(tick_count[]) 个Tick")
    end
end

ws.on_kline = function(kline)
    kline_count[] += 1
    println("  📊 K线 #$(kline_count[]): $(kline.close_time) Close=\$$(kline.close)")
end

println("✅ 回调设置完成")

# 启动WebSocket
println("\n🚀 启动WebSocket（运行30秒）...")
start!(ws)

println("\n⏳ 接收数据中...")

# 运行30秒
for i in 1:30
    sleep(1)
    
    if i % 10 == 0
        println("  ⏱️  运行中... $(30-i)秒后停止")
        
        # 打印统计
        stats = get_stats(ws)
        println("     消息总数: $(stats["messages_received"])")
        println("     连接状态: $(stats["is_connected"])")
    end
end

# 停止
println("\n⏹️  停止WebSocket...")
stop!(ws)

# 最终统计
println("\n" * "="^70)
println("测试结果")
println("="^70)

stats = get_stats(ws)
println("  总消息数: $(stats["messages_received"])")
println("  Tick接收: $(tick_count[])")
println("  K线接收: $(kline_count[])")
println("  平均速率: $(round(tick_count[] / 30, digits=1)) tick/秒")

if tick_count[] > 0
    println("\n✅ WebSocket客户端工作正常！")
else
    println("\n❌ 未接收到数据")
    println("\n可能的问题:")
    println("  1. MbedTLS未正确配置")
    println("  2. 网络连接问题")
    println("  3. URL格式错误")
end

println("="^70)