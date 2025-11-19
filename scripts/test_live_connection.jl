# scripts/test_live_connection.jl

"""
快速测试实盘连接（不启动交易）

测试：
- WebSocket连接
- API认证
- 数据接收

不会：
- 下单
- 修改持仓
"""

using Pkg
Pkg.activate(".")

using Dates
using Logging

# ✅ 启用调试日志
global_logger(ConsoleLogger(stderr, Logging.Debug))

include("../src/live/live_engine.jl")

println("="^70)
println("🧪 实盘连接测试")
println("="^70)

# 创建引擎
println("\n🔧 创建引擎...")
engine = LiveEngine("config/strategy.yaml")

println("\n✅ 引擎创建成功")

# 同步状态
println("\n📊 同步账户状态...")
sync_positions!(engine.broker)
sync_orders!(engine.broker)

print_broker_stats(engine.broker)

# 订阅数据
println("\n📡 订阅数据流...")
subscribe_ticks!(engine.ws_client, string(engine.symbol))
subscribe_klines!(engine.ws_client, string(engine.symbol), "1m")

println("  订阅流: $(engine.ws_client.streams)")

# 启动WebSocket（仅测试30秒）
println("\n🔌 启动WebSocket（测试30秒）...")

# 计数器
tick_count = Ref(0)
kline_count = Ref(0)

# 设置简单回调
engine.ws_client.on_tick = function(tick)
    tick_count[] += 1
    if tick_count[] % 10 == 1
        println("  📈 Tick #$(tick_count[]): \$$(tick.price)")
    end
end

engine.ws_client.on_kline = function(kline)
    kline_count[] += 1
    println("  📊 K线完成: $(kline.close_time) Close=\$$(kline.close)")
end

# 启动
start!(engine.ws_client)

println("\n⏳ 接收数据中...")

# 运行30秒
for i in 1:30
    sleep(1)
    if i % 10 == 0
        println("  $(30-i) 秒后停止...")
    end
end

# 停止
println("\n⏹️  停止WebSocket...")
stop!(engine.ws_client)

# 统计
println("\n" * "="^70)
println("测试结果")
println("="^70)
println("  Tick接收: $(tick_count[]) 个")
println("  K线接收: $(kline_count[]) 个")
println("  平均Tick速率: $(round(tick_count[] / 30, digits=1)) tick/秒")

if tick_count[] > 0
    println("\n✅ WebSocket连接正常！")
else
    println("\n⚠️  未接收到数据，请检查:")
    println("  1. 网络连接")
    println("  2. 交易对是否正确")
    println("  3. WebSocket URL是否正确")
end

println("\n✅ 测试完成！")