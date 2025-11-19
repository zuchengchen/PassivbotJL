# examples/test_strategy.jl

"""
测试完整策略分析
"""

using PassivbotJL
using Dates
using Printf  # 添加这行

# 加载配置
config = load_config("config/strategy.yaml")

# 创建交易所连接
exchange = BinanceFutures(config.exchange)

println("\n" * "="^70)
println("测试完整策略分析")
println("="^70)

# ============================================================================
# 测试1: 单个交易对分析
# ============================================================================
println("\n📊 测试1: 分析BTC市场")

try
    analysis = PassivbotJL.analyze_market(exchange, :BTCUSDT, config)
    PassivbotJL.print_market_analysis(analysis)
    
    println("\n✅ 单交易对分析成功")
catch e
    println("❌ 失败: $e")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试2: 多交易对分析
# ============================================================================
println("\n📊 测试2: 分析多个交易对")

symbols = [:BTCUSDT, :ETHUSDT, :BNBUSDT]

try
    analyses = PassivbotJL.analyze_multiple_symbols(exchange, symbols, config)
    
    println("\n✅ 成功分析 $(length(analyses)) 个交易对")
    
    # 显示简要结果
    println("\n交易对摘要:")
    println("-" * "─"^69)
    println(@sprintf("%-12s %-15s %-15s %-12s", "交易对", "趋势", "CCI信号", "建议"))
    println("-" * "─"^69)
    
    for (symbol, analysis) in sort(collect(analyses), by=x->string(x[1]))
        trend_str = string(analysis.trend.primary_trend)[1:min(end, 6)]
        signal_str = has_entry_signal(analysis.cci_signal) ? 
                    string(analysis.cci_signal.direction) : "无"
        trade_str = analysis.should_trade ? "✅ 交易" : "⏸️  等待"
        
        println(@sprintf("%-12s %-15s %-15s %-12s", 
                symbol, trend_str, signal_str, trade_str))
    end
    println("-" * "─"^69)
    
    # 找出交易机会
    opportunities = PassivbotJL.find_trading_opportunities(analyses, 0.5)
    
    if !isempty(opportunities)
        println("\n🎯 发现 $(length(opportunities)) 个交易机会:")
        for (i, symbol) in enumerate(opportunities)
            analysis = analyses[symbol]
            side = analysis.recommended_side == LONG ? "做多" : "做空"
            println("  $i. $symbol - $side (信号强度: $(round(analysis.cci_signal.strength*100, digits=0))%)")
        end
    else
        println("\n⏸️  当前无交易机会")
    end
    
catch e
    println("❌ 失败: $e")
    showerror(stdout, e, catch_backtrace())
end

# ============================================================================
# 测试3: 趋势检测独立测试
# ============================================================================
println("\n\n📈 测试3: 独立趋势检测")

try
    trend = PassivbotJL.detect_trend_from_symbol(exchange, :BTCUSDT, config.trend)
    
    println("✅ 趋势检测成功")
    println("  主趋势: $(trend.primary_trend)")
    println("  趋势强度: $(trend.strength)")
    println("  已确认: $(trend.confirmed)")
    println("  ADX: $(round(trend.adx, digits=2))")
    println("  描述: $(PassivbotJL.get_trend_description(trend))")
    
    # 测试辅助函数
    println("\n  辅助判断:")
    println("  - 是否趋势中: $(PassivbotJL.is_trending(trend))")
    println("  - 是否强趋势: $(PassivbotJL.is_strong_trend(trend))")
    println("  - 可以交易: $(PassivbotJL.should_trade_on_trend(trend))")
    
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试4: CCI信号独立测试
# ============================================================================
println("\n📊 测试4: 独立CCI信号生成")

try
    # 先获取趋势
    trend = PassivbotJL.detect_trend_from_symbol(exchange, :BTCUSDT, config.trend)
    
    # 生成CCI信号
    cci_signal = PassivbotJL.generate_cci_signal_from_symbol(
        exchange, :BTCUSDT, trend, config.cci
    )
    
    println("✅ CCI信号生成成功")
    println("  CCI值: $(round(cci_signal.cci_value, digits=2))")
    println("  方向: $(cci_signal.direction)")
    println("  级别: $(cci_signal.level)")
    println("  强度: $(round(cci_signal.strength * 100, digits=0))%")
    println("  建议仓位: $(round(cci_signal.suggested_position_pct * 100, digits=0))%")
    println("  描述: $(PassivbotJL.get_signal_description(cci_signal))")
    
    # 测试辅助函数
    println("\n  辅助判断:")
    println("  - 有入场信号: $(PassivbotJL.has_entry_signal(cci_signal))")
    println("  - 是强信号: $(PassivbotJL.is_strong_signal(cci_signal))")
    println("  - 应该入场: $(PassivbotJL.should_enter_position(cci_signal))")
    
catch e
    println("❌ 失败: $e")
end

println("\n" * "="^70)
println("✅ 策略测试完成！")
println("="^70)