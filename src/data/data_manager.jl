# src/data/data_manager.jl

"""
智能数据管理器

优先级策略：
1. 本地 Parquet 文件（最快，最优先）✅
2. 本地 CSV 文件（兼容旧数据）
3. Binance Vision 历史数据（快速、完整）
4. Binance API 实时数据（最新、最慢）
"""

using Dates
using DataFrames
using CSV

include("binance_vision.jl")
include("binance_api.jl")
include("local_storage.jl")

# ============================================================================
# 配置
# ============================================================================

# Vision 数据可用性：通常是3天前的数据
const VISION_DELAY_DAYS = 3

# 回测数据缓存目录
const BACKTEST_CACHE_DIR = "data/backtest_cache"

# ============================================================================
# 时间范围分割
# ============================================================================

"""
    split_date_range(start_time::DateTime, end_time::DateTime)

将时间范围分割为 Vision 和 API 两部分
"""
function split_date_range(start_time::DateTime, end_time::DateTime)
    
    # Vision 数据截止日期（今天 - VISION_DELAY_DAYS）
    vision_cutoff = today() - Day(VISION_DELAY_DAYS)
    
    # 转换为日期
    start_date = Date(start_time)
    end_date = Date(end_time)
    
    vision_range = nothing
    api_range = nothing
    
    # 完全在 Vision 范围内
    if end_date <= vision_cutoff
        vision_range = (start_date, end_date)
    
    # 完全在 API 范围内
    elseif start_date > vision_cutoff
        api_range = (start_time, end_time)
    
    # 跨越两个范围
    else
        vision_range = (start_date, vision_cutoff)
        
        # 正确构造 DateTime
        api_start_date = vision_cutoff + Day(1)
        api_range = (DateTime(api_start_date), end_time)
    end
    
    return (vision_range, api_range)
end

# ============================================================================
# 本地数据检查（增强版）
# ============================================================================

"""
    check_local_data_with_format(symbol::String, date::Date, market::Symbol)::Tuple{Bool, Union{StorageFormat, Nothing}}

检查本地数据并返回格式

返回：
- (has_data::Bool, format::Union{StorageFormat, Nothing})
"""
function check_local_data_with_format(
    symbol::String, 
    date::Date, 
    market::Symbol
)::Tuple{Bool, Union{StorageFormat, Nothing}}
    
    # ✅ 优先检查 Parquet
    parquet_path = get_local_data_path(symbol, date, market, PARQUET_FORMAT)
    if isfile(parquet_path) && stat(parquet_path).size > 0
        return (true, PARQUET_FORMAT)
    end
    
    # 其次检查 CSV
    csv_path = get_local_data_path(symbol, date, market, CSV_FORMAT)
    if isfile(csv_path) && stat(csv_path).size > 0
        return (true, CSV_FORMAT)
    end
    
    return (false, nothing)
end

"""
    get_local_coverage_detailed(symbol::String, start_date::Date, end_date::Date, market::Symbol)

获取本地数据详细覆盖情况

返回：
- (parquet_dates, csv_dates, missing_dates)
"""
function get_local_coverage_detailed(
    symbol::String,
    start_date::Date,
    end_date::Date,
    market::Symbol
)
    
    parquet_dates = Date[]
    csv_dates = Date[]
    missing_dates = Date[]
    
    current_date = start_date
    while current_date <= end_date
        has_data, format = check_local_data_with_format(symbol, current_date, market)
        
        if has_data
            if format == PARQUET_FORMAT
                push!(parquet_dates, current_date)
            else
                push!(csv_dates, current_date)
            end
        else
            push!(missing_dates, current_date)
        end
        
        current_date += Day(1)
    end
    
    return (parquet_dates=parquet_dates, csv_dates=csv_dates, missing_dates=missing_dates)
end

# ============================================================================
# 智能数据获取（优化版）
# ============================================================================

