# test/test_live_engine.jl

using Pkg
Pkg.activate(".")

include("../src/live/live_engine.jl")

println("="^70)
println("Live Engine 测试")
println("="^70)

# 创建引擎
engine = LiveEngine("config/strategy.yaml")

println("\n✅ 引擎创建成功！")
println("\n组件状态:")
println("  WebSocket: $(typeof(engine.ws_client))")
println("  Broker: $(typeof(engine.broker))")
println("  交易对: $(engine.symbol)")
println("  数据流: $(length(engine.ws_client.streams)) 个流")

println("\n配置信息:")
println("  测试网: $(contains(engine.broker.order_client.base_url, "testnet"))")
println("  WebSocket URL: $(engine.ws_client.base_url)")

println("\n⚠️  这只是初始化测试，不会启动实盘交易")
println("要启动实盘交易，请运行:")
println("  julia --project=. scripts/start_live_trading.jl")

println("\n✅ 测试完成！")