# src/strategy/market_analyzer.jl

"""
市场分析综合模块

整合趋势检测和CCI信号，提供完整的市场分析
"""

using DataFrames
using Dates

# ============================================================================
# 市场分析结果
# ============================================================================

"""
    MarketAnalysis

完整的市场分析结果
"""
struct MarketAnalysis
    symbol::Symbol
    timestamp::DateTime
    
    # 趋势分析
    trend::TrendState
    
    # CCI信号
    cci_signal::CCISignal
    
    # 波动率
    volatility::VolatilityMetrics
    
    # 当前价格
    current_price::Float64
    
    # 交易建议
    should_trade::Bool
    recommended_side::Union{Side, Nothing}
    recommended_position_size::Float64
    
    # 风险评估
    risk_level::Symbol  # :low, :medium, :high
end

# ============================================================================
# 市场分析函数
# ============================================================================

"""
    analyze_market(
        exchange::AbstractExchange,
        symbol::Symbol,
        config::StrategyConfig
    )::MarketAnalysis

完整的市场分析

参数：
- exchange: 交易所连接
- symbol: 交易对
- config: 策略配置

返回：
- MarketAnalysis: 完整的市场分析结果
"""
function analyze_market(
    exchange::AbstractExchange,
    symbol::Symbol,
    config::StrategyConfig
)::MarketAnalysis
    
    @info "Analyzing market for $symbol..."
    
    # ========================================================================
    # 1. 获取市场数据
    # ========================================================================
    
    # 计算需要的K线数量
    required_periods = max(
        config.trend.ema_slow_period,
        config.trend.adx_period,
        config.cci.period
    ) + 30
    
    # 获取主要时间框架的数据
    klines = get_klines(exchange, symbol, config.trend.timeframe_primary, required_periods)
    
    # 计算所有指标
    klines_with_indicators = calculate_all_indicators(klines)
    
    # 当前价格
    current_price = klines_with_indicators[end, :close]
    
    # ========================================================================
    # 2. 趋势分析
    # ========================================================================
    
    trend = detect_trend(klines_with_indicators, config.trend)
    
    @info "Trend detected" trend=get_trend_description(trend)
    
    # ========================================================================
    # 3. CCI信号分析
    # ========================================================================
    
    cci_signal = generate_cci_signal(klines_with_indicators, trend, config.cci)
    
    @info "CCI signal" signal=get_signal_description(cci_signal)
    
    # ========================================================================
    # 4. 波动率分析
    # ========================================================================
    
    atr = klines_with_indicators[end, :atr]
    atr_pct = klines_with_indicators[end, :atr_pct]
    
    # 计算多种波动率
    hl_vol = mean((klines_with_indicators[end-19:end, :high] .- 
                   klines_with_indicators[end-19:end, :low]) ./ 
                   klines_with_indicators[end-19:end, :close])
    
    returns = diff(log.(klines_with_indicators[end-19:end, :close]))
    return_vol = std(returns)
    
    # 综合波动率
    composite_vol = 0.5 * atr_pct + 0.3 * hl_vol + 0.2 * return_vol
    
    # 波动率状态
    vol_state = if composite_vol < 0.01
        VERY_LOW
    elseif composite_vol < 0.02
        LOW
    elseif composite_vol < 0.04
        MEDIUM
    elseif composite_vol < 0.06
        HIGH
    else
        VERY_HIGH
    end
    
    volatility = VolatilityMetrics(
        atr,
        atr_pct,
        hl_vol,
        return_vol,
        composite_vol,
        vol_state,
        now()
    )
    
    @info "Volatility" state=vol_state composite_pct=round(composite_vol*100, digits=2)
    
    # ========================================================================
    # 5. 交易决策
    # ========================================================================
    
    should_trade = false
    recommended_side = nothing
    recommended_position_size = 0.0
    risk_level = :medium
    
    # 检查是否可以交易
    if trend.confirmed && has_entry_signal(cci_signal)
        # 趋势和信号方向一致
        if trend_direction_matches(trend, cci_signal.direction)
            should_trade = true
            recommended_side = cci_signal.direction
            recommended_position_size = cci_signal.suggested_position_pct
            
            # 根据趋势强度和波动率调整仓位
            if trend.strength == WEAK || vol_state in [HIGH, VERY_HIGH]
                recommended_position_size *= 0.7  # 减少30%
                risk_level = :high
            elseif trend.strength == STRONG && vol_state in [LOW, MEDIUM]
                recommended_position_size *= 1.0  # 保持不变
                risk_level = :low
            end
            
            @info "Trade opportunity detected" side=recommended_side position_size=recommended_position_size
        else
            @warn "Trend and signal direction mismatch"
        end
    else
        if !trend.confirmed
            @debug "Trend not confirmed, no trade"
        end
        if !has_entry_signal(cci_signal)
            @debug "No CCI signal, no trade"
        end
    end
    
    # ========================================================================
    # 6. 构建分析结果
    # ========================================================================
    
    return MarketAnalysis(
        symbol,
        now(),
        trend,
        cci_signal,
        volatility,
        current_price,
        should_trade,
        recommended_side,
        recommended_position_size,
        risk_level
    )