"""
    fetch_data(
        symbol::String,
        start_time::DateTime,
        end_time::DateTime;
        market::Symbol=:futures,
        use_cache::Bool=true,
        verbose::Bool=true
    )::DataFrame

智能获取数据（优先级：本地 Parquet > 本地 CSV > Vision > API）
"""
function fetch_data(
    symbol::String,
    start_time::DateTime,
    end_time::DateTime;
    market::Symbol=:futures,
    use_cache::Bool=true,
    verbose::Bool=true
)::DataFrame
    
    if verbose
        println("\n" * "="^70)
        println("智能数据获取")
        println("="^70)
        println("\n配置:")
        println("  交易对: $symbol")
        println("  时间范围: $start_time 到 $end_time")
        println("  市场: $market")
        println("  使用缓存: $use_cache")
    end
    
    # 分割时间范围
    vision_range, api_range = split_date_range(start_time, end_time)
    
    all_data = DataFrame[]
    
    # ========================================================================
    # 优先从本地加载（Parquet > CSV）
    # ========================================================================
    
    if !isnothing(vision_range)
        vision_start, vision_end = vision_range
        
        if verbose
            println("\n📦 历史数据范围 ($(vision_start) 到 $(vision_end)):")
        end
        
        # ✅ 详细检查本地数据（按格式分类）
        coverage = get_local_coverage_detailed(symbol, vision_start, vision_end, market)
        
        total_days = Dates.value(vision_end - vision_start) + 1
        available_days = length(coverage.parquet_dates) + length(coverage.csv_dates)
        coverage_pct = available_days / total_days * 100
        
        if verbose
            if !isempty(coverage.parquet_dates)
                println("  ✅ Parquet 文件: $(length(coverage.parquet_dates)) 天")
            end
            
            if !isempty(coverage.csv_dates)
                println("  📄 CSV 文件: $(length(coverage.csv_dates)) 天 (建议转换为 Parquet)")
            end
            
            if !isempty(coverage.missing_dates)
                println("  📥 缺失数据: $(length(coverage.missing_dates)) 天")
            end
            
            println("  📊 本地覆盖率: $(round(coverage_pct, digits=1))%")
        end
        
        # ✅ 从本地加载已有数据（自动优先 Parquet）
        local_data = DataFrame()
        if available_days > 0 && use_cache
            if verbose
                println("  📂 加载本地数据...")
            end
            
            local_data = load_local_data_range(symbol, vision_start, vision_end, market)
            
            if verbose && nrow(local_data) > 0
                println("  ✅ 已加载: $(nrow(local_data)) 笔交易")
            end
        end
        
        # ✅ 下载缺失的数据（仅缺失的日期）
        if !isempty(coverage.missing_dates) && use_cache
            if verbose
                println("  📥 从 Binance Vision 下载 $(length(coverage.missing_dates)) 天缺失数据...")
            end
            
            download_success = 0
            download_failed = 0
            
            for date in coverage.missing_dates
                try
                    # 下载单天数据
                    day_data = download_date_range_aggtrades(
                        symbol,
                        date,
                        date,
                        market=market,
                        use_cache=false,  # Vision 自己有缓存
                        merge=true
                    )
                    
                    # ✅ 保存为 Parquet 格式
                    if nrow(day_data) > 0
                        save_local_data(day_data, symbol, date, market, PARQUET_FORMAT)
                        download_success += 1
                        
                        if verbose
                            println("    ✅ $date: $(nrow(day_data)) 笔交易")
                        end
                    else
                        download_failed += 1
                        if verbose
                            println("    ⚠️  $date: 无数据")
                        end
                    end
                    
                catch e
                    download_failed += 1
                    if verbose
                        println("    ❌ $date: 下载失败")
                    end
                end
            end
            
            if verbose && download_success > 0
                println("  ✅ Vision 下载完成: 成功 $download_success 天, 失败 $download_failed 天")
            end
            
            # 重新加载所有数据（包括新下载的）
            if download_success > 0
                local_data = load_local_data_range(symbol, vision_start, vision_end, market)
            end
        end
        
        # 过滤到精确时间
        if nrow(local_data) > 0
            mask = (local_data.timestamp .>= start_time) .& (local_data.timestamp .<= end_time)
            vision_data = local_data[mask, :]
            
            if nrow(vision_data) > 0
                push!(all_data, vision_data)
                
                if verbose
                    println("  ✅ 历史数据已准备: $(nrow(vision_data)) 笔交易")
                end
            end
        end
    end
    
    # ========================================================================
    # 从 API 下载（仅在必要时）
    # ========================================================================
    
    if !isnothing(api_range)
        api_start, api_end = api_range
        
        if verbose
            println("\n🌐 最新数据 (Binance API):")
            println("  时间范围: $api_start 到 $api_end")
        end
        
        try
            api_data = fetch_aggtrades_from_api(
                symbol,
                api_start,
                api_end,
                market=market
            )
            
            if nrow(api_data) > 0
                push!(all_data, api_data)
                
                if verbose
                    println("  ✅ API 数据: $(nrow(api_data)) 笔交易")
                end
                
                # ✅ 保存 API 数据到本地（Parquet 格式）
                if use_cache && nrow(api_data) > 0
                    api_dates = unique(Date.(api_data.timestamp))
                    
                    if verbose
                        println("  💾 保存到本地 (Parquet 格式)...")
                    end
                    
                    for date in api_dates
                        date_mask = Date.(api_data.timestamp) .== date
                        day_data = api_data[date_mask, :]
                        
                        if nrow(day_data) > 0
                            save_local_data(day_data, symbol, date, market, PARQUET_FORMAT)
                        end
                    end
                    
                    if verbose
                        println("  ✅ 已保存 $(length(api_dates)) 天数据")
                    end
                end
            else
                if verbose
                    println("  ⚠️  API 数据不可用")
                end
            end
            
        catch e
            if verbose
                println("  ❌ API 下载失败: $e")
            end
        end
    end
    
    # ========================================================================
    # 合并数据
    # ========================================================================
    
    if isempty(all_data)
        @warn "No data fetched for $symbol from $start_time to $end_time"
        return DataFrame(
            agg_trade_id = Int64[],
            price = Float64[],
            quantity = Float64[],
            first_trade_id = Int64[],
            last_trade_id = Int64[],
            timestamp = DateTime[],
            is_buyer_maker = Bool[],
            symbol = String[]
        )
    end
    
    result = vcat(all_data...)
    sort!(result, :timestamp)
    unique!(result, :agg_trade_id)
    
    if verbose
        println("\n📊 数据汇总:")
        println("  总数据量: $(nrow(result)) 笔交易")
        println("  时间范围: $(result[1, :timestamp]) 到 $(result[end, :timestamp])")
        println("  数据完整性: $(check_data_completeness(result, start_time, end_time))")
        println("="^70)
    end
    
    return result
