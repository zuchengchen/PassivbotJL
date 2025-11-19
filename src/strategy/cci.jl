# src/strategy/cci.jl

"""
CCI信号生成模块

基于CCI指标生成超买超卖入场信号
"""

using DataFrames
using Dates

# ============================================================================
# CCI信号生成
# ============================================================================

"""
    generate_cci_signal(
        klines::DataFrame,
        trend::TrendState,
        config::CCIConfig
    )::CCISignal

生成CCI入场信号

参数：
- klines: K线数据（必须已计算CCI）
- trend: 当前趋势状态
- config: CCI配置

返回：
- CCISignal: 入场信号
"""
function generate_cci_signal(
    klines::DataFrame,
    trend::TrendState,
    config::CCIConfig
)::CCISignal
    
    # 计算CCI（如果还没有）
    if !hasproperty(klines, :cci)
        cci_values = calculate_cci(klines, config.period)
    else
        cci_values = klines.cci
    end
    
    current_cci = cci_values[end]
    
    # ========================================================================
    # 只在趋势方向上寻找信号
    # ========================================================================
    
    # 上涨趋势 - 寻找超卖做多信号
    if trend.primary_trend == UPTREND && trend.confirmed
        return generate_long_signal(current_cci, config)
    
    # 下跌趋势 - 寻找超买做空信号
    elseif trend.primary_trend == DOWNTREND && trend.confirmed
        return generate_short_signal(current_cci, config)
    
    # 无趋势或未确认 - 不交易
    else
        return CCISignal(
            nothing,
            0.0,
            0,
            current_cci,
            0.0,
            now()
        )
    end
end

"""
    generate_long_signal(cci::Float64, config::CCIConfig)::CCISignal

生成做多信号（基于超卖）
"""
function generate_long_signal(cci::Float64, config::CCIConfig)::CCISignal
    
    # 检查每个阈值级别
    for (i, threshold) in enumerate(config.long_thresholds)
        if cci < threshold
            # 找到对应的级别
            level = length(config.long_thresholds) - i + 1
            
            # 信号强度（CCI越低，信号越强）
            # 归一化到0-1之间
            strength = if i == length(config.long_thresholds)
                1.0  # 最深的超卖，最强信号
            else
                0.3 + 0.7 * (i / length(config.long_thresholds))
            end
            
            # 建议仓位大小
            suggested_position = config.long_position_sizes[length(config.long_thresholds) - i + 1]
            
            return CCISignal(
                LONG,
                strength,
                level,
                cci,
                suggested_position,
                now()
            )
        end
    end
    
    # 没有达到任何阈值
    return CCISignal(nothing, 0.0, 0, cci, 0.0, now())
end

"""
    generate_short_signal(cci::Float64, config::CCIConfig)::CCISignal

生成做空信号（基于超买）
"""
function generate_short_signal(cci::Float64, config::CCIConfig)::CCISignal
    
    # 检查每个阈值级别
    for (i, threshold) in enumerate(config.short_thresholds)
        if cci > threshold
            # 找到对应的级别
            level = length(config.short_thresholds) - i + 1
            
            # 信号强度
            strength = if i == length(config.short_thresholds)
                1.0
            else
                0.3 + 0.7 * (i / length(config.short_thresholds))
            end
            
            # 建议仓位大小
            suggested_position = config.short_position_sizes[length(config.short_thresholds) - i + 1]
            
            return CCISignal(
                SHORT,
                strength,
                level,
                cci,
                suggested_position,
                now()
            )
        end
    end
    
    # 没有达到任何阈值
    return CCISignal(nothing, 0.0, 0, cci, 0.0, now())
end

"""
    generate_cci_signal_from_symbol(
        exchange::AbstractExchange,
        symbol::Symbol,
        trend::TrendState,
        config::CCIConfig
    )::CCISignal

直接从交易对生成CCI信号
"""
function generate_cci_signal_from_symbol(
    exchange::AbstractExchange,
    symbol::Symbol,
    trend::TrendState,
    config::CCIConfig
)::CCISignal
    
    # 获取K线数据
    required_periods = config.period + 20
    klines = get_klines(exchange, symbol, config.timeframe, required_periods)
    
    # 计算CCI
    klines.cci = calculate_cci(klines, config.period)
    
    # 生成信号
    return generate_cci_signal(klines, trend, config)
end

# ============================================================================
# 信号分析辅助函数
# ============================================================================

"""
    has_entry_signal(signal::CCISignal)::Bool

判断是否有入场信号
"""
function has_entry_signal(signal::CCISignal)::Bool
    return !isnothing(signal.direction)
end

"""
    is_strong_signal(signal::CCISignal, min_strength::Float64=0.7)::Bool

判断是否为强信号
"""
function is_strong_signal(signal::CCISignal, min_strength::Float64=0.7)::Bool
    return has_entry_signal(signal) && signal.strength >= min_strength
end

"""
    get_signal_description(signal::CCISignal)::String

获取信号的文字描述
"""
function get_signal_description(signal::CCISignal)::String
    if !has_entry_signal(signal)
        return "无信号 (CCI=$(round(signal.cci_value, digits=1)))"
    end
    
    direction = signal.direction == LONG ? "做多" : "做空"
    level_str = ["弱", "中", "强"][min(signal.level, 3)]
    
    return "$(direction)信号 (级别$signal.level-$(level_str), 强度=$(round(signal.strength*100, digits=0))%, CCI=$(round(signal.cci_value, digits=1)))"
end

"""
    should_enter_position(signal::CCISignal, min_level::Int=1)::Bool

判断是否应该入场

参数：
- signal: CCI信号
- min_level: 最小级别要求（1=弱信号也可，2=至少中等，3=只接受强信号）
"""
function should_enter_position(signal::CCISignal, min_level::Int=1)::Bool
    return has_entry_signal(signal) && signal.level >= min_level
end