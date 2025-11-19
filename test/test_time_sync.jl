# test/test_time_sync.jl

using Pkg
Pkg.activate(".")

using Dates

include("../src/config/config_loader.jl")
include("../src/live/live_order_client.jl")

println("="^70)
println("时间同步测试")
println("="^70)

# 加载配置
config = load_config("config/strategy.yaml")
creds = get_api_credentials(config)

# 创建客户端
client = LiveOrderClient(creds.api_key, creds.api_secret, market=:futures)
client.base_url = "https://testnet.binancefuture.com"

println("\n本地时间 (UTC): $(now(UTC))")
println("时间偏移: $(client.time_offset) ms")

# 测试账户查询
println("\n📊 测试账户查询...")
try
    account = get_account(client)
    println("✅ 成功！")
    println("  可用余额: \$$(account.availableBalance)")
    println("  总权益: \$$(account.totalWalletBalance)")
catch e
    println("❌ 失败: $e")
end