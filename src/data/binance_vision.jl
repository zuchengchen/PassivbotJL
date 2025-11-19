# src/data/binance_vision.jl

"""
Binance Data Vision 下载器 (修复版)

从 https://data.binance.vision 下载官方历史数据

功能：
- 批量下载历史数据
- 断点续传
- 数据验证
- 自动重试
- 缓存管理
"""

using Dates
using DataFrames
using CSV
using HTTP
using ZipFile
using ProgressMeter
using Statistics

# ============================================================================
# 配置
# ============================================================================

const VISION_BASE_URL = "https://data.binance.vision"

# 数据类型路径
const DATA_PATHS = Dict(
    # 现货
    :spot_daily_aggtrades => "data/spot/daily/aggTrades",
    :spot_monthly_aggtrades => "data/spot/monthly/aggTrades",
    :spot_daily_klines => "data/spot/daily/klines",
    :spot_monthly_klines => "data/spot/monthly/klines",
    :spot_daily_trades => "data/spot/daily/trades",
    
    # USDT永续合约
    :futures_daily_aggtrades => "data/futures/um/daily/aggTrades",
    :futures_monthly_aggtrades => "data/futures/um/monthly/aggTrades",
    :futures_daily_klines => "data/futures/um/daily/klines",
    :futures_monthly_klines => "data/futures/um/monthly/klines",
    
    # COIN永续合约
    :coin_futures_daily_aggtrades => "data/futures/cm/daily/aggTrades",
    :coin_futures_monthly_aggtrades => "data/futures/cm/monthly/aggTrades"
)

# 下载配置
mutable struct DownloadConfig
    cache_dir::String
    max_retries::Int
    retry_delay::Float64  # 秒
    verify_checksum::Bool
    parallel_downloads::Int
    
    function DownloadConfig(;
        cache_dir="data/cache",
        max_retries=3,
        retry_delay=2.0,
        verify_checksum=true,
        parallel_downloads=3
    )
        mkpath(cache_dir)
        new(cache_dir, max_retries, retry_delay, verify_checksum, parallel_downloads)
    end
end

# 全局配置
const DOWNLOAD_CONFIG = DownloadConfig()

# ============================================================================
# 辅助函数
# ============================================================================

"""
    get_cache_path(filename::String)::String

获取缓存文件路径
"""
function get_cache_path(filename::String)::String
    return joinpath(DOWNLOAD_CONFIG.cache_dir, filename)
end

"""
    is_cached(filename::String)::Bool

检查文件是否已缓存
"""
function is_cached(filename::String)::Bool
    cache_path = get_cache_path(filename)
    return isfile(cache_path)
end

"""
    download_with_retry(url::String, max_retries::Int=DOWNLOAD_CONFIG.max_retries)::Vector{UInt8}

带重试的下载
"""
function download_with_retry(url::String, max_retries::Int=DOWNLOAD_CONFIG.max_retries)::Vector{UInt8}
    
    for attempt in 1:max_retries
        try
            @debug "Downloading" url=url attempt=attempt
            
            response = HTTP.get(url, retry=false, readtimeout=300)
            
            if response.status == 200
                return response.body
            else
                @warn "Unexpected status" status=response.status
            end
            
        catch e
            if attempt == max_retries
                @error "Download failed after $max_retries attempts" url=url error=e
                rethrow(e)
            else
                @warn "Download failed, retrying..." attempt=attempt error=e
                sleep(DOWNLOAD_CONFIG.retry_delay * attempt)  # 指数退避
            end
        end
    end
    
    error("Download failed")
end

"""
    verify_zip_integrity(data::Vector{UInt8})::Bool

验证ZIP文件完整性
"""
function verify_zip_integrity(data::Vector{UInt8})::Bool
    try
        zip_reader = ZipFile.Reader(IOBuffer(data))
        close(zip_reader)
        return true
    catch
        return false
    end
end

