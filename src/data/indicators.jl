# src/data/indicators.jl

"""
技术指标计算模块

实现所有策略需要的技术指标：
- EMA (指数移动平均)
- ADX (平均趋向指标)
- CCI (顺势指标)
- ATR (平均真实波幅)
"""

using Statistics
using DataFrames

# ============================================================================
# EMA (Exponential Moving Average)
# ============================================================================

"""
    calculate_ema(prices::Vector{Float64}, period::Int)::Vector{Float64}

计算指数移动平均线

参数：
- prices: 价格序列
- period: EMA周期

返回：
- EMA值序列
"""
function calculate_ema(prices::Vector{Float64}, period::Int)::Vector{Float64}
    n = length(prices)
    if n < period
        error("Not enough data points. Need at least $period, got $n")
    end
    
    ema = zeros(Float64, n)
    
    # 平滑因子
    multiplier = 2.0 / (period + 1)
    
    # 第一个EMA值使用SMA
    ema[period] = mean(prices[1:period])
    
    # 计算后续EMA值
    for i in (period + 1):n
        ema[i] = (prices[i] - ema[i-1]) * multiplier + ema[i-1]
    end
    
    # 填充前面的NaN值为第一个有效EMA值
    for i in 1:(period-1)
        ema[i] = ema[period]
    end
    
    return ema
end

"""
    calculate_ema(df::DataFrame, column::Symbol, period::Int)::Vector{Float64}

从DataFrame计算EMA（便捷函数）
"""
function calculate_ema(df::DataFrame, column::Symbol, period::Int)::Vector{Float64}
    return calculate_ema(df[!, column], period)
end

# ============================================================================
# ATR (Average True Range)
# ============================================================================

"""
    calculate_true_range(high::Vector{Float64}, low::Vector{Float64}, close::Vector{Float64})::Vector{Float64}

计算真实波幅（True Range）

TR = max(high - low, |high - prev_close|, |low - prev_close|)
"""
function calculate_true_range(
    high::Vector{Float64},
    low::Vector{Float64},
    close::Vector{Float64}
)::Vector{Float64}
    n = length(high)
    tr = zeros(Float64, n)
    
    # 第一个TR就是高低价差
    tr[1] = high[1] - low[1]
    
    # 后续TR取三个值的最大值
    for i in 2:n
        tr[i] = max(
            high[i] - low[i],                    # 当前高低价差
            abs(high[i] - close[i-1]),           # 当前高价与前收盘价差
            abs(low[i] - close[i-1])             # 当前低价与前收盘价差
        )
    end
    
    return tr
end

"""
    calculate_atr(df::DataFrame, period::Int=14)::Vector{Float64}

计算平均真实波幅（ATR）

参数：
- df: 包含high, low, close列的DataFrame
- period: ATR周期，默认14

返回：
- ATR值序列
"""
function calculate_atr(df::DataFrame, period::Int=14)::Vector{Float64}
    # 计算TR
    tr = calculate_true_range(df.high, df.low, df.close)
    
    # ATR是TR的移动平均（使用Wilder's smoothing，类似EMA）
    n = length(tr)
    atr = zeros(Float64, n)
    
    # 第一个ATR是前period个TR的平均
    atr[period] = mean(tr[1:period])
    
    # 后续使用Wilder's smoothing
    for i in (period + 1):n
        atr[i] = (atr[i-1] * (period - 1) + tr[i]) / period
    end
    
    # 填充前面的值
    for i in 1:(period-1)
        atr[i] = atr[period]
    end
    
    return atr
end

"""
    calculate_atr_percentage(df::DataFrame, period::Int=14)::Vector{Float64}

计算ATR百分比（ATR / 价格）
"""
function calculate_atr_percentage(df::DataFrame, period::Int=14)::Vector{Float64}
    atr = calculate_atr(df, period)
    return atr ./ df.close
end

# ============================================================================
# ADX (Average Directional Index)
# ============================================================================

