# src/backtest/signal_generator.jl

"""
信号生成器

职责：
- 基于K线计算技术指标
- 判断趋势方向和强度
- 检测超买超卖
- 生成开仓信号
- 动态调整网格参数
"""

using Dates
using DataFrames
using Statistics
using Logging

# ============================================================================
# 信号生成器
# ============================================================================

"""
    SignalGenerator

信号生成器
"""
mutable struct SignalGenerator
    # 配置
    config::Any  # StrategyConfig
    
    # K线数据缓存（用于计算指标）
    bar_data::Dict{String, DataFrame}
    
    # 指标缓存（避免重复计算）
    indicators_cache::Dict{Symbol, Dict{String, Any}}
    
    # 最后生成信号的时间
    last_signal_time::Dict{Symbol, DateTime}
    
    # 信号冷却期（避免频繁开仓）
    signal_cooldown::Period
    
    function SignalGenerator(config, bar_data::Dict{String, DataFrame})
        new(
            config,
            bar_data,
            Dict{Symbol, Dict{String, Any}}(),
            Dict{Symbol, DateTime}(),
            Hour(1)  # ✅ 从15分钟改为1小时
        )
    end
end

# ============================================================================
# 指标计算（复用现有的indicators.jl）
# ============================================================================

"""
    calculate_indicators!(sg::SignalGenerator, symbol::Symbol, timeframe::String, current_time::DateTime)

计算技术指标
"""
function calculate_indicators!(
    sg::SignalGenerator,
    symbol::Symbol,
    timeframe::String,
    current_time::DateTime
)
    
    if !haskey(sg.bar_data, timeframe)
        @warn "No bar data for timeframe $timeframe"
        return nothing
    end
    
    bars = sg.bar_data[timeframe]
    
    if nrow(bars) < 50
        @debug "Not enough bars for indicators" timeframe=timeframe bars=nrow(bars)
        return nothing
    end
    
    # 只使用当前时间之前的数据（避免未来函数）
    historical_bars = bars[bars.timestamp .<= current_time, :]
    
    if nrow(historical_bars) < 50
        return nothing
    end
    
    # 计算EMA
    ema_fast = calculate_ema(historical_bars.close, 12)
    ema_slow = calculate_ema(historical_bars.close, 26)
    
    # 计算ATR
    atr = calculate_atr(historical_bars.high, historical_bars.low, historical_bars.close, 14)
    atr_pct = (atr / historical_bars.close[end]) * 100
    
    # 计算ADX
    adx = calculate_adx(historical_bars.high, historical_bars.low, historical_bars.close, 14)
    
    # 计算CCI
    cci = calculate_cci(historical_bars.high, historical_bars.low, historical_bars.close, 20)
    
    # 缓存指标
    if !haskey(sg.indicators_cache, symbol)
        sg.indicators_cache[symbol] = Dict{String, Any}()
    end
    
    sg.indicators_cache[symbol][timeframe] = Dict(
        "ema_fast" => ema_fast,
        "ema_slow" => ema_slow,
        "atr" => atr,
        "atr_pct" => atr_pct,
        "adx" => adx,
        "cci" => cci,
        "close" => historical_bars.close[end],
        "timestamp" => current_time
    )
    
    return sg.indicators_cache[symbol][timeframe]
end

# ============================================================================
# EMA计算（简化版）
# ============================================================================

"""
    calculate_ema(prices::Vector{Float64}, period::Int)::Float64

计算指数移动平均（返回最新值）
"""
function calculate_ema(prices::Vector{Float64}, period::Int)::Float64
    
    if length(prices) < period
        return prices[end]
    end
    
    # 初始SMA
    sma = mean(prices[1:period])
    
    # EMA计算
    multiplier = 2.0 / (period + 1)
    ema = sma
    
    for i in (period+1):length(prices)
        ema = (prices[i] - ema) * multiplier + ema
    end
    
    return ema
end

"""
    calculate_atr(high::Vector{Float64}, low::Vector{Float64}, close::Vector{Float64}, period::Int)::Float64

计算平均真实波幅
"""
function calculate_atr(
    high::Vector{Float64},
    low::Vector{Float64},
    close::Vector{Float64},
    period::Int
)::Float64
    
    n = length(close)
    
    if n < period + 1
        return high[end] - low[end]
    end
    
    # 计算真实波幅
    tr = zeros(n - 1)
    for i in 2:n
        tr[i-1] = max(
            high[i] - low[i],
            abs(high[i] - close[i-1]),
            abs(low[i] - close[i-1])
        )
    end
    
    # ATR = TR的移动平均
    return mean(tr[max(1, end-period+1):end])