end

# ============================================================================
# 数据完整性检查
# ============================================================================

"""
    check_data_completeness(df::DataFrame, start_time::DateTime, end_time::DateTime)::String

检查数据完整性
"""
function check_data_completeness(df::DataFrame, start_time::DateTime, end_time::DateTime)::String
    
    if nrow(df) == 0
        return "❌ 无数据"
    end
    
    actual_start = df[1, :timestamp]
    actual_end = df[end, :timestamp]
    
    # 检查开始和结束时间
    start_gap = Dates.value(actual_start - start_time) / 1000  # 秒
    end_gap = Dates.value(end_time - actual_end) / 1000
    
    if start_gap > 60 || end_gap > 60  # 超过1分钟
        missing_pct = ((start_gap + end_gap) / Dates.value(end_time - start_time) * 1000) * 100
        return "⚠️ 不完整 (缺失 $(round(missing_pct, digits=1))%)"
    end
    
    return "✅ 完整"
end

# ============================================================================
# 回测数据准备
# ============================================================================

"""
    fetch_data_for_backtest(
        symbol::String,
        start_time::DateTime,
        end_time::DateTime;
        market::Symbol=:futures,
        force_refresh::Bool=false
    )::DataFrame

为回测准备数据（带缓存）
"""
function fetch_data_for_backtest(
    symbol::String,
    start_time::DateTime,
    end_time::DateTime;
    market::Symbol=:futures,
    force_refresh::Bool=false
)::DataFrame
    
    # 生成缓存文件名
    mkpath(BACKTEST_CACHE_DIR)
    
    start_str = Dates.format(start_time, "yyyymmdd_HHMMSS")
    end_str = Dates.format(end_time, "yyyymmdd_HHMMSS")
    cache_file = joinpath(
        BACKTEST_CACHE_DIR,
        "$(symbol)_$(market)_$(start_str)_$(end_str).csv"
    )
    
    # 检查缓存
    if !force_refresh && isfile(cache_file)
        @info "Loading from cache" file=cache_file
        
        df = CSV.read(cache_file, DataFrame)
        
        # 转换时间列
        if hasproperty(df, :timestamp) && eltype(df.timestamp) == String
            df.timestamp = DateTime.(df.timestamp)
        end
        
        @info "Loaded from cache" rows=nrow(df)
        return df
    end
    
    # 下载数据
    @info "Fetching data for backtest" symbol=symbol start_time=start_time end_time=end_time
    
    df = fetch_data(
        symbol,
        start_time,
        end_time,
        market=market,
        use_cache=true,
        verbose=false
    )
    
    # 保存到缓存
    if nrow(df) > 0
        CSV.write(cache_file, df)
        @info "Saved to cache" file=cache_file rows=nrow(df)
    end
    
    return df
