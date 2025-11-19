# test/test_websocket_raw.jl

using Pkg
Pkg.activate(".")

using WebSockets
using JSON3
using Dates

println("="^70)
println("WebSocket原始测试")
println("="^70)

url = "wss://fstream.binance.com/stream?streams=btcusdt@aggTrade"

println("\n🚀 连接到: $url")

tick_count = 0
start_time = now()

try
    WebSockets.open(url) do ws
        println("✅ WebSocket已连接！\n")
        
        while now() - start_time < Second(30)
            # 读取消息
            msg = String(read(ws))
            
            if !isempty(msg)
                # 解析JSON
                data = JSON3.read(msg)
                
                if haskey(data, :data)
                    tick_data = data.data
                    tick_count += 1
                    
                    # 只打印前5个
                    if tick_count <= 5
                        println("📊 Tick #$tick_count:")
                        println("  符号: $(tick_data.s)")
                        println("  价格: \$$(tick_data.p)")
                        println("  数量: $(tick_data.q)")
                        println("  时间: $(unix2datetime(tick_data.T / 1000))")
                        println()
                    elseif tick_count == 6
                        println("... (后续消息不再打印) ...\n")
                    end
                    
                    # 每收到100个消息打印一次统计
                    if tick_count % 100 == 0
                        println("📊 已接收 $tick_count 个Tick")
                    end
                end
            end
        end
        
        println("\n⏰ 30秒到，停止接收")
    end
    
    println("\n" * "="^70)
    println("测试统计")
    println("="^70)
    println("  运行时间: 30秒")
    println("  接收Tick数: $tick_count")
    println("  平均速率: $(round(tick_count/30, digits=1)) tick/秒")
    println("\n✅ 测试成功！")
    
catch e
    println("\n❌ 错误: $e")
    
    # 打印详细错误
    if isa(e, Base.IOError)
        println("\n网络IO错误，可能原因:")
        println("  1. 网络连接不稳定")
        println("  2. 防火墙阻止WebSocket连接")
        println("  3. Binance API暂时不可用")
    end
    
    rethrow(e)
end