"""
    extract_csv_from_zip(zip_data::Vector{UInt8})::String

从ZIP中提取CSV数据
"""
function extract_csv_from_zip(zip_data::Vector{UInt8})::String
    zip_reader = ZipFile.Reader(IOBuffer(zip_data))
    
    if isempty(zip_reader.files)
        close(zip_reader)
        error("ZIP file is empty")
    end
    
    csv_file = zip_reader.files[1]
    csv_data = read(csv_file, String)
    
    close(zip_reader)
    
    return csv_data
end

# ============================================================================
# 核心下载函数
# ============================================================================

"""
    download_daily_aggtrades(
        symbol::String,
        date::Date;
        market::Symbol=:futures,
        use_cache::Bool=true
    )::DataFrame

下载单日aggTrades数据

参数：
- symbol: 交易对，如"BTCUSDT"
- date: 日期
- market: :spot 或 :futures
- use_cache: 是否使用缓存

返回：
- DataFrame包含: agg_trade_id, price, quantity, first_trade_id, last_trade_id, 
                 timestamp, is_buyer_maker, symbol
"""
function download_daily_aggtrades(
    symbol::String,
    date::Date;
    market::Symbol=:futures,
    use_cache::Bool=true
)::DataFrame
    
    # 构建文件名
    path_key = market == :spot ? :spot_daily_aggtrades : :futures_daily_aggtrades
    base_path = DATA_PATHS[path_key]
    
    date_str = Dates.format(date, "yyyy-mm-dd")
    filename = "$(symbol)-aggTrades-$(date_str).zip"
    
    # 检查缓存
    if use_cache && is_cached(filename)
        @debug "Loading from cache" filename=filename
        
        cache_path = get_cache_path(filename)
        zip_data = read(cache_path)
    else
        # 构建URL
        url = "$(VISION_BASE_URL)/$(base_path)/$(symbol)/$(filename)"
        
        @debug "Downloading from" url=url
        
        try
            zip_data = download_with_retry(url)
            
            # 验证完整性
            if !verify_zip_integrity(zip_data)
                error("Downloaded ZIP file is corrupted")
            end
            
            # 保存到缓存
            if use_cache
                cache_path = get_cache_path(filename)
                write(cache_path, zip_data)
                @debug "Saved to cache" cache_path=cache_path
            end
            
        catch e
            if isa(e, HTTP.ExceptionRequest.StatusError) && e.status == 404
                @debug "Data not available" symbol=symbol date=date
                return DataFrame()
            else
                rethrow(e)
            end
        end
    end
    
    # 解析数据
    csv_data = extract_csv_from_zip(zip_data)
    
    # CSV有表头，直接读取
    df = CSV.read(IOBuffer(csv_data), DataFrame)
    
    # 标准化列名（Binance使用 transact_time，我们统一为 timestamp）
    if hasproperty(df, :transact_time)
        rename!(df, :transact_time => :timestamp)
    end
    
    # 数据类型转换
    df.timestamp = unix2datetime.(df.timestamp ./ 1000)
    df.price = parse.(Float64, string.(df.price))
    df.quantity = parse.(Float64, string.(df.quantity))
    df.symbol .= symbol
    
    return df
end

