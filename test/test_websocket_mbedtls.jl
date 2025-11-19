# test/test_websocket_mbedtls.jl

using Pkg
Pkg.activate(".")

using MbedTLS
using WebSockets
using JSON3
using Dates

println("="^70)
println("WebSocket测试（使用MbedTLS）")
println("="^70)

url = "wss://fstream.binance.com/stream?streams=btcusdt@aggTrade"

println("\n🚀 连接到: $url")

# ✅ 使用全局变量或Ref
tick_count = Ref(0)
start_time = now()

try
    WebSockets.open(url; sslconfig=MbedTLS.SSLConfig(true)) do ws
        println("✅ WebSocket已连接（MbedTLS）！\n")
        
        while now() - start_time < Second(30)
            if !eof(ws)
                msg = String(read(ws))
                
                if !isempty(msg)
                    data = JSON3.read(msg)
                    
                    if haskey(data, :data)
                        tick_data = data.data
                        tick_count[] += 1  # ✅ 使用 Ref
                        
                        if tick_count[] <= 5
                            println("📊 Tick #$(tick_count[]):")
                            println("  符号: $(tick_data.s)")
                            println("  价格: \$$(tick_data.p)")
                            println("  数量: $(tick_data.q)")
                            println("  时间: $(unix2datetime(tick_data.T / 1000))")
                            println()
                        elseif tick_count[] == 6
                            println("... (后续不再打印) ...\n")
                        end
                        
                        if tick_count[] % 100 == 0
                            println("📊 已接收 $(tick_count[]) 个Tick")
                        end
                    end
                end
            else
                sleep(0.001)
            end
        end
    end
    
    println("\n" * "="^70)
    println("✅ 测试成功！")
    println("  运行时间: 30秒")
    println("  接收Tick数: $(tick_count[])")
    println("  平均速率: $(round(tick_count[]/30, digits=1)) tick/秒")
    println("="^70)
    
catch e
    println("\n❌ 错误: $e")
    rethrow(e)
end