# examples/test_indicators.jl

"""
测试技术指标计算
"""

using PassivbotJL
using DataFrames
using Dates

# 创建交易所连接
temp_config = ExchangeConfig(:binance, "", "", false, 1200, 30, 3)
exchange = BinanceFutures(temp_config)

println("\n" * "="^70)
println("测试技术指标计算")
println("="^70)

# ============================================================================
# 获取测试数据
# ============================================================================
println("\n📊 获取BTC历史数据...")
klines = get_klines(exchange, :BTCUSDT, "5m", 200)
println("✅ 获取到 $(nrow(klines)) 根K线")
println("   时间范围: $(klines[1, :timestamp]) 至 $(klines[end, :timestamp])")

# ============================================================================
# 测试1: EMA计算
# ============================================================================
println("\n📈 测试1: EMA计算")
try
    ema_20 = PassivbotJL.calculate_ema(klines, :close, 20)
    ema_60 = PassivbotJL.calculate_ema(klines, :close, 60)
    
    println("✅ EMA计算成功")
    println("   EMA20 最新值: $(round(ema_20[end], digits=2))")
    println("   EMA60 最新值: $(round(ema_60[end], digits=2))")
    println("   当前价格: $(round(klines[end, :close], digits=2))")
    
    # 判断趋势
    if ema_20[end] > ema_60[end]
        println("   趋势: 上涨 (EMA20 > EMA60)")
    else
        println("   趋势: 下跌 (EMA20 < EMA60)")
    end
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试2: ATR计算
# ============================================================================
println("\n📊 测试2: ATR计算")
try
    atr = PassivbotJL.calculate_atr(klines, 14)
    atr_pct = PassivbotJL.calculate_atr_percentage(klines, 14)
    
    println("✅ ATR计算成功")
    println("   ATR: $(round(atr[end], digits=2))")
    println("   ATR%: $(round(atr_pct[end] * 100, digits=2))%")
    
    # 波动率评估
    vol_pct = atr_pct[end] * 100
    vol_state = if vol_pct < 1.0
        "极低"
    elseif vol_pct < 2.0
        "低"
    elseif vol_pct < 4.0
        "中等"
    elseif vol_pct < 6.0
        "高"
    else
        "极高"
    end
    println("   波动率状态: $vol_state")
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试3: ADX计算
# ============================================================================
println("\n📈 测试3: ADX计算")
try
    adx_data = PassivbotJL.calculate_adx(klines, 14)
    
    println("✅ ADX计算成功")
    println("   ADX: $(round(adx_data.adx[end], digits=2))")
    println("   +DI: $(round(adx_data.plus_di[end], digits=2))")
    println("   -DI: $(round(adx_data.minus_di[end], digits=2))")
    
    # 趋势强度评估
    adx_val = adx_data.adx[end]
    trend_strength = if adx_val < 20
        "弱趋势或震荡"
    elseif adx_val < 30
        "中等趋势"
    else
        "强趋势"
    end
    println("   趋势强度: $trend_strength")
    
    # 趋势方向
    if adx_data.plus_di[end] > adx_data.minus_di[end]
        println("   方向: 上涨趋势 (+DI > -DI)")
    else
        println("   方向: 下跌趋势 (-DI > +DI)")
    end
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试4: CCI计算
# ============================================================================
println("\n📊 测试4: CCI计算")
try
    cci = PassivbotJL.calculate_cci(klines, 14)
    
    println("✅ CCI计算成功")
    println("   CCI: $(round(cci[end], digits=2))")
    
    # CCI信号评估
    cci_val = cci[end]
    cci_signal = if cci_val < -150
        "深度超卖 (强烈买入信号)"
    elseif cci_val < -100
        "超卖 (买入信号)"
    elseif cci_val < -50
        "轻度超卖"
    elseif cci_val > 150
        "深度超买 (强烈卖出信号)"
    elseif cci_val > 100
        "超买 (卖出信号)"
    elseif cci_val > 50
        "轻度超买"
    else
        "中性"
    end
    println("   状态: $cci_signal")
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试5: RSI计算
# ============================================================================
println("\n📈 测试5: RSI计算")
try
    rsi = PassivbotJL.calculate_rsi(klines, :close, 14)
    
    println("✅ RSI计算成功")
    println("   RSI: $(round(rsi[end], digits=2))")
    
    # RSI信号评估
    rsi_val = rsi[end]
    rsi_signal = if rsi_val < 30
        "超卖"
    elseif rsi_val > 70
        "超买"
    else
        "中性"
    end
    println("   状态: $rsi_signal")
catch e
    println("❌ 失败: $e")
end

# ============================================================================
# 测试6: 计算所有指标
# ============================================================================
println("\n📊 测试6: 计算所有指标")
try
    klines_with_indicators = PassivbotJL.calculate_all_indicators(klines)
    
    println("✅ 所有指标计算成功")
    println("   DataFrame列数: $(ncol(klines_with_indicators))")
    println("   新增指标: $(setdiff(names(klines_with_indicators), names(klines)))")
    
    # 显示最新数据
    println("\n   最新指标值:")
    last_row = klines_with_indicators[end, :]
    println("   时间: $(last_row.timestamp)")
    println("   收盘: $(round(last_row.close, digits=2))")
    println("   EMA20: $(round(last_row.ema_20, digits=2))")
    println("   EMA60: $(round(last_row.ema_60, digits=2))")
    println("   ATR%: $(round(last_row.atr_pct * 100, digits=2))%")
    println("   ADX: $(round(last_row.adx, digits=2))")
    println("   CCI: $(round(last_row.cci, digits=2))")
    println("   RSI: $(round(last_row.rsi, digits=2))")
    
    # 验证指标
    is_valid = PassivbotJL.validate_indicators(klines_with_indicators)
    if is_valid
        println("\n   ✅ 指标验证通过（无NaN或Inf）")
    else
        println("\n   ⚠️  指标验证发现问题")
    end
catch e
    println("❌ 失败: $e")
    showerror(stdout, e, catch_backtrace())
end

println("\n" * "="^70)
println("✅ 技术指标测试完成！")
println("="^70)