"""
    calculate_adx(df::DataFrame, period::Int=14)::NamedTuple

计算ADX及相关指标

返回：
- adx: ADX值
- plus_di: +DI值
- minus_di: -DI值
"""
function calculate_adx(df::DataFrame, period::Int=14)::NamedTuple
    n = nrow(df)
    
    # 1. 计算+DM和-DM
    plus_dm = zeros(Float64, n)
    minus_dm = zeros(Float64, n)
    
    for i in 2:n
        high_diff = df.high[i] - df.high[i-1]
        low_diff = df.low[i-1] - df.low[i]
        
        # +DM: 当前高点高于前高点的部分
        if high_diff > low_diff && high_diff > 0
            plus_dm[i] = high_diff
        end
        
        # -DM: 当前低点低于前低点的部分
        if low_diff > high_diff && low_diff > 0
            minus_dm[i] = low_diff
        end
    end
    
    # 2. 计算ATR
    atr = calculate_atr(df, period)
    
    # 3. 平滑+DM和-DM
    smoothed_plus_dm = zeros(Float64, n)
    smoothed_minus_dm = zeros(Float64, n)
    
    smoothed_plus_dm[period] = sum(plus_dm[1:period])
    smoothed_minus_dm[period] = sum(minus_dm[1:period])
    
    for i in (period + 1):n
        smoothed_plus_dm[i] = smoothed_plus_dm[i-1] - smoothed_plus_dm[i-1]/period + plus_dm[i]
        smoothed_minus_dm[i] = smoothed_minus_dm[i-1] - smoothed_minus_dm[i-1]/period + minus_dm[i]
    end
    
    # 4. 计算+DI和-DI
    plus_di = zeros(Float64, n)
    minus_di = zeros(Float64, n)
    
    for i in period:n
        if atr[i] != 0
            plus_di[i] = (smoothed_plus_dm[i] / atr[i]) * 100
            minus_di[i] = (smoothed_minus_dm[i] / atr[i]) * 100
        end
    end
    
    # 5. 计算DX
    dx = zeros(Float64, n)
    
    for i in period:n
        di_sum = plus_di[i] + minus_di[i]
        if di_sum != 0
            dx[i] = abs(plus_di[i] - minus_di[i]) / di_sum * 100
        end
    end
    
    # 6. 计算ADX (DX的移动平均)
    adx = zeros(Float64, n)
    
    # 第一个ADX是前period个DX的平均
    if period * 2 <= n
        adx[period * 2 - 1] = mean(dx[period:(period * 2 - 1)])
        
        # 后续使用平滑
        for i in (period * 2):n
            adx[i] = (adx[i-1] * (period - 1) + dx[i]) / period
        end
    end
    
    # 填充前面的值
    fill_value = adx[period * 2 - 1]
    for i in 1:(period * 2 - 2)
        adx[i] = fill_value
    end
    
    return (
        adx = adx,
        plus_di = plus_di,
        minus_di = minus_di,
        dx = dx
    )
end

# ============================================================================
# CCI (Commodity Channel Index)
# ============================================================================

"""
    calculate_cci(df::DataFrame, period::Int=14)::Vector{Float64}

计算顺势指标（CCI）

CCI = (TP - SMA(TP)) / (0.015 × MD)
其中：
- TP (Typical Price) = (High + Low + Close) / 3
- SMA = Simple Moving Average
- MD = Mean Deviation
"""
function calculate_cci(df::DataFrame, period::Int=14)::Vector{Float64}
    n = nrow(df)
    
    # 1. 计算典型价格 (Typical Price)
    tp = (df.high .+ df.low .+ df.close) ./ 3
    
    # 2. 计算TP的简单移动平均
    sma_tp = zeros(Float64, n)
    
    for i in period:n
        sma_tp[i] = mean(tp[(i - period + 1):i])
    end
    
    # 填充前面的值
    for i in 1:(period-1)
        sma_tp[i] = sma_tp[period]
    end
    
    # 3. 计算平均偏差 (Mean Deviation)
    md = zeros(Float64, n)
    
    for i in period:n
        deviations = abs.(tp[(i - period + 1):i] .- sma_tp[i])
        md[i] = mean(deviations)
    end
    
    # 填充前面的值
    for i in 1:(period-1)
        md[i] = md[period]
    end
    
    # 4. 计算CCI
    cci = zeros(Float64, n)
    
    for i in 1:n
        if md[i] != 0
            cci[i] = (tp[i] - sma_tp[i]) / (0.015 * md[i])
        end
    end
    
    return cci
end

# ============================================================================
# RSI (Relative Strength Index) - 额外指标
# ============================================================================

