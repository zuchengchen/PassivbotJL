# test/test_signal_generator.jl

using Pkg
Pkg.activate(".")

using Dates
using DataFrames

include("../src/data/tick_data.jl")
include("../src/data/data_manager.jl")
include("../src/backtest/signal_generator.jl")

# 模拟配置
config = (
    grid_spacing = 0.005,
    max_grid_levels = 6,
    ddown_factor = 1.5
)

println("="^70)
println("测试信号生成器")
println("="^70)

# 加载数据（使用更长时间段）
println("\n📥 加载测试数据...")
tick_data = fetch_data_for_backtest(
    "BTCUSDT",
    DateTime(2024, 11, 13, 0, 0, 0),
    DateTime(2024, 11, 13, 23, 59, 59),  # ✅ 全天数据
    market=:futures
)

println("✅ 加载了 $(nrow(tick_data)) 条tick数据")

# 转换K线
println("\n📊 转换K线...")
bar_data = Dict{String, DataFrame}()
bar_data["1m"] = ticks_to_bars(tick_data, "1m")
bar_data["5m"] = ticks_to_bars(tick_data, "5m")
bar_data["15m"] = ticks_to_bars(tick_data, "15m")

println("✅ 1分钟K线: $(nrow(bar_data["1m"])) 根")
println("✅ 5分钟K线: $(nrow(bar_data["5m"])) 根")
println("✅ 15分钟K线: $(nrow(bar_data["15m"])) 根")

# 检查数据量
if nrow(bar_data["15m"]) < 50
    println("\n❌ 数据量不足（需要至少50根15分钟K线）")
    println("   当前只有 $(nrow(bar_data["15m"])) 根")
    println("   请使用更长时间段的数据")
    exit(1)
end

# 创建信号生成器
println("\n🔧 创建信号生成器...")
sg = SignalGenerator(config, bar_data)

println("✅ 信号生成器创建成功")

# 测试指标计算
println("\n📈 测试指标计算...")
current_time = bar_data["15m"][end, :timestamp]
indicators = calculate_indicators!(sg, :BTCUSDT, "15m", current_time)

if !isnothing(indicators)
    println("✅ 指标计算成功:")
    println("  当前价格: \$$(round(indicators["close"], digits=2))")
    println("  EMA快线(12): \$$(round(indicators["ema_fast"], digits=2))")
    println("  EMA慢线(26): \$$(round(indicators["ema_slow"], digits=2))")
    println("  ATR: \$$(round(indicators["atr"], digits=2)) ($(round(indicators["atr_pct"], digits=2))%)")
    println("  ADX: $(round(indicators["adx"], digits=1))")
    println("  CCI: $(round(indicators["cci"], digits=1))")
else
    println("❌ 指标计算失败")
    exit(1)
end

# 测试趋势检测
println("\n🔍 测试趋势检测...")
trend = detect_trend(sg, :BTCUSDT, current_time)

if !isnothing(trend)
    println("✅ 趋势检测成功:")
    println("  主趋势(15m): $(trend.primary_trend)")
    println("  次级趋势(5m): $(trend.secondary_trend)")
    println("  强度: $(trend.strength)")
    println("  双重确认: $(trend.confirmed ? "✅" : "❌")")
    println("  ADX: $(round(trend.adx, digits=1))")
    println("  EMA分离: $(round(trend.separation_pct, digits=3))%")
else
    println("❌ 趋势检测失败")
end

# 测试CCI信号
println("\n📡 测试CCI信号...")
cci_signal = generate_cci_signal(sg, :BTCUSDT, current_time)

if !isnothing(cci_signal)
    println("✅ CCI信号生成:")
    println("  方向: $(cci_signal.direction)")
    println("  级别: $(cci_signal.level)")
    println("  强度: $(round(cci_signal.strength * 100, digits=0))%")
    println("  CCI值: $(round(cci_signal.cci_value, digits=1))")
    println("  建议仓位: $(round(cci_signal.suggested_position_pct * 100, digits=1))%")
else
    println("⚠️  当前无CCI信号（CCI在中性区间）")
end

# 测试完整信号生成（遍历所有K线）
println("\n🎯 测试完整信号生成...")
println("正在扫描 $(nrow(bar_data["15m"])) 根K线...")

signals = []

for (idx, bar) in enumerate(eachrow(bar_data["15m"]))
    
    if idx < 50  # 跳过前50根（指标预热）
        continue
    end
    
    bar_event = (
        timestamp = bar.timestamp,
        symbol = :BTCUSDT,
        timeframe = "15m",
        open = bar.open,
        high = bar.high,
        low = bar.low,
        close = bar.close,
        volume = bar.volume
    )
    
    signal = generate_signal(sg, bar_event, bar.timestamp)
    
    if !isnothing(signal)
        push!(signals, signal)
        
        println("\n✅ 信号 #$(length(signals)):")
        println("  时间: $(signal.timestamp)")
        println("  类型: $(signal.signal_type)")
        println("  强度: $(round(signal.strength * 100, digits=0))%")
        println("  网格间距: $(round(signal.grid_spacing * 100, digits=2))%")
        println("  最大层数: $(signal.max_levels)")
        println("  加倍因子: $(round(signal.ddown_factor, digits=2))")
        println("  CCI: $(round(signal.indicators[:cci], digits=1))")
        println("  ADX: $(round(signal.indicators[:adx], digits=1))")
        println("  趋势: $(signal.indicators[:trend])")
    end
end

println("\n" * "="^70)
println("测试总结")
println("="^70)
println("  测试时间段: $(bar_data["15m"][1, :timestamp]) 到 $(bar_data["15m"][end, :timestamp])")
println("  1分钟K线: $(nrow(bar_data["1m"])) 根")
println("  5分钟K线: $(nrow(bar_data["5m"])) 根")
println("  15分钟K线: $(nrow(bar_data["15m"])) 根")
println("  有效K线数: $(nrow(bar_data["15m"]) - 49)")
println("  生成信号数: $(length(signals))")

if length(signals) > 0
    println("  信号率: $(round(length(signals) / (nrow(bar_data["15m"]) - 49) * 100, digits=1))%")
    
    # 信号统计
    long_signals = count(s -> s.signal_type == :LONG_ENTRY, signals)
    short_signals = count(s -> s.signal_type == :SHORT_ENTRY, signals)
    
    println("\n信号分布:")
    println("  做多信号: $long_signals")
    println("  做空信号: $short_signals")
    
    if length(signals) > 0
        avg_strength = mean([s.strength for s in signals])
        avg_spacing = mean([s.grid_spacing for s in signals])
        
        println("\n平均参数:")
        println("  平均强度: $(round(avg_strength * 100, digits=1))%")
        println("  平均间距: $(round(avg_spacing * 100, digits=2))%")
    end
else
    println("  ⚠️  未生成任何信号")
    println("\n可能原因:")
    println("  1. 市场处于震荡（无明确趋势）")
    println("  2. CCI未进入超买超卖区域")
    println("  3. 趋势与CCI方向不一致")
end

println("\n✅ 所有测试完成！")