end

# ============================================================================
# 多交易对数据准备
# ============================================================================

"""
    prepare_multiple_symbols(
        symbols::Vector{String},
        start_time::DateTime,
        end_time::DateTime;
        market::Symbol=:futures
    )::Dict{String, DataFrame}

准备多个交易对的数据
"""
function prepare_multiple_symbols(
    symbols::Vector{String},
    start_time::DateTime,
    end_time::DateTime;
    market::Symbol=:futures
)::Dict{String, DataFrame}
    
    @info "Preparing multiple symbols" symbols=symbols count=length(symbols)
    
    result = Dict{String, DataFrame}()
    
    for symbol in symbols
        @info "Fetching $symbol..."
        
        try
            df = fetch_data_for_backtest(
                symbol,
                start_time,
                end_time,
                market=market
            )
            
            result[symbol] = df
            
            @info "Fetched $symbol" rows=nrow(df)
            
        catch e
            @error "Failed to fetch $symbol" error=e
            result[symbol] = DataFrame()
        end
    end
    
    return result
end

# ============================================================================
# 缓存管理
# ============================================================================

"""
    clear_backtest_cache(;older_than_days::Int=7)

清理回测缓存
"""
function clear_backtest_cache(;older_than_days::Int=7)
    
    if !isdir(BACKTEST_CACHE_DIR)
        @info "Cache directory does not exist"
        return
    end
    
    cutoff_time = now() - Day(older_than_days)
    deleted_count = 0
    freed_space = 0
    
    for file in readdir(BACKTEST_CACHE_DIR, join=true)
        if isfile(file)
            file_time = unix2datetime(stat(file).mtime)
            
            if file_time < cutoff_time
                file_size = stat(file).size
                rm(file)
                deleted_count += 1
                freed_space += file_size
                
                @debug "Deleted cache file" file=basename(file)
            end
        end
    end
    
    @info "Cache cleared" deleted_files=deleted_count freed_mb=round(freed_space/1024/1024, digits=2)
end

"""
    get_cache_info()

获取缓存信息
"""
function get_cache_info()
    
    if !isdir(BACKTEST_CACHE_DIR)
        println("回测缓存目录不存在")
        return
    end
    
    files = readdir(BACKTEST_CACHE_DIR, join=true)
    
    if isempty(files)
        println("回测缓存为空")
        return
    end
    
    println("\n回测缓存信息:")
    println("  目录: $BACKTEST_CACHE_DIR")
    println("  文件数: $(length(files))")
    
    total_size = sum(stat(f).size for f in files)
    println("  总大小: $(round(total_size/1024/1024, digits=2)) MB")
    
    println("\n最近的文件:")
    sorted_files = sort(files, by=f->stat(f).mtime, rev=true)
    
    for (i, file) in enumerate(first(sorted_files, 5))
        size_mb = round(stat(file).size / 1024 / 1024, digits=2)
        mtime = unix2datetime(stat(file).mtime)
        println("  $i. $(basename(file)) ($size_mb MB, $mtime)")
    end
end