"""
    download_monthly_aggtrades(
        symbol::String,
        year::Int,
        month::Int;
        market::Symbol=:futures,
        use_cache::Bool=true
    )::DataFrame

下载月度aggTrades数据

参数：
- symbol: 交易对
- year: 年份
- month: 月份 (1-12)
- market: :spot 或 :futures
- use_cache: 是否使用缓存

返回：
- DataFrame
"""
function download_monthly_aggtrades(
    symbol::String,
    year::Int,
    month::Int;
    market::Symbol=:futures,
    use_cache::Bool=true
)::DataFrame
    
    path_key = market == :spot ? :spot_monthly_aggtrades : :futures_monthly_aggtrades
    base_path = DATA_PATHS[path_key]
    
    month_str = lpad(month, 2, '0')
    filename = "$(symbol)-aggTrades-$(year)-$(month_str).zip"
    
    # 检查缓存
    if use_cache && is_cached(filename)
        @debug "Loading from cache" filename=filename
        
        cache_path = get_cache_path(filename)
        zip_data = read(cache_path)
    else
        # 构建URL
        url = "$(VISION_BASE_URL)/$(base_path)/$(symbol)/$(filename)"
        
        @debug "Downloading from" url=url
        
        zip_data = download_with_retry(url)
        
        if !verify_zip_integrity(zip_data)
            error("Downloaded ZIP file is corrupted")
        end
        
        if use_cache
            cache_path = get_cache_path(filename)
            write(cache_path, zip_data)
        end
    end
    
    # 解析
    csv_data = extract_csv_from_zip(zip_data)
    
    # CSV有表头
    df = CSV.read(IOBuffer(csv_data), DataFrame)
    
    # 标准化列名
    if hasproperty(df, :transact_time)
        rename!(df, :transact_time => :timestamp)
    end
    
    # 数据类型转换
    df.timestamp = unix2datetime.(df.timestamp ./ 1000)
    df.price = parse.(Float64, string.(df.price))
    df.quantity = parse.(Float64, string.(df.quantity))
    df.symbol .= symbol
    
    @info "Loaded monthly data" symbol=symbol year=year month=month rows=nrow(df)
    
    return df
end

"""
    download_klines(
        symbol::String,
        interval::String,
        date::Date;
        market::Symbol=:futures,
        use_cache::Bool=true
    )::DataFrame

下载K线数据

参数：
- symbol: 交易对
- interval: 时间周期，如"1m", "5m", "1h", "1d"
- date: 日期
- market: :spot 或 :futures
- use_cache: 是否使用缓存

返回：
- DataFrame包含: open_time, open, high, low, close, volume, close_time, 
                 quote_volume, count, taker_buy_volume, taker_buy_quote_volume, ignore, symbol
"""
function download_klines(
    symbol::String,
    interval::String,
    date::Date;
    market::Symbol=:futures,
    use_cache::Bool=true
)::DataFrame
    
    path_key = market == :spot ? :spot_daily_klines : :futures_daily_klines
    base_path = DATA_PATHS[path_key]
    
    date_str = Dates.format(date, "yyyy-mm-dd")
    filename = "$(symbol)-$(interval)-$(date_str).zip"
    
    # 检查缓存
    if use_cache && is_cached(filename)
        cache_path = get_cache_path(filename)
        zip_data = read(cache_path)
    else
        # 构建URL
        url = "$(VISION_BASE_URL)/$(base_path)/$(symbol)/$(interval)/$(filename)"
        
        @debug "Downloading from" url=url
        
        try
            zip_data = download_with_retry(url)
            
            if !verify_zip_integrity(zip_data)
                error("Downloaded ZIP file is corrupted")
            end
            
            if use_cache
                cache_path = get_cache_path(filename)
                write(cache_path, zip_data)
            end
            
        catch e
            if isa(e, HTTP.ExceptionRequest.StatusError) && e.status == 404
                @debug "Klines not available" symbol=symbol interval=interval date=date
                return DataFrame()
            else
                rethrow(e)
            end
        end
    end
    
    csv_data = extract_csv_from_zip(zip_data)
    
    # Klines CSV也有表头
    df = CSV.read(IOBuffer(csv_data), DataFrame)
    
    # 转换时间戳
    if hasproperty(df, :open_time)
        df.open_time = unix2datetime.(df.open_time ./ 1000)
    end
    
    if hasproperty(df, :close_time)
        df.close_time = unix2datetime.(df.close_time ./ 1000)
    end
    
    # 转换价格列（如果是字符串）
    for col in [:open, :high, :low, :close, :volume]
        if hasproperty(df, col)
            df[!, col] = parse.(Float64, string.(df[!, col]))
        end
    end
    
    df.symbol .= symbol
    
    return df
end

# ============================================================================
# 批量下载
# ============================================================================

