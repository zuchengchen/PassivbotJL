# test/test_simple_order.jl

using Pkg
Pkg.activate(".")

include("../src/config/config_loader.jl")
include("../src/live/live_order_client.jl")

println("="^70)
println("简单下单测试")
println("="^70)

# 加载配置
config = load_config("config/strategy.yaml")
creds = get_api_credentials(config)

# 创建客户端
client = LiveOrderClient(creds.api_key, creds.api_secret, market=:futures)
client.base_url = "https://testnet.binancefuture.com"

println("\n📊 获取当前价格...")
price_data = HTTP.get("$(client.base_url)/fapi/v1/ticker/price?symbol=BTCUSDT")
current_price = parse(Float64, JSON3.read(String(price_data.body)).price)

println("  BTCUSDT: \$$(current_price)")

# 计算合适的订单数量（确保>$100）
min_notional = 120.0  # 留点余量
order_quantity = ceil(min_notional / current_price, digits=3)
order_value = order_quantity * current_price

println("\n📝 订单参数:")
println("  数量: $(order_quantity) BTC")
println("  价值: \$$(round(order_value, digits=2))")

# 下单价格（低于市价5%，不会立即成交）
order_price = round(current_price * 0.95, digits=1)
println("  挂单价: \$$(order_price)")

print("\n确认下单？(yes/NO): ")
confirm = readline()

if lowercase(confirm) == "yes"
    try
        println("\n📤 下单中...")
        
        order = place_limit_order(
            client,
            "BTCUSDT",
            "BUY",
            order_quantity,
            order_price,
            timeInForce="GTC"
        )
        
        println("✅ 下单成功！")
        println("  订单ID: $(order.orderId)")
        println("  状态: $(order.status)")
        
        sleep(3)
        
        # 查询订单
        println("\n📊 查询订单状态...")
        status = get_order(client, "BTCUSDT", order.orderId)
        println("  状态: $(status.status)")
        
        # 撤销
        print("\n撤销订单？(y/N): ")
        if lowercase(readline()) == "y"
            println("\n🗑️  撤销中...")
            result = cancel_order(client, "BTCUSDT", order.orderId)
            println("✅ 已撤销")
        end
        
    catch e
        println("❌ 失败: $e")
    end
else
    println("已取消")
end