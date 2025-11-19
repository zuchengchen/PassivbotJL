# src/data/tick_data.jl

"""
Tick数据处理
"""

using Dates
using DataFrames
using CSV
using HTTP
using JSON3
using ProgressMeter
using UUIDs  # 添加这个

# ============================================================================
# Tick数据结构
# ============================================================================

"""
    TickData

单个Tick数据
"""
struct TickData
    timestamp::DateTime
    symbol::Symbol
    price::Float64
    quantity::Float64
    is_buyer_maker::Bool
    trade_id::Int64
end

# ============================================================================
# 历史Tick数据下载
# ============================================================================

"""
    download_agg_trades(
        symbol::String,
        start_time::DateTime,
        end_time::DateTime;
        testnet::Bool=false
    )::DataFrame

下载币安aggTrades历史数据

参数：
- symbol: 交易对，如"BTCUSDT"
- start_time: 开始时间
- end_time: 结束时间
- testnet: 是否使用测试网

返回：
- DataFrame包含: timestamp, price, quantity, is_buyer_maker, trade_id
"""
function download_agg_trades(
    symbol::String,
    start_time::DateTime,
    end_time::DateTime;
    testnet::Bool=false
)::DataFrame
    
    base_url = if testnet
        "https://testnet.binancefuture.com"
    else
        "https://fapi.binance.com"
    end
    
    endpoint = "/fapi/v1/aggTrades"
    
    # 转换为毫秒时间戳
    start_ms = Int64(datetime2unix(start_time) * 1000)
    end_ms = Int64(datetime2unix(end_time) * 1000)
    
    all_trades = []
    current_start = start_ms
    
    @info "Downloading aggTrades for $symbol" start_time=start_time end_time=end_time
    
    # 分批下载（每次最多1000条）
    pbar = Progress(0, desc="Downloading trades...")
    
    while current_start < end_ms
        try
            # 构建请求
            params = Dict(
                "symbol" => symbol,
                "startTime" => current_start,
                "endTime" => end_ms,
                "limit" => 1000
            )
            
            query_string = join(["$k=$v" for (k, v) in params], "&")
            url = "$base_url$endpoint?$query_string"
            
            # 发送请求
            response = HTTP.get(url)
            trades = JSON3.read(String(response.body))
            
            if isempty(trades)
                break
            end
            
            # 添加到结果
            append!(all_trades, trades)
            
            # 更新进度
            update!(pbar, length(all_trades))
            
            # 更新起始时间（最后一条的时间+1ms）
            current_start = trades[end].T + 1
            
            # 避免触发速率限制
            sleep(0.1)
            
        catch e
            @error "Error downloading trades" error=e
            sleep(1)
        end
    end
    
    finish!(pbar)
    
    if isempty(all_trades)
        @warn "No trades downloaded"
        return DataFrame(
            timestamp = DateTime[],
            price = Float64[],
            quantity = Float64[],
            is_buyer_maker = Bool[],
            trade_id = Int64[]
        )
    end
    
    # 转换为DataFrame
    df = DataFrame(
        timestamp = [unix2datetime(t.T / 1000) for t in all_trades],
        price = [parse(Float64, t.p) for t in all_trades],
        quantity = [parse(Float64, t.q) for t in all_trades],
        is_buyer_maker = [t.m for t in all_trades],
        trade_id = [t.a for t in all_trades]
    )
    
    @info "Downloaded $(nrow(df)) trades"
    
    return df
end

"""
    save_tick_data(df::DataFrame, filepath::String)

保存Tick数据到CSV
"""
function save_tick_data(df::DataFrame, filepath::String)
    CSV.write(filepath, df)
    @info "Tick data saved to $filepath"
end

"""
    load_tick_data(filepath::String)::DataFrame

从CSV加载Tick数据
"""
function load_tick_data(filepath::String)::DataFrame
    df = CSV.read(filepath, DataFrame)
    
    # 确保timestamp是DateTime类型
    if eltype(df.timestamp) != DateTime
        df.timestamp = DateTime.(df.timestamp)
    end
    
    @info "Loaded $(nrow(df)) ticks from $filepath"
    
    return df
end

# ============================================================================
# Tick数据转K线
# ============================================================================

"""
    ticks_to_bars(
        ticks::DataFrame,
        timeframe::String
    )::DataFrame

将Tick数据聚合为K线
"""
function ticks_to_bars(
    ticks::DataFrame,
    timeframe::String
)::DataFrame
    
    if nrow(ticks) == 0
        return DataFrame(
            timestamp = DateTime[],
            open = Float64[],
            high = Float64[],
            low = Float64[],
            close = Float64[],
            volume = Float64[]
        )
    end
    
    # 解析时间周期
    period = parse_timeframe(timeframe)
    
    # 按时间分组
    ticks_sorted = sort(ticks, :timestamp)
    
    # 修复：使用正确的 floor 语法
    # 将每个时间戳向下取整到最近的周期开始
    ticks_sorted.bar_time = floor.(ticks_sorted.timestamp, period)
    
    # 分组聚合
    bars = combine(groupby(ticks_sorted, :bar_time)) do group
        (
            timestamp = group[1, :bar_time],  # 使用bar_time作为时间戳
            open = group[1, :price],
            high = maximum(group.price),
            low = minimum(group.price),
            close = group[end, :price],
            volume = sum(group.quantity)
        )
    end
    
    # 按时间排序
    sort!(bars, :timestamp)
    
    return bars
end

"""
    parse_timeframe(timeframe::String)::Period

解析时间周期字符串
"""
function parse_timeframe(timeframe::String)::Period
    # 提取数字和单位
    m = match(r"(\d+)([mhd])", timeframe)
    
    if isnothing(m)
        error("Invalid timeframe format: $timeframe")
    end
    
    value = parse(Int, m.captures[1])
    unit = m.captures[2]
    
    if unit == "m"
        return Minute(value)
    elseif unit == "h"
        return Hour(value)
    elseif unit == "d"
        return Day(value)
    else
        error("Unknown timeframe unit: $unit")
    end
end

# ============================================================================
# Tick数据迭代器
# ============================================================================

"""
    TickIterator

Tick数据迭代器（用于回测）
"""
struct TickIterator
    ticks::DataFrame
    current_index::Ref{Int}
    
    function TickIterator(ticks::DataFrame)
        new(ticks, Ref(1))
    end
end

"""
    Base.iterate(iter::TickIterator, state=1)

迭代器接口
"""
function Base.iterate(iter::TickIterator, state=1)
    if state > nrow(iter.ticks)
        return nothing
    end
    
    row = iter.ticks[state, :]
    
    # 获取symbol（如果存在）
    tick_symbol = if hasproperty(row, :symbol)
        Symbol(row.symbol)
    else
        :UNKNOWN
    end
    
    tick = TickData(
        row.timestamp,
        tick_symbol,
        row.price,
        row.quantity,
        row.is_buyer_maker,
        row.trade_id
    )
    
    return (tick, state + 1)
end

"""
    Base.length(iter::TickIterator)

获取迭代器长度
"""
function Base.length(iter::TickIterator)
    return nrow(iter.ticks)
end

"""
    reset!(iter::TickIterator)

重置迭代器
"""
function reset!(iter::TickIterator)
    iter.current_index[] = 1
end