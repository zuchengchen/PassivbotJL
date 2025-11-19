# test/test_websocket_simple.jl

using Pkg
Pkg.activate(".")

using HTTP
using JSON3
using Dates

println("="^70)
println("WebSocket连接测试（简化版）")
println("="^70)

# 直接使用HTTP.WebSockets
url = "wss://fstream.binance.com/stream?streams=btcusdt@aggTrade"

println("\n🚀 连接到: $url")

tick_count = 0

try
    HTTP.WebSockets.open(url) do io
        println("✅ WebSocket已连接！")
        println("\n接收实时Tick数据（10秒后自动停止）...\n")
        
        start_time = now()
        
        while now() - start_time < Second(10)
            # 读取消息
            msg = String(readavailable(io))
            
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
                    end
                end
            end
            
            sleep(0.01)  # 短暂休眠
        end
        
        println("\n⏰ 时间到，停止接收")
    end
    
    println("\n📊 统计:")
    println("  共接收Tick数: $tick_count")
    println("\n✅ 测试成功！")
    
catch e
    println("\n❌ 错误: $e")
    println("\n可能的原因:")
    println("  1. 网络连接问题")
    println("  2. Binance服务不可用")
    println("  3. 需要安装HTTP.jl的WebSocket支持")
    println("\n请检查网络连接后重试")
end