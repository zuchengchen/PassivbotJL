# examples/test_binance.jl

"""
测试币安API连接

运行前请设置环境变量：
export EXCHANGE_API_KEY="your_api_key"
export EXCHANGE_API_SECRET="your_api_secret"

或者在config/strategy.yaml中配置
"""

using PassivbotJL
using Dates          # 添加这行
using DataFrames     # 添加这行

# 加载配置
config = load_config("config/strategy.yaml")

# 创建交易所连接
exchange = BinanceFutures(config.exchange)

println("\n" * "="^70)
println("测试币安API连接")
println("="^70)

# ============================================================================
# 测试1: 服务器时间
# ============================================================================
println("\n📡 测试1: 获取服务器时间")
try
    server_time = get_server_time(exchange)
    local_time = now()
    time_diff = Dates.value(local_time - server_time) / 1000  # 秒
    
    println("✅ 服务器时间: $server_time")
    println("   本地时间:   $local_time")
    println("   时间差:     $(round(time_diff, digits=2))秒")
    
    if abs(time_diff) > 1.0
        println("⚠️  警告: 本地时间与服务器时间相差较大，可能导致API请求失败")
        println("   建议: 同步系统时间")
    end
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试2: 获取K线数据
# ============================================================================
println("\n📊 测试2: 获取K线数据")
try
    klines = get_klines(exchange, :BTCUSDT, "5m", 10)
    println("✅ 获取到 $(nrow(klines)) 根K线")
    println("   最新K线:")
    println("   时间: $(klines[end, :timestamp])")
    println("   开: $(klines[end, :open])")
    println("   高: $(klines[end, :high])")
    println("   低: $(klines[end, :low])")
    println("   收: $(klines[end, :close])")
    println("   量: $(klines[end, :volume])")
catch e
    println("❌ 失败: $e")
    println("   详细错误: ")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试3: 获取当前价格
# ============================================================================
println("\n💰 测试3: 获取当前价格")
try
    price = get_ticker_price(exchange, :BTCUSDT)
    println("✅ BTC当前价格: \$$price")
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试4: 获取24小时统计（需要先导出函数）
# ============================================================================
println("\n📈 测试4: 获取24小时统计")
try
    # 直接调用，因为还没导出
    ticker = PassivbotJL.get_ticker_24hr(exchange, :BTCUSDT)
    println("✅ 24小时统计:")
    println("   价格变化: $(round(ticker.price_change, digits=2))")
    println("   变化百分比: $(round(ticker.price_change_percent, digits=2))%")
    println("   最高: $(ticker.high)")
    println("   最低: $(ticker.low)")
    println("   成交量: $(round(ticker.volume, digits=2))")
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试5: 获取账户信息（需要API密钥）
# ============================================================================
println("\n💼 测试5: 获取账户信息")
if isempty(config.exchange.api_key)
    println("⚠️  跳过: 未配置API密钥")
    println("   请设置环境变量:")
    println("   export EXCHANGE_API_KEY=\"your_key\"")
    println("   export EXCHANGE_API_SECRET=\"your_secret\"")
else
    try
        balance = get_account_balance(exchange)
        println("✅ USDT余额:")
        println("   总余额: $(balance.balance)")
        println("   可用: $(balance.available)")
        println("   未实现盈亏: $(balance.cross_unrealized_pnl)")
    catch e
        println("❌ 失败: $e")
        println("   提示: 请确保设置了正确的API密钥")
        if occursin("Timestamp", string(e))
            println("   ⚠️  时间戳错误: 请同步系统时间")
        end
    end
end

# ============================================================================
# 测试6: 获取持仓信息
# ============================================================================
println("\n📊 测试6: 获取持仓信息")
if isempty(config.exchange.api_key)
    println("⚠️  跳过: 未配置API密钥")
else
    try
        position = get_position(exchange, :BTCUSDT)
        if isnothing(position)
            println("✅ 当前无持仓")
        else
            println("✅ 当前持仓:")
            println("   方向: $(position.side)")
            println("   数量: $(position.size)")
            println("   入场价: $(position.entry_price)")
            println("   标记价: $(position.mark_price)")
            println("   未实现盈亏: $(position.unrealized_pnl)")
        end
    catch e
        println("❌ 失败: $e")
        if occursin("Timestamp", string(e))
            println("   ⚠️  时间戳错误: 请同步系统时间")
        end
    end
end

println("\n" * "="^70)
println("测试完成！")
println("="^70)