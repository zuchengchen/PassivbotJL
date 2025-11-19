# test/test_broker.jl

using Pkg
Pkg.activate(".")

using Dates

include("../src/backtest/backtest_broker.jl")

println("="^70)
println("测试模拟交易所")
println("="^70)

# 创建broker
broker = BacktestBroker(10000.0)

println("\n✅ Broker创建成功")
println("  初始余额: \$$(broker.balance)")

# 更新价格
update_price!(broker, :BTCUSDT, 90000.0)
println("\n✅ 价格更新: BTCUSDT = \$90,000")

# 测试市价买单
buy_order = (
    symbol = :BTCUSDT,
    side = :BUY,
    order_type = :MARKET,
    quantity = 0.1,
    price = nothing,
    reduce_only = false,
    client_order_id = "test_1"
)

fill = execute_order(broker, buy_order, now())

if !isnothing(fill)
    println("\n✅ 市价买单成交:")
    println("  数量: $(fill.quantity) BTC")
    println("  成交价: \$$(round(fill.fill_price, digits=2))")
    println("  手续费: \$$(round(fill.commission, digits=2))")
    println("  剩余余额: \$$(round(broker.balance, digits=2))")
else
    println("\n❌ 订单被拒绝")
end

# 测试限价卖单
sell_order = (
    symbol = :BTCUSDT,
    side = :SELL,
    order_type = :LIMIT,
    quantity = 0.1,
    price = 91000.0,
    reduce_only = true,
    client_order_id = "test_2"
)

# 价格未触及
update_price!(broker, :BTCUSDT, 90500.0)
fill2 = execute_order(broker, sell_order, now())

if isnothing(fill2)
    println("\n✅ 限价单pending（价格未触及）")
end

# 价格触及
update_price!(broker, :BTCUSDT, 91000.0)
fill3 = execute_order(broker, sell_order, now())

if !isnothing(fill3)
    println("\n✅ 限价卖单成交:")
    println("  数量: $(fill3.quantity) BTC")
    println("  成交价: \$$(round(fill3.fill_price, digits=2))")
    println("  手续费: \$$(round(fill3.commission, digits=2))")
    println("  剩余余额: \$$(round(broker.balance, digits=2))")
end

# 打印统计
print_broker_stats(broker)

println("\n✅ 所有测试通过！")