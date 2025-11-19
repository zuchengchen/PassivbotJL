# test/test_live_broker.jl

using Pkg
Pkg.activate(".")

include("../src/config/config_loader.jl")
include("../src/live/live_broker.jl")

println("="^70)
println("Live Broker 测试")
println("="^70)

# 加载配置
config = load_config("config/strategy.yaml")
creds = get_api_credentials(config)

# 创建Broker
broker = LiveBroker(
    creds.api_key,
    creds.api_secret,
    :BTCUSDT,
    market=:futures,
    testnet=true
)

println("\n✅ Broker创建成功！")

# 同步状态
println("\n📊 同步持仓和订单...")
sync_positions!(broker)
sync_orders!(broker)

# 打印统计
print_broker_stats(broker)

println("\n✅ 测试完成！")