# scripts/test_websocket_minimal.jl

using Pkg
Pkg.activate(".")

using WebSockets
using JSON3
using Dates

println("="^70)
println("最小WebSocket测试")
println("="^70)

url = "wss://fstream.binance.com/stream?streams=btcusdt@aggTrade"

println("\n连接到: $url")

message_count = Ref(0)

try
    WebSockets.open(url) do ws
        println("✅ 连接成功！")
        println("\n等待消息（10秒）...")
        
        start_time = time()
        
        for msg in ws
            if time() - start_time > 10
                break
            end
            
            message_count[] += 1
            
            try
                msg_str = String(msg)
                data = JSON3.read(msg_str)
                
                if haskey(data, :stream) && haskey(data, :data)
                    trade = data.data
                    price = parse(Float64, String(trade.p))
                    
                    println("  消息 #$(message_count[]): Price=\$$price")
                else
                    println("  消息 #$(message_count[]): $(keys(data))")
                end
                
            catch e
                println("  消息 #$(message_count[]): 解析失败 - $e")
                println("    内容: $(first(String(msg), 100))")
            end
            
            if message_count[] >= 5
                println("\n已接收5条消息，测试成功！")
                break
            end
        end
    end
    
catch e
    println("❌ 错误: $e")
    rethrow(e)
end

println("\n" * "="^70)
println("总消息数: $(message_count[])")

if message_count[] > 0
    println("✅ WebSocket工作正常！")
else
    println("❌ 未接收到消息")
end