"""
    calculate_rsi(prices::Vector{Float64}, period::Int=14)::Vector{Float64}

计算相对强弱指标（RSI）

RSI = 100 - (100 / (1 + RS))
其中 RS = 平均涨幅 / 平均跌幅
"""
function calculate_rsi(prices::Vector{Float64}, period::Int=14)::Vector{Float64}
    n = length(prices)
    rsi = zeros(Float64, n)
    
    # 计算价格变化
    changes = diff(prices)
    
    # 分离涨跌
    gains = max.(changes, 0.0)
    losses = abs.(min.(changes, 0.0))
    
    # 第一个周期使用简单平均
    avg_gain = mean(gains[1:period])
    avg_loss = mean(losses[1:period])
    
    # 计算第一个RSI
    if avg_loss != 0
        rs = avg_gain / avg_loss
        rsi[period + 1] = 100 - (100 / (1 + rs))
    else
        rsi[period + 1] = 100
    end
    
    # 后续使用Wilder's smoothing
    for i in (period + 2):n
        avg_gain = (avg_gain * (period - 1) + gains[i - 1]) / period
        avg_loss = (avg_loss * (period - 1) + losses[i - 1]) / period
        
        if avg_loss != 0
            rs = avg_gain / avg_loss
            rsi[i] = 100 - (100 / (1 + rs))
        else
            rsi[i] = 100
        end
    end
    
    # 填充前面的值
    for i in 1:period
        rsi[i] = rsi[period + 1]
    end
    
    return rsi
end

"""
    calculate_rsi(df::DataFrame, column::Symbol=:close, period::Int=14)::Vector{Float64}

从DataFrame计算RSI
"""
function calculate_rsi(df::DataFrame, column::Symbol=:close, period::Int=14)::Vector{Float64}
    return calculate_rsi(df[!, column], period)
end

# ============================================================================
# 布林带 (Bollinger Bands) - 额外指标
# ============================================================================

"""
    calculate_bollinger_bands(prices::Vector{Float64}, period::Int=20, num_std::Float64=2.0)::NamedTuple

计算布林带

返回：
- upper: 上轨
- middle: 中轨（SMA）
- lower: 下轨
"""
function calculate_bollinger_bands(
    prices::Vector{Float64},
    period::Int=20,
    num_std::Float64=2.0
)::NamedTuple
    n = length(prices)
    
    upper = zeros(Float64, n)
    middle = zeros(Float64, n)
    lower = zeros(Float64, n)
    
    for i in period:n
        window = prices[(i - period + 1):i]
        sma = mean(window)
        std_dev = std(window)
        
        middle[i] = sma
        upper[i] = sma + num_std * std_dev
        lower[i] = sma - num_std * std_dev
    end
    
    # 填充前面的值
    for i in 1:(period-1)
        middle[i] = middle[period]
        upper[i] = upper[period]
        lower[i] = lower[period]
    end
    
    return (
        upper = upper,
        middle = middle,
        lower = lower
    )
end

# ============================================================================
# 组合指标计算（便捷函数）
# ============================================================================

"""
    calculate_all_indicators(df::DataFrame)::DataFrame

计算所有指标并添加到DataFrame

参数：
- df: 包含OHLCV数据的DataFrame

返回：
- 添加了所有指标的DataFrame
"""
function calculate_all_indicators(df::DataFrame)::DataFrame
    result = copy(df)
    
    # EMA
    result.ema_20 = calculate_ema(result, :close, 20)
    result.ema_60 = calculate_ema(result, :close, 60)
    
    # ATR
    result.atr = calculate_atr(result, 14)
    result.atr_pct = calculate_atr_percentage(result, 14)
    
    # ADX
    adx_data = calculate_adx(result, 14)
    result.adx = adx_data.adx
    result.plus_di = adx_data.plus_di
    result.minus_di = adx_data.minus_di
    
    # CCI
    result.cci = calculate_cci(result, 14)
    
    # RSI
    result.rsi = calculate_rsi(result, :close, 14)
    
    return result
end

# ============================================================================
# 指标验证
# ============================================================================

"""
    validate_indicators(df::DataFrame)::Bool

验证指标计算是否正确（检查NaN和Inf）
"""
function validate_indicators(df::DataFrame)::Bool
    for col in names(df)
        if eltype(df[!, col]) <: Number
            if any(isnan, df[!, col]) || any(isinf, df[!, col])
                @warn "Invalid values found in column: $col"
                return false
            end
        end
    end
    return true
end