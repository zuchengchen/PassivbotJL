# test/test_order_fix.jl

using Pkg
Pkg.activate(".")

include("../src/config/config_loader.jl")
include("../src/live/live_order_client.jl")

println("="^70)
println("订单功能修复测试")
println("="^70)

# 加载配置
config = load_config("config/strategy.yaml")
creds = get_api_credentials(config)

# 创建客户端
client = LiveOrderClient(creds.api_key, creds.api_secret, market=:futures)
client.base_url = "https://testnet.binancefuture.com"

println("\n📊 测试1: 时间戳获取")
println("-"^70)
for i in 1:3
    ts = get_timestamp(client)
    println("  尝试 $i: $ts")
    sleep(1)
end

println("\n📊 测试2: 账户查询")
println("-"^70)
try
    account = get_account(client)
    println("✅ 成功！余额: \$$(account.availableBalance)")
catch e
    println("❌ 失败: $e")
end

println("\n📊 测试3: 持仓查询")
println("-"^70)
try
    positions = get_position(client)
    println("✅ 成功！持仓数: $(length(positions))")
catch e
    println("❌ 失败: $e")
end

println("\n✅ 测试完成！")