end

"""
    calculate_adx(high::Vector{Float64}, low::Vector{Float64}, close::Vector{Float64}, period::Int)::Float64

计算平均趋向指数（简化版）
"""
function calculate_adx(
    high::Vector{Float64},
    low::Vector{Float64},
    close::Vector{Float64},
    period::Int
)::Float64
    
    n = length(close)
    
    if n < period + 1
        return 0.0
    end
    
    # 简化：使用价格变化率估算ADX
    price_changes = abs.(diff(close))
    avg_change = mean(price_changes[max(1, end-period+1):end])
    
    # 归一化到0-100
    return min(100.0, avg_change / close[end] * 1000)
end

"""
    calculate_cci(high::Vector{Float64}, low::Vector{Float64}, close::Vector{Float64}, period::Int)::Float64

计算商品通道指数
"""
function calculate_cci(
    high::Vector{Float64},
    low::Vector{Float64},
    close::Vector{Float64},
    period::Int
)::Float64
    
    n = length(close)
    
    if n < period
        return 0.0
    end
    
    # 典型价格
    tp = (high .+ low .+ close) ./ 3
    
    # 最近period个TP的均值
    sma_tp = mean(tp[max(1, end-period+1):end])
    
    # 平均偏差
    mad = mean(abs.(tp[max(1, end-period+1):end] .- sma_tp))
    
    # CCI
    if mad == 0.0
        return 0.0
    end
    
    cci = (tp[end] - sma_tp) / (0.015 * mad)
    
    return cci
end

# ============================================================================
# 趋势判断
# ============================================================================

"""
    detect_trend(sg::SignalGenerator, symbol::Symbol, current_time::DateTime)::Union{Nothing, NamedTuple}

检测趋势
"""
function detect_trend(
    sg::SignalGenerator,
    symbol::Symbol,
    current_time::DateTime
)::Union{Nothing, NamedTuple}
    
    # 计算15分钟和5分钟指标
    ind_15m = calculate_indicators!(sg, symbol, "15m", current_time)
    ind_5m = calculate_indicators!(sg, symbol, "5m", current_time)
    
    if isnothing(ind_15m) || isnothing(ind_5m)
        return nothing
    end
    
    # 主趋势（15分钟）
    primary_trend = if ind_15m["ema_fast"] > ind_15m["ema_slow"]
        :UPTREND
    elseif ind_15m["ema_fast"] < ind_15m["ema_slow"]
        :DOWNTREND
    else
        :RANGING
    end
    
    # 次级趋势（5分钟）
    secondary_trend = if ind_5m["ema_fast"] > ind_5m["ema_slow"]
        :UPTREND
    elseif ind_5m["ema_fast"] < ind_5m["ema_slow"]
        :DOWNTREND
    else
        :RANGING
    end
    
    # EMA分离度
    separation_pct = abs(ind_15m["ema_fast"] - ind_15m["ema_slow"]) / ind_15m["ema_slow"] * 100
    
    # 趋势强度
    strength = if ind_15m["adx"] > 40
        :STRONG
    elseif ind_15m["adx"] > 25
        :MODERATE
    else
        :WEAK
    end
    
    # 双重确认
    confirmed = (primary_trend == secondary_trend) && (primary_trend != :RANGING)
    
    return (
        primary_trend = primary_trend,
        secondary_trend = secondary_trend,
        strength = strength,
        confirmed = confirmed,
        ema_fast = ind_15m["ema_fast"],
        ema_slow = ind_15m["ema_slow"],
        separation_pct = separation_pct,
        adx = ind_15m["adx"],
        timestamp = current_time
    )
end

# ============================================================================
# CCI信号
# ============================================================================

"""
    generate_cci_signal(sg::SignalGenerator, symbol::Symbol, current_time::DateTime)::Union{Nothing, NamedTuple}

生成CCI信号
"""
function generate_cci_signal(
    sg::SignalGenerator,
    symbol::Symbol,
    current_time::DateTime
)::Union{Nothing, NamedTuple}
    
    ind_5m = calculate_indicators!(sg, symbol, "5m", current_time)
    
    if isnothing(ind_5m)
        return nothing
    end
    
    cci = ind_5m["cci"]
    
    # CCI信号逻辑
    direction = nothing
    level = 0
    strength = 0.0
    suggested_position_pct = 0.0
    
    if cci < -200
        # 强超卖
        direction = :LONG
        level = 3
        strength = 1.0
        suggested_position_pct = 1.0
        
    elseif cci < -100
        # 中等超卖
        direction = :LONG
        level = 2
        strength = 0.7
        suggested_position_pct = 0.7
        
    elseif cci < -50
        # 轻度超卖
        direction = :LONG
        level = 1
        strength = 0.4
        suggested_position_pct = 0.4
        
    elseif cci > 200
        # 强超买
        direction = :SHORT
        level = 3
        strength = 1.0
        suggested_position_pct = 1.0
        
    elseif cci > 100
        # 中等超买
        direction = :SHORT
        level = 2
        strength = 0.7
        suggested_position_pct = 0.7
        
    elseif cci > 50
        # 轻度超买
        direction = :SHORT
        level = 1
        strength = 0.4
        suggested_position_pct = 0.4
    end
    
    if isnothing(direction)
        return nothing
    end
    
    return (
        direction = direction,
        strength = strength,
        level = level,
        cci_value = cci,
        suggested_position_pct = suggested_position_pct,
        timestamp = current_time
    )