"""
    download_date_range_aggtrades(
        symbol::String,
        start_date::Date,
        end_date::Date;
        market::Symbol=:futures,
        use_cache::Bool=true,
        merge::Bool=true
    )::Union{DataFrame, Vector{DataFrame}}

下载日期范围的数据

参数：
- symbol: 交易对
- start_date: 开始日期
- end_date: 结束日期
- market: :spot 或 :futures
- use_cache: 是否使用缓存
- merge: 是否合并为单个DataFrame（false则返回每日DataFrame数组）

返回：
- DataFrame 或 Vector{DataFrame}
"""
function download_date_range_aggtrades(
    symbol::String,
    start_date::Date,
    end_date::Date;
    market::Symbol=:futures,
    use_cache::Bool=true,
    merge::Bool=true
)::Union{DataFrame, Vector{DataFrame}}
    
    date_range = start_date:Day(1):end_date
    total_days = length(date_range)
    
    @info "Downloading date range" symbol=symbol days=total_days
    
    all_data = DataFrame[]
    failed_dates = Date[]
    
    p = Progress(total_days, desc="Downloading $symbol...")
    
    for date in date_range
        try
            df = download_daily_aggtrades(symbol, date, market=market, use_cache=use_cache)
            
            if nrow(df) > 0
                push!(all_data, df)
            else
                push!(failed_dates, date)
            end
            
        catch e
            @warn "Failed to download" date=date error=e
            push!(failed_dates, date)
        end
        
        next!(p)
        sleep(0.05)  # 避免请求过快
    end
    
    finish!(p)
    
    if !isempty(failed_dates)
        @warn "Failed dates" count=length(failed_dates) dates=failed_dates[1:min(5, length(failed_dates))]
    end
    
    if isempty(all_data)
        @warn "No data downloaded"
        return merge ? DataFrame() : DataFrame[]
    end
    
    @info "Download complete" successful_days=length(all_data) failed_days=length(failed_dates)
    
    if merge
        result = vcat(all_data...)
        sort!(result, :timestamp)
        @info "Merged data" total_rows=nrow(result)
        return result
    else
        return all_data
    end
end

"""
    download_multiple_months(
        symbol::String,
        start_year::Int,
        start_month::Int,
        end_year::Int,
        end_month::Int;
        market::Symbol=:futures,
        use_cache::Bool=true
    )::DataFrame

下载多个月的数据

参数：
- symbol: 交易对
- start_year: 开始年份
- start_month: 开始月份
- end_year: 结束年份
- end_month: 结束月份
- market: :spot 或 :futures
- use_cache: 是否使用缓存

返回：
- DataFrame
"""
function download_multiple_months(
    symbol::String,
    start_year::Int,
    start_month::Int,
    end_year::Int,
    end_month::Int;
    market::Symbol=:futures,
    use_cache::Bool=true
)::DataFrame
    
    months = []
    
    current_year = start_year
    current_month = start_month
    
    while (current_year < end_year) || (current_year == end_year && current_month <= end_month)
        push!(months, (current_year, current_month))
        
        current_month += 1
        if current_month > 12
            current_month = 1
            current_year += 1
        end
    end
    
    @info "Downloading multiple months" symbol=symbol total_months=length(months)
    
    all_data = DataFrame[]
    
    p = Progress(length(months), desc="Downloading months...")
    
    for (year, month) in months
        try
            df = download_monthly_aggtrades(symbol, year, month, market=market, use_cache=use_cache)
            
            if nrow(df) > 0
                push!(all_data, df)
            end
            
        catch e
            @warn "Failed to download month" year=year month=month error=e
        end
        
        next!(p)
        sleep(0.1)
    end
    
    finish!(p)
    
    if isempty(all_data)
        return DataFrame()
    end
    
    result = vcat(all_data...)
    sort!(result, :timestamp)
    
    @info "Download complete" total_rows=nrow(result)
    
    return result
end

