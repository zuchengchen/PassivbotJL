# src/strategy/trend.jl

"""
趋势检测模块

基于EMA和ADX判断市场趋势
"""

using DataFrames
using Dates

# ============================================================================
# 趋势检测
# ============================================================================

"""
    detect_trend(
        klines::DataFrame,
        config::TrendConfig
    )::TrendState

检测市场趋势

参数：
- klines: K线数据（必须已计算指标）
- config: 趋势配置

返回：
- TrendState: 趋势状态
"""
function detect_trend(
    klines::DataFrame,
    config::TrendConfig
)::TrendState
    
    # 确保数据足够
    if nrow(klines) < max(config.ema_fast_period, config.ema_slow_period, config.adx_period)
        error("Insufficient data for trend detection")
    end
    
    # ========================================================================
    # 1. 计算主趋势（使用配置的时间框架）
    # ========================================================================
    
    # 计算EMA
    ema_fast = calculate_ema(klines, :close, config.ema_fast_period)
    ema_slow = calculate_ema(klines, :close, config.ema_slow_period)
    
    # 最新EMA值
    current_ema_fast = ema_fast[end]
    current_ema_slow = ema_slow[end]
    
    # EMA分离度（百分比）
    separation_pct = (current_ema_fast - current_ema_slow) / current_ema_slow
    
    # 判断主趋势方向
    primary_trend = if separation_pct > config.trend_threshold
        UPTREND
    elseif separation_pct < -config.trend_threshold
        DOWNTREND
    else
        RANGING
    end
    
    # ========================================================================
    # 2. 计算ADX（趋势强度）
    # ========================================================================
    
    adx_data = calculate_adx(klines, config.adx_period)
    current_adx = adx_data.adx[end]
    
    # 判断趋势强度
    strength = if current_adx > 30
        STRONG
    elseif current_adx > config.adx_threshold
        MODERATE
    else
        WEAK
    end
    
    # ========================================================================
    # 3. 次级确认（如果启用）
    # ========================================================================
    
    secondary_trend = primary_trend  # 默认与主趋势相同
    confirmed = true
    
    if config.confirmation_required
        # 简化版：检查短期EMA斜率
        # 如果需要更复杂的确认，可以获取次级时间框架数据
        
        # 计算最近几根K线的EMA斜率
        lookback = min(5, length(ema_fast) - 1)
        ema_fast_slope = (ema_fast[end] - ema_fast[end - lookback]) / lookback
        
        # 次级趋势判断
        if ema_fast_slope > 0
            secondary_trend = UPTREND
        elseif ema_fast_slope < 0
            secondary_trend = DOWNTREND
        else
            secondary_trend = RANGING
        end
        
        # 确认：主趋势和次级趋势一致，且ADX足够
        confirmed = (primary_trend == secondary_trend) && 
                   (current_adx >= config.adx_threshold)
    end
    
    # ========================================================================
    # 4. 构建趋势状态
    # ========================================================================
    
    return TrendState(
        primary_trend,
        secondary_trend,
        strength,
        confirmed,
        current_ema_fast,
        current_ema_slow,
        separation_pct,
        current_adx,
        now()
    )
end

"""
    detect_trend_from_symbol(
        exchange::AbstractExchange,
        symbol::Symbol,
        config::TrendConfig
    )::TrendState

直接从交易对检测趋势（获取数据并分析）
"""
function detect_trend_from_symbol(
    exchange::AbstractExchange,
    symbol::Symbol,
    config::TrendConfig
)::TrendState
    
    # 计算需要的K线数量
    required_periods = max(
        config.ema_slow_period,
        config.adx_period
    ) + 20  # 多获取一些以确保准确
    
    # 获取K线数据
    klines = get_klines(exchange, symbol, config.timeframe_primary, required_periods)
    
    # 计算所有指标
    klines_with_indicators = calculate_all_indicators(klines)
    
    # 检测趋势
    return detect_trend(klines_with_indicators, config)
end

# ============================================================================
# 趋势分析辅助函数
# ============================================================================

"""
    is_trending(trend::TrendState)::Bool

判断是否处于明确的趋势中
"""
function is_trending(trend::TrendState)::Bool
    return trend.primary_trend != RANGING && trend.confirmed
end

"""
    is_strong_trend(trend::TrendState)::Bool

判断是否为强趋势
"""
function is_strong_trend(trend::TrendState)::Bool
    return trend.strength == STRONG && trend.confirmed
end

"""
    trend_direction_matches(trend::TrendState, side::Side)::Bool

判断趋势方向是否与交易方向一致
"""
function trend_direction_matches(trend::TrendState, side::Side)::Bool
    if side == LONG
        return trend.primary_trend == UPTREND
    else  # SHORT
        return trend.primary_trend == DOWNTREND
    end
end

"""
    get_trend_description(trend::TrendState)::String

获取趋势的文字描述
"""
function get_trend_description(trend::TrendState)::String
    direction = if trend.primary_trend == UPTREND
        "上涨"
    elseif trend.primary_trend == DOWNTREND
        "下跌"
    else
        "震荡"
    end
    
    strength_str = if trend.strength == STRONG
        "强"
    elseif trend.strength == MODERATE
        "中等"
    else
        "弱"
    end
    
    confirmed_str = trend.confirmed ? "已确认" : "未确认"
    
    return "$(direction)趋势 ($(strength_str), $(confirmed_str), ADX=$(round(trend.adx, digits=1)))"
end

"""
    should_trade_on_trend(trend::TrendState, min_strength::TrendStrength=MODERATE)::Bool

判断趋势是否足够强，可以交易
"""
function should_trade_on_trend(trend::TrendState, min_strength::TrendStrength=MODERATE)::Bool
    # 必须确认
    if !trend.confirmed
        return false
    end
    
    # 不能是震荡
    if trend.primary_trend == RANGING
        return false
    end
    
    # 检查强度
    strength_ok = if min_strength == STRONG
        trend.strength == STRONG
    elseif min_strength == MODERATE
        trend.strength in [MODERATE, STRONG]
    else  # WEAK
        true
    end
    
    return strength_ok
end