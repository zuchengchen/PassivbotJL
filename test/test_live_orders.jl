# test/test_live_orders.jl

using Pkg
Pkg.activate(".")

include("../src/live/live_order_client.jl")

println("="^70)
println("实盘订单客户端测试")
println("="^70)

# ⚠️ 警告：这里使用测试网API Key
# 真实交易请使用主网API Key

API_KEY = "YOUR_TESTNET_API_KEY"      # 替换为你的测试网API Key
API_SECRET = "YOUR_TESTNET_API_SECRET"  # 替换为你的测试网API Secret

# 创建客户端（期货测试网）
client = LiveOrderClient(API_KEY, API_SECRET, market=:futures)

println("\n📊 查询账户信息...")
try
    account = get_account(client)
    println("  可用余额: \$$(account.availableBalance)")
    println("  总权益: \$$(account.totalWalletBalance)")
catch e
    println("  ❌ 失败: $e")
    println("\n请确保:")
    println("  1. API Key正确")
    println("  2. 使用Binance期货测试网: https://testnet.binancefuture.com")
    println("  3. API Key已启用期货权限")
end

println("\n📊 查询持仓...")
try
    positions = get_position(client, "BTCUSDT")
    for pos in positions
        if parse(Float64, pos.positionAmt) != 0
            println("  $(pos.symbol): $(pos.positionAmt) @ \$$(pos.entryPrice)")
        end
    end
catch e
    println("  ❌ 失败: $e")
end

println("\n✅ 测试完成！")
println("\n⚠️  注意：实际下单前请确认使用测试网！")