# scripts/test_single_stream.jl

using Pkg
Pkg.activate(".")

using WebSockets
using JSON3

println("="^70)
println("测试单流WebSocket")
println("="^70)

url = "wss://fstream.binance.com/ws/btcusdt@aggTrade"
println("\nURL: $url")

message_count = 0

try
    println("连接中...")
    
    WebSockets.open(url) do ws
        println("✅ 连接成功！\n")
        
        println("等待消息...")
        start_time = time()
        
        for msg in ws
            elapsed = time() - start_time
            
            if elapsed > 10
                println("\n⏱️  10秒超时")
                break
            end
            
            message_count += 1
            msg_str = String(msg)
            
            println("📨 消息 #$message_count ($(round(elapsed, digits=1))秒)")
            println("   长度: $(length(msg_str)) 字节")
            
            # 解析
            try
                data = JSON3.read(msg_str)
                
                # 显示所有字段
                println("   字段: $(keys(data))")
                
                # 如果是交易数据
                if haskey(data, :p)
                    price = parse(Float64, String(data.p))
                    qty = parse(Float64, String(data.q))
                    println("   💰 价格: \$$price, 数量: $qty")
                end
                
            catch e
                println("   ⚠️  解析失败: $e")
                println("   内容: $(first(msg_str, 150))")
            end
            
            if message_count >= 3
                println("\n✅ 已接收3条消息，测试成功！")
                break
            end
        end
    end
    
catch e
    println("❌ 错误: $e")
    showerror(stdout, e, catch_backtrace())
end

println("\n" * "="^70)
println("总消息: $message_count")

if message_count > 0
    println("✅ 单流WebSocket工作正常！")
else
    println("❌ 仍然没有收到消息")
    println("\n🔍 诊断建议:")
    println("  1. 检查网络代理设置")
    println("  2. 尝试使用VPN")
    println("  3. 检查防火墙规则")
    println("  4. 测试其他交易对（如ethusdt）")
end