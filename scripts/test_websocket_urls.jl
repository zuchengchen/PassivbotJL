# scripts/test_websocket_urls.jl

using Pkg
Pkg.activate(".")

using WebSockets
using JSON3

println("="^70)
println("测试不同的WebSocket URL")
println("="^70)

# 测试多个URL
urls = [
    # 主网
    ("主网 - Stream", "wss://fstream.binance.com/stream?streams=btcusdt@aggTrade"),
    ("主网 - WS", "wss://fstream.binance.com/ws/btcusdt@aggTrade"),
    
    # 测试网
    ("测试网 - Stream", "wss://stream.binancefuture.com/stream?streams=btcusdt@aggTrade"),
    ("测试网 - WS", "wss://stream.binancefuture.com/ws/btcusdt@aggTrade"),
]

for (name, url) in urls
    println("\n" * "-"^70)
    println("测试: $name")
    println("URL: $url")
    println("-"^70)
    
    try
        # 设置超时
        timeout = 5.0
        message_received = Ref(false)
        
        @async begin
            sleep(timeout)
            if !message_received[]
                println("  ⏱️  超时（$(timeout)秒）- 未收到消息")
            end
        end
        
        WebSockets.open(url) do ws
            println("  ✅ 连接成功")
            
            # 尝试读取一条消息
            start = time()
            for msg in ws
                if time() - start > timeout
                    break
                end
                
                message_received[] = true
                msg_str = String(msg)
                
                println("  📨 收到消息！")
                println("  长度: $(length(msg_str)) 字节")
                
                # 尝试解析
                try
                    data = JSON3.read(msg_str)
                    if haskey(data, :stream)
                        println("  流名称: $(data.stream)")
                    end
                    if haskey(data, :data)
                        println("  ✅ 数据格式正确")
                    end
                catch e
                    println("  ⚠️  解析失败: $e")
                    println("  内容预览: $(first(msg_str, 100))")
                end
                
                break  # 只测试一条消息
            end
            
            if !message_received[]
                println("  ❌ 未收到消息")
            end
        end
        
    catch e
        println("  ❌ 连接失败: $e")
    end
    
    sleep(1)
end

println("\n" * "="^70)
println("测试完成")
println("="^70)