end

"""
    print_market_analysis(analysis::MarketAnalysis)

打印市场分析结果（格式化输出）
"""
function print_market_analysis(analysis::MarketAnalysis)
    println("\n" * "="^70)
    println("市场分析报告 - $(analysis.symbol)")
    println("="^70)
    println("时间: $(analysis.timestamp)")
    println("当前价格: \$$(round(analysis.current_price, digits=2))")
    println()
    
    println("📈 趋势分析:")
    println("  $(get_trend_description(analysis.trend))")
    println("  EMA快线: $(round(analysis.trend.ema_fast, digits=2))")
    println("  EMA慢线: $(round(analysis.trend.ema_slow, digits=2))")
    println("  分离度: $(round(analysis.trend.separation_pct * 100, digits=2))%")
    println()
    
    println("📊 CCI信号:")
    println("  $(get_signal_description(analysis.cci_signal))")
    println()
    
    println("💨 波动率:")
    println("  状态: $(analysis.volatility.state)")
    println("  ATR: $(round(analysis.volatility.atr, digits=2)) ($(round(analysis.volatility.atr_pct*100, digits=2))%)")
    println("  综合波动率: $(round(analysis.volatility.composite*100, digits=2))%")
    println()
    
    println("💡 交易建议:")
    if analysis.should_trade
        side_str = analysis.recommended_side == LONG ? "做多 🟢" : "做空 🔴"
        println("  ✅ 建议交易: $side_str")
        println("  建议仓位: $(round(analysis.recommended_position_size*100, digits=0))%")
        println("  风险等级: $(analysis.risk_level)")
    else
        println("  ⏸️  暂不建议交易")
    end
    
    println("="^70)
end

# ============================================================================
# 批量分析
# ============================================================================

"""
    analyze_multiple_symbols(
        exchange::AbstractExchange,
        symbols::Vector{Symbol},
        config::StrategyConfig
    )::Dict{Symbol, MarketAnalysis}

分析多个交易对
"""
function analyze_multiple_symbols(
    exchange::AbstractExchange,
    symbols::Vector{Symbol},
    config::StrategyConfig
)::Dict{Symbol, MarketAnalysis}
    
    results = Dict{Symbol, MarketAnalysis}()
    
    for symbol in symbols
        try
            analysis = analyze_market(exchange, symbol, config)
            results[symbol] = analysis
        catch e
            @error "Failed to analyze $symbol" exception=e
        end
    end
    
    return results
end

"""
    find_trading_opportunities(
        analyses::Dict{Symbol, MarketAnalysis},
        min_signal_strength::Float64=0.5
    )::Vector{Symbol}

从分析结果中找出交易机会
"""
function find_trading_opportunities(
    analyses::Dict{Symbol, MarketAnalysis},
    min_signal_strength::Float64=0.5
)::Vector{Symbol}
    
    opportunities = Symbol[]
    
    for (symbol, analysis) in analyses
        if analysis.should_trade && 
           analysis.cci_signal.strength >= min_signal_strength
            push!(opportunities, symbol)
        end
    end
    
    # 按信号强度排序
    sort!(opportunities, by = sym -> analyses[sym].cci_signal.strength, rev=true)
    
    return opportunities
end