end

# ============================================================================
# 主信号生成
# ============================================================================

"""
    generate_signal(sg::SignalGenerator, bar_event, current_time::DateTime)::Union{Nothing, NamedTuple}

生成交易信号
"""
function generate_signal(
    sg::SignalGenerator,
    bar_event,
    current_time::DateTime
)::Union{Nothing, NamedTuple}
    
    symbol = bar_event.symbol
    
    # 检查冷却期
    if haskey(sg.last_signal_time, symbol)
        elapsed = current_time - sg.last_signal_time[symbol]
        if elapsed < sg.signal_cooldown
            @debug "Signal cooldown active" symbol=symbol remaining=sg.signal_cooldown-elapsed
            return nothing
        end
    end
    
    # 检测趋势
    trend = detect_trend(sg, symbol, current_time)
    
    if isnothing(trend)
        return nothing
    end
    
    # 生成CCI信号
    cci_signal = generate_cci_signal(sg, symbol, current_time)
    
    if isnothing(cci_signal)
        return nothing
    end
    
    # 信号过滤：趋势与CCI方向一致
    trend_direction = trend.primary_trend
    cci_direction = cci_signal.direction
    
    # 做多条件：上升趋势 + CCI超卖
    long_condition = (trend_direction == :UPTREND) && (cci_direction == :LONG) && trend.confirmed
    
    # 做空条件：下降趋势 + CCI超买
    short_condition = (trend_direction == :DOWNTREND) && (cci_direction == :SHORT) && trend.confirmed
    
    if !long_condition && !short_condition
        @debug "Signal filtered out" trend=trend_direction cci=cci_direction confirmed=trend.confirmed
        return nothing
    end
    
    # 确定信号类型
    signal_type = long_condition ? :LONG_ENTRY : :SHORT_ENTRY
    
    # 动态调整网格参数
    ind_15m = sg.indicators_cache[symbol]["15m"]
    
    # 基于ATR调整网格间距
    base_spacing = sg.config.grid_spacing
    atr_pct = ind_15m["atr_pct"]
    
    # ATR高时增大间距，ATR低时减小间距
    adjusted_spacing = base_spacing * (atr_pct / 1.0)  # 假设1%为基准ATR
    adjusted_spacing = clamp(adjusted_spacing, base_spacing * 0.5, base_spacing * 2.0)
    
    # 基于趋势强度调整最大层数
    max_levels = if trend.strength == :STRONG
        sg.config.max_grid_levels
    elseif trend.strength == :MODERATE
        Int(ceil(sg.config.max_grid_levels * 0.8))
    else
        Int(ceil(sg.config.max_grid_levels * 0.6))
    end
    
    # 基于CCI级别调整加倍因子
    ddown_factor = if cci_signal.level == 3
        sg.config.ddown_factor * 1.2  # 强信号，更激进
    elseif cci_signal.level == 2
        sg.config.ddown_factor
    else
        sg.config.ddown_factor * 0.8  # 弱信号，更保守
    end
    
    # 记录信号时间
    sg.last_signal_time[symbol] = current_time
    
    @info "Signal generated" symbol=symbol type=signal_type strength=cci_signal.strength cci=cci_signal.cci_value adx=trend.adx
    
    # 返回SignalEvent（使用NamedTuple）
    return (
        timestamp = current_time,
        symbol = symbol,
        signal_type = signal_type,
        strength = cci_signal.strength,
        grid_spacing = adjusted_spacing,
        max_levels = max_levels,
        ddown_factor = ddown_factor,
        indicators = Dict{Symbol, Any}(
            :cci => cci_signal.cci_value,
            :adx => trend.adx,
            :ema_fast => trend.ema_fast,
            :ema_slow => trend.ema_slow,
            :atr_pct => atr_pct,
            :trend => String(trend.primary_trend)
        )
    )
end