"""
    download_multiple_symbols(
        symbols::Vector{String},
        date::Date;
        market::Symbol=:futures,
        use_cache::Bool=true
    )::Dict{String, DataFrame}

下载多个交易对的数据

参数：
- symbols: 交易对列表
- date: 日期
- market: :spot 或 :futures
- use_cache: 是否使用缓存

返回：
- Dict{String, DataFrame}，键为交易对，值为数据
"""
function download_multiple_symbols(
    symbols::Vector{String},
    date::Date;
    market::Symbol=:futures,
    use_cache::Bool=true
)::Dict{String, DataFrame}
    
    @info "Downloading multiple symbols" symbols=symbols date=date
    
    results = Dict{String, DataFrame}()
    
    p = Progress(length(symbols), desc="Downloading symbols...")
    
    for symbol in symbols
        try
            df = download_daily_aggtrades(symbol, date, market=market, use_cache=use_cache)
            
            if nrow(df) > 0
                results[symbol] = df
            end
            
        catch e
            @warn "Failed to download symbol" symbol=symbol error=e
        end
        
        next!(p)
        sleep(0.1)
    end
    
    finish!(p)
    
    @info "Download complete" successful_symbols=length(results)
    
    return results
end

# ============================================================================
# 数据管理
# ============================================================================

"""
    list_cached_files()::Vector{String}

列出所有缓存文件
"""
function list_cached_files()::Vector{String}
    if !isdir(DOWNLOAD_CONFIG.cache_dir)
        return String[]
    end
    
    return readdir(DOWNLOAD_CONFIG.cache_dir)
end

"""
    get_cache_size()::Float64

获取缓存大小（MB）
"""
function get_cache_size()::Float64
    if !isdir(DOWNLOAD_CONFIG.cache_dir)
        return 0.0
    end
    
    total_size = 0
    for file in readdir(DOWNLOAD_CONFIG.cache_dir, join=true)
        if isfile(file)
            total_size += stat(file).size
        end
    end
    
    return total_size / 1024 / 1024
end

"""
    clear_cache(;older_than_days::Union{Int, Nothing}=nothing)

清理缓存

参数：
- older_than_days: 只清理N天前的文件，nothing表示清理全部
"""
function clear_cache(;older_than_days::Union{Int, Nothing}=nothing)
    
    if !isdir(DOWNLOAD_CONFIG.cache_dir)
        @info "Cache directory does not exist"
        return
    end
    
    files = readdir(DOWNLOAD_CONFIG.cache_dir, join=true)
    
    deleted_count = 0
    freed_space = 0
    
    cutoff_time = if !isnothing(older_than_days)
        now() - Day(older_than_days)
    else
        nothing
    end
    
    for file in files
        if isfile(file)
            should_delete = if isnothing(cutoff_time)
                true
            else
                file_time = unix2datetime(stat(file).mtime)
                file_time < cutoff_time
            end
            
            if should_delete
                file_size = stat(file).size
                rm(file)
                deleted_count += 1
                freed_space += file_size
            end
        end
    end
    
    freed_mb = freed_space / 1024 / 1024
    
    @info "Cache cleared" deleted_files=deleted_count freed_space_mb=round(freed_mb, digits=2)
end

"""
    print_cache_info()

打印缓存信息
"""
function print_cache_info()
    
    println("\n" * "="^70)
    println("缓存信息")
    println("="^70)
    
    cache_size = get_cache_size()
    files = list_cached_files()
    
    println("缓存目录: $(DOWNLOAD_CONFIG.cache_dir)")
    println("文件数量: $(length(files))")
    println("总大小: $(round(cache_size, digits=2)) MB")
    
    if !isempty(files)
        println("\n最近的文件:")
        
        # 按修改时间排序
        file_paths = [joinpath(DOWNLOAD_CONFIG.cache_dir, f) for f in files]
        sorted_files = sort(file_paths, by=f -> stat(f).mtime, rev=true)
        
        for (i, file) in enumerate(sorted_files[1:min(10, length(sorted_files))])
            size_mb = stat(file).size / 1024 / 1024
            mtime = unix2datetime(stat(file).mtime)
            println("  $(i). $(basename(file)) ($(round(size_mb, digits=2)) MB, $mtime)")
        end
    end
    
    println("="^70)
end

# ============================================================================
# 数据验证
# ============================================================================

"""
    validate_aggtrades_data(df::DataFrame)::NamedTuple

验证aggTrades数据质量

返回：
- (is_valid=Bool, warnings=Vector{String}, errors=Vector{String})
"""
function validate_aggtrades_data(df::DataFrame)::NamedTuple
    
    warnings = String[]
    errors = String[]
    
    # 1. 检查必需列
    required_cols = [:timestamp, :price, :quantity, :is_buyer_maker]
    for col in required_cols
        if !hasproperty(df, col)
            push!(errors, "Missing required column: $col")
        end
    end
    
    if !isempty(errors)
        return (is_valid=false, warnings=warnings, errors=errors)
    end
    
    # 2. 检查数据量
    if nrow(df) == 0
        push!(warnings, "DataFrame is empty")
    end
    
    # 3. 检查时间顺序
    if nrow(df) > 1 && !issorted(df.timestamp)
        push!(warnings, "Timestamps are not sorted")
    end
    
    # 4. 检查缺失值
    for col in [:price, :quantity]
        if any(ismissing, df[!, col])
            push!(errors, "Missing values in column: $col")
        end
    end
    
    # 5. 检查价格异常
    if nrow(df) > 0
        if any(df.price .<= 0)
            push!(errors, "Invalid prices (<=0) found")
        end
        
        if any(df.quantity .<= 0)
            push!(errors, "Invalid quantities (<=0) found")
        end
    end
    
    # 6. 检查时间间隔异常
    if nrow(df) > 1
        time_diffs = diff(Dates.value.(df.timestamp))
        max_gap = maximum(time_diffs)
        
        if max_gap > 60000  # 超过1分钟
            push!(warnings, "Large time gap detected: $(max_gap/1000) seconds")
        end
    end
    
    is_valid = isempty(errors)
    
    return (is_valid=is_valid, warnings=warnings, errors=errors)
end

"""
    print_data_summary(df::DataFrame)

打印数据摘要
"""
function print_data_summary(df::DataFrame)
    
    println("\n" * "="^70)
    println("数据摘要")
    println("="^70)
    
    if nrow(df) == 0
        println("⚠️  数据为空")
        return
    end
    
    println("\n基本信息:")
    println("  行数: $(nrow(df))")
    println("  列数: $(ncol(df))")
    
    if hasproperty(df, :symbol)
        symbols = unique(df.symbol)
        println("  交易对: $(join(symbols, ", "))")
    end
    
    if hasproperty(df, :timestamp)
        println("\n时间范围:")
        println("  开始: $(df[1, :timestamp])")
        println("  结束: $(df[end, :timestamp])")
        
        duration_hours = Dates.value(df[end, :timestamp] - df[1, :timestamp]) / (1000 * 3600)
        println("  时长: $(round(duration_hours, digits=2)) 小时")
    end
    
    if hasproperty(df, :price)
        println("\n价格统计:")
        println("  最高: $(round(maximum(df.price), digits=2))")
        println("  最低: $(round(minimum(df.price), digits=2))")
        println("  均价: $(round(mean(df.price), digits=2))")
        println("  中位: $(round(median(df.price), digits=2))")
    end
    
    if hasproperty(df, :quantity)
        println("\n成交量:")
        println("  总量: $(round(sum(df.quantity), digits=4))")
        println("  均量: $(round(mean(df.quantity), digits=6))")
    end
    
    if hasproperty(df, :is_buyer_maker)
        buy_count = count(.!df.is_buyer_maker)
        sell_count = count(df.is_buyer_maker)
        println("\n买卖分布:")
        println("  主动买入: $buy_count ($(round(buy_count/nrow(df)*100, digits=1))%)")
        println("  主动卖出: $sell_count ($(round(sell_count/nrow(df)*100, digits=1))%)")
    end
    
    println("="^70)
end

# ============================================================================
# 导出函数
# ============================================================================

"""
    save_aggtrades(df::DataFrame, filepath::String)

保存aggTrades数据到CSV
"""
function save_aggtrades(df::DataFrame, filepath::String)
    CSV.write(filepath, df)
    @info "Data saved to $filepath"
end