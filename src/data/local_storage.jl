# src/data/local_storage.jl

"""
本地数据存储管理器

功能：
- 按日期存储 aggTrades 数据
- 自动检查本地是否已有数据
- 支持增量下载
- 支持 CSV 和 Parquet 格式
- 数据完整性验证
- DateTime 自动转换（Parquet 兼容性）
- 类型优化（移除 Union{Missing, T}）
- 字符串类型标准化（InlineString → String）
"""

using Dates
using DataFrames
using CSV
using Logging
using JSON3
using Parquet

# ============================================================================
# 配置
# ============================================================================

const LOCAL_DATA_DIR = "data/aggtrades"

# 数据存储格式
@enum StorageFormat begin
    CSV_FORMAT       # CSV 格式（易读、通用）
    PARQUET_FORMAT   # Parquet 格式（更小、更快）
end

# 默认使用 Parquet（更高效）
const DEFAULT_FORMAT = PARQUET_FORMAT

# 元数据文件（记录每个文件的信息）
const METADATA_FILE = "metadata.json"

# ============================================================================
# 类型标准化
# ============================================================================

"""
    normalize_dataframe_types(df::DataFrame)::DataFrame

标准化 DataFrame 的数据类型

处理：
- String/Int64 timestamp → DateTime
- InlineString (String7等) → String
- 清理 Union{Missing, T}
"""
function normalize_dataframe_types(df::DataFrame)::DataFrame
    df_copy = copy(df)
    
    # 处理 timestamp 列
    if hasproperty(df_copy, :timestamp)
        ts = df_copy.timestamp
        ts_type = eltype(ts)
        
        # 已经是 DateTime，跳过
        if ts_type == DateTime
            # 不需要处理
        # 字符串类型
        elseif ts_type <: AbstractString
            df_copy.timestamp = DateTime.(ts)
        # 整数类型（Unix 时间戳，毫秒）
        elseif ts_type <: Integer
            df_copy.timestamp = unix2datetime.(ts ./ 1000)
        # Union 类型
        elseif ts_type isa Union
            base_type = Base.nonmissingtype(ts_type)
            if base_type <: AbstractString
                df_copy.timestamp = map(x -> ismissing(x) ? DateTime(0) : DateTime(x), ts)
            elseif base_type <: Integer
                df_copy.timestamp = map(x -> ismissing(x) ? DateTime(0) : unix2datetime(x / 1000), ts)
            end
        end
    end
    
    # 处理字符串列（转换 InlineString 为 String）
    for col in names(df_copy)
        col_data = df_copy[:, col]
        col_type = eltype(col_data)
        
        if col_type <: AbstractString && col_type != String
            df_copy[:, col] = String.(col_data)
        elseif col_type isa Union
            base_type = Base.nonmissingtype(col_type)
            if base_type <: AbstractString && base_type != String
                df_copy[:, col] = map(x -> ismissing(x) ? missing : String(x), col_data)
            end
        end
    end
    
    return df_copy
end

# ============================================================================
# DateTime 转换辅助函数（Parquet 兼容性）
# ============================================================================

"""
    prepare_for_parquet(df::DataFrame)::DataFrame

准备 DataFrame 用于 Parquet 保存
"""
function prepare_for_parquet(df::DataFrame)::DataFrame
    # 构建新列的字典
    cols = Dict{Symbol, Any}()
    
    for col_name in names(df)
        col_sym = Symbol(col_name)
        col_data = df[:, col_name]
        col_type = eltype(col_data)
        
        # DateTime → Int64
        if col_type == DateTime
            cols[col_sym] = round.(Int64, datetime2unix.(col_data) .* 1000)
        # InlineString → String
        elseif col_type <: AbstractString && col_type != String
            cols[col_sym] = String.(col_data)
        # Union{Missing, DateTime}
        elseif col_type isa Union && Base.nonmissingtype(col_type) == DateTime
            cols[col_sym] = map(x -> ismissing(x) ? missing : round(Int64, datetime2unix(x) * 1000), col_data)
        # Union{Missing, InlineString}
        elseif col_type isa Union && Base.nonmissingtype(col_type) <: AbstractString && Base.nonmissingtype(col_type) != String
            cols[col_sym] = map(x -> ismissing(x) ? missing : String(x), col_data)
        # 其他类型保持不变
        else
            cols[col_sym] = col_data
        end
    end
    
    return DataFrame(cols)
end

"""
    restore_from_parquet(df::DataFrame)::DataFrame

从 Parquet 恢复 DataFrame（转换 Int64 回 DateTime，清理类型）
"""
function restore_from_parquet(df::DataFrame)::DataFrame
    df_copy = copy(df)
    
    # 1. 转换时间戳回 DateTime
    if hasproperty(df_copy, :timestamp)
        timestamps = df_copy.timestamp
        
        # 创建 DateTime 向量
        datetime_vec = Vector{DateTime}(undef, length(timestamps))
        
        for i in eachindex(timestamps)
            val = timestamps[i]
            if ismissing(val)
                datetime_vec[i] = DateTime(0)
            elseif val isa Integer
                datetime_vec[i] = unix2datetime(val / 1000)
            elseif val isa DateTime
                datetime_vec[i] = val
            else
                datetime_vec[i] = DateTime(0)
            end
        end
        
        df_copy.timestamp = datetime_vec
    end
    
    # 2. 清理其他列的 Union{Missing, T} 类型
    for col in names(df_copy)
        if col in ("timestamp", :timestamp)
            continue
        end
        
        col_data = df_copy[:, col]
        col_type = eltype(col_data)
        
        # 如果是 Union{Missing, T} 但没有实际 missing 值
        if col_type isa Union && Missing <: col_type
            if !any(ismissing, col_data)
                non_missing_type = Base.nonmissingtype(col_type)
                df_copy[:, col] = Vector{non_missing_type}(col_data)
            end
        end
    end
    
    return df_copy
end

# ============================================================================
# 路径管理
# ============================================================================

"""
    get_local_data_path(symbol::String, date::Date, market::Symbol, format::StorageFormat)::String

获取本地数据文件路径
"""
function get_local_data_path(
    symbol::String,
    date::Date,
    market::Symbol,
    format::StorageFormat=DEFAULT_FORMAT
)::String
    
    # 构建目录结构
    market_dir = joinpath(LOCAL_DATA_DIR, string(market))
    symbol_dir = joinpath(market_dir, symbol)
    
    # 确保目录存在
    mkpath(symbol_dir)
    
    # 文件名
    date_str = Dates.format(date, "yyyy-mm-dd")
    extension = format == CSV_FORMAT ? "csv" : "parquet"
    
    return joinpath(symbol_dir, "$date_str.$extension")
end

"""
    get_local_data_dir(symbol::String, market::Symbol)::String

获取交易对的本地数据目录
"""
function get_local_data_dir(symbol::String, market::Symbol)::String
    market_dir = joinpath(LOCAL_DATA_DIR, string(market))
    symbol_dir = joinpath(market_dir, symbol)
    return symbol_dir
end

"""
    get_metadata_path(symbol::String, market::Symbol)::String

获取元数据文件路径
"""
function get_metadata_path(symbol::String, market::Symbol)::String
    symbol_dir = get_local_data_dir(symbol, market)
    mkpath(symbol_dir)
    return joinpath(symbol_dir, METADATA_FILE)
end

# ============================================================================
# 元数据管理
# ============================================================================

"""
    save_metadata(symbol::String, date::Date, market::Symbol, row_count::Int, file_size::Int)

保存文件元数据
"""
function save_metadata(
    symbol::String,
    date::Date,
    market::Symbol,
    row_count::Int,
    file_size::Int
)
    
    metadata_path = get_metadata_path(symbol, market)
    
    # 读取现有元数据（转换为可变的 Dict）
    metadata = if isfile(metadata_path)
        try
            # ✅ 修复：递归转换所有键为 String
            json_data = JSON3.read(read(metadata_path, String))
            convert_keys_to_string(json_data)
        catch e
            @warn "Failed to read existing metadata, creating new" error=e
            Dict{String, Any}()
        end
    else
        Dict{String, Any}()
    end
    
    # 更新元数据
    date_str = Dates.format(date, "yyyy-mm-dd")
    metadata[date_str] = Dict{String, Any}(
        "rows" => row_count,
        "size" => file_size,
        "updated" => string(now())
    )
    
    # 保存
    try
        write(metadata_path, JSON3.write(metadata))
    catch e
        @warn "Failed to save metadata" error=e
    end
end

"""
    convert_keys_to_string(obj)

递归转换所有键为 String
"""
function convert_keys_to_string(obj)
    if obj isa AbstractDict
        result = Dict{String, Any}()
        for (k, v) in obj
            key_str = k isa Symbol ? String(k) : string(k)
            result[key_str] = convert_keys_to_string(v)
        end
        return result
    elseif obj isa AbstractArray
        return [convert_keys_to_string(x) for x in obj]
    else
        return obj
    end
end

"""
    load_metadata(symbol::String, market::Symbol)::Dict

加载元数据
"""
function load_metadata(symbol::String, market::Symbol)::Dict
    
    metadata_path = get_metadata_path(symbol, market)
    
    if !isfile(metadata_path)
        return Dict{String, Any}()
    end
    
    try
        # ✅ 修复：转换为可变 Dict
        json_data = JSON3.read(read(metadata_path, String))
        return Dict{String, Any}(json_data)
    catch e
        @warn "Failed to load metadata" error=e
        return Dict{String, Any}()
    end
end

# ============================================================================
# 数据检查
# ============================================================================

"""
    has_local_data(symbol::String, date::Date, market::Symbol)::Bool

检查本地是否有指定日期的数据（自动检测格式）
"""
function has_local_data(
    symbol::String,
    date::Date,
    market::Symbol
)::Bool
    
    # 检查两种格式
    for format in [PARQUET_FORMAT, CSV_FORMAT]
        path = get_local_data_path(symbol, date, market, format)
        
        if !isfile(path)
            continue
        end
        
        # 检查文件是否完整（大小 > 0）
        file_size = stat(path).size
        if file_size == 0
            @warn "Local data file is empty" path=path
            continue
        end
        
        return true
    end
    
    return false
end

"""
    get_missing_dates(symbol::String, start_date::Date, end_date::Date, market::Symbol)::Vector{Date}

获取缺失的日期列表
"""
function get_missing_dates(
    symbol::String,
    start_date::Date,
    end_date::Date,
    market::Symbol
)::Vector{Date}
    
    missing_dates = Date[]
    
    current_date = start_date
    while current_date <= end_date
        if !has_local_data(symbol, current_date, market)
            push!(missing_dates, current_date)
        end
        current_date += Day(1)
    end
    
    return missing_dates
end

"""
    get_available_dates(symbol::String, market::Symbol)::Vector{Date}

获取本地已有的所有日期
"""
function get_available_dates(symbol::String, market::Symbol)::Vector{Date}
    
    symbol_dir = get_local_data_dir(symbol, market)
    
    if !isdir(symbol_dir)
        return Date[]
    end
    
    dates = Date[]
    
    for file in readdir(symbol_dir)
        # 匹配 yyyy-mm-dd.csv 或 yyyy-mm-dd.parquet
        m = match(r"(\d{4}-\d{2}-\d{2})\.(csv|parquet)$", file)
        if !isnothing(m)
            try
                date = Date(m.captures[1], "yyyy-mm-dd")
                push!(dates, date)
            catch
                @warn "Invalid date in filename" file=file
            end
        end
    end
    
    return sort(unique(dates))
end

"""
    get_date_coverage(symbol::String, start_date::Date, end_date::Date, market::Symbol)::Float64

获取日期范围的覆盖率（0.0-1.0）
"""
function get_date_coverage(
    symbol::String,
    start_date::Date,
    end_date::Date,
    market::Symbol
)::Float64
    
    total_days = Dates.value(end_date - start_date) + 1
    
    if total_days <= 0
        return 0.0
    end
    
    available_count = 0
    current_date = start_date
    
    while current_date <= end_date
        if has_local_data(symbol, current_date, market)
            available_count += 1
        end
        current_date += Day(1)
    end
    
    return available_count / total_days
end

# ============================================================================
# 数据读写
# ============================================================================

"""
    save_local_data(df::DataFrame, symbol::String, date::Date, market::Symbol, format::StorageFormat)

保存数据到本地
"""
function save_local_data(
    df::DataFrame,
    symbol::String,
    date::Date,
    market::Symbol,
    format::StorageFormat=DEFAULT_FORMAT
)
    
    if nrow(df) == 0
        @warn "Empty DataFrame, not saving" symbol=symbol date=date
        return
    end
    
    path = get_local_data_path(symbol, date, market, format)
    
    try
        if format == CSV_FORMAT
            CSV.write(path, df)
        else
            # Parquet 格式：需要转换 DateTime 和清理类型
            df_parquet = prepare_for_parquet(df)
            write_parquet(path, df_parquet)
        end
        
        file_size = stat(path).size
        file_size_mb = file_size / (1024 * 1024)
        
        # 保存元数据
        save_metadata(symbol, date, market, nrow(df), file_size)
        
        @info "Saved local data" symbol=symbol date=date rows=nrow(df) size_mb=round(file_size_mb, digits=2) format=format
        
    catch e
        @error "Failed to save local data" symbol=symbol date=date error=e
        
        # 如果是 Parquet 失败，尝试降级到 CSV
        if format == PARQUET_FORMAT
            @warn "Parquet save failed, falling back to CSV" symbol=symbol date=date
            try
                csv_path = get_local_data_path(symbol, date, market, CSV_FORMAT)
                CSV.write(csv_path, df)
                
                file_size = stat(csv_path).size
                save_metadata(symbol, date, market, nrow(df), file_size)
                
                @info "Saved as CSV instead" path=csv_path
            catch e2
                @error "CSV fallback also failed" error=e2
            end
        end
    end
end

"""
    load_local_data(symbol::String, date::Date, market::Symbol)::DataFrame

从本地加载数据（自动检测格式）
"""
function load_local_data(
    symbol::String,
    date::Date,
    market::Symbol
)::DataFrame
    
    # 优先尝试 Parquet，其次 CSV
    for format in [PARQUET_FORMAT, CSV_FORMAT]
        path = get_local_data_path(symbol, date, market, format)
        
        if !isfile(path)
            continue
        end
        
        try
            df = if format == CSV_FORMAT
                df_csv = CSV.read(path, DataFrame)
                
                # 标准化类型
                normalize_dataframe_types(df_csv)
            else
                # Parquet 格式：读取并恢复 DateTime
                df_parquet = DataFrame(read_parquet(path))
                restore_from_parquet(df_parquet)
            end
            
            @debug "Loaded local data" symbol=symbol date=date rows=nrow(df) format=format
            
            return df
            
        catch e
            @error "Failed to load local data" path=path error=e format=format
            continue
        end
    end
    
    @debug "Local data file not found" symbol=symbol date=date
    return DataFrame()
end

"""
    load_local_data_range(symbol::String, start_date::Date, end_date::Date, market::Symbol)::DataFrame

加载日期范围内的所有本地数据
"""
function load_local_data_range(
    symbol::String,
    start_date::Date,
    end_date::Date,
    market::Symbol
)::DataFrame
    
    all_data = DataFrame[]
    loaded_dates = Date[]
    
    current_date = start_date
    while current_date <= end_date
        if has_local_data(symbol, current_date, market)
            df = load_local_data(symbol, current_date, market)
            if nrow(df) > 0
                push!(all_data, df)
                push!(loaded_dates, current_date)
            end
        end
        current_date += Day(1)
    end
    
    if isempty(all_data)
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
    
    # 合并并排序
    result = vcat(all_data...)
    sort!(result, :timestamp)
    unique!(result, :agg_trade_id)
    
    @info "Loaded local data range" symbol=symbol dates=length(loaded_dates) rows=nrow(result)
    
    return result
end

# ============================================================================
# 数据验证
# ============================================================================

"""
    validate_local_data(symbol::String, date::Date, market::Symbol)::Bool

验证本地数据的完整性
"""
function validate_local_data(
    symbol::String,
    date::Date,
    market::Symbol
)::Bool
    
    if !has_local_data(symbol, date, market)
        return false
    end
    
    try
        df = load_local_data(symbol, date, market)
        
        # 检查必需的列
        required_cols = [:agg_trade_id, :price, :quantity, :timestamp, :is_buyer_maker]
        for col in required_cols
            if !hasproperty(df, col)
                @warn "Missing required column" symbol=symbol date=date column=col
                return false
            end
        end
        
        # 检查数据量（至少应该有一些数据）
        if nrow(df) < 100
            @warn "Too few rows" symbol=symbol date=date rows=nrow(df)
            return false
        end
        
        # 检查时间范围（应该在指定日期内）
        min_date = Date(minimum(df.timestamp))
        max_date = Date(maximum(df.timestamp))
        
        if min_date != date && max_date != date
            @warn "Date mismatch" symbol=symbol expected=date actual_range=(min_date, max_date)
            return false
        end
        
        return true
        
    catch e
        @warn "Validation failed" symbol=symbol date=date error=e
        return false
    end
end

# ============================================================================
# 数据管理
# ============================================================================

"""
    clean_local_data(;older_than_days::Int=30, market::Union{Symbol,Nothing}=nothing, dry_run::Bool=false)

清理旧的本地数据
"""
function clean_local_data(;
    older_than_days::Int=30,
    market::Union{Symbol,Nothing}=nothing,
    dry_run::Bool=false
)
    
    cutoff_date = today() - Day(older_than_days)
    
    markets_to_clean = if isnothing(market)
        [:spot, :futures]
    else
        [market]
    end
    
    total_deleted = 0
    total_freed_mb = 0.0
    files_to_delete = []
    
    for mkt in markets_to_clean
        market_dir = joinpath(LOCAL_DATA_DIR, string(mkt))
        
        if !isdir(market_dir)
            continue
        end
        
        for symbol_name in readdir(market_dir)
            symbol_dir = joinpath(market_dir, symbol_name)
            
            if !isdir(symbol_dir)
                continue
            end
            
            for file in readdir(symbol_dir)
                # 跳过元数据文件
                if file == METADATA_FILE
                    continue
                end
                
                # 匹配日期
                m = match(r"(\d{4}-\d{2}-\d{2})\.(csv|parquet)$", file)
                if !isnothing(m)
                    try
                        file_date = Date(m.captures[1], "yyyy-mm-dd")
                        
                        if file_date < cutoff_date
                            file_path = joinpath(symbol_dir, file)
                            file_size_mb = stat(file_path).size / (1024 * 1024)
                            
                            push!(files_to_delete, (file_path, file_date, file_size_mb))
                            total_deleted += 1
                            total_freed_mb += file_size_mb
                        end
                    catch e
                        @warn "Error processing file" file=file error=e
                    end
                end
            end
        end
    end
    
    if dry_run
        println("\n🔍 预览清理操作（不会实际删除）:")
        println("  将删除 $total_deleted 个文件")
        println("  将释放 $(round(total_freed_mb, digits=2)) MB")
        
        if !isempty(files_to_delete)
            println("\n  文件列表:")
            for (path, date, size_mb) in first(files_to_delete, 10)
                println("    • $date ($(round(size_mb, digits=2)) MB)")
            end
            
            if length(files_to_delete) > 10
                println("    ... 还有 $(length(files_to_delete) - 10) 个文件")
            end
        end
    else
        # 实际删除
        for (path, date, size_mb) in files_to_delete
            try
                rm(path)
                @debug "Deleted old data" path=path date=date size_mb=size_mb
            catch e
                @warn "Failed to delete file" path=path error=e
            end
        end
        
        @info "Local data cleanup complete" deleted_files=total_deleted freed_mb=round(total_freed_mb, digits=2)
    end
    
    return (deleted=total_deleted, freed_mb=total_freed_mb)
end

"""
    repair_local_data(symbol::String, market::Symbol)

修复损坏的本地数据文件
"""
function repair_local_data(symbol::String, market::Symbol)
    
    println("\n🔧 检查并修复本地数据: $symbol ($market)")
    
    dates = get_available_dates(symbol, market)
    
    if isempty(dates)
        println("  没有找到本地数据")
        return
    end
    
    corrupted_count = 0
    repaired_count = 0
    
    for date in dates
        if !validate_local_data(symbol, date, market)
            corrupted_count += 1
            println("  ❌ 损坏: $date")
            
            # 删除损坏的文件（尝试两种格式）
            for format in [PARQUET_FORMAT, CSV_FORMAT]
                path = get_local_data_path(symbol, date, market, format)
                if isfile(path)
                    try
                        rm(path)
                        repaired_count += 1
                        println("    ✅ 已删除 $(format == CSV_FORMAT ? "CSV" : "Parquet")，需要重新下载")
                    catch e
                        println("    ❌ 删除失败: $e")
                    end
                end
            end
        end
    end
    
    if corrupted_count == 0
        println("  ✅ 所有数据完整")
    else
        println("\n  总计: 发现 $corrupted_count 个损坏文件，删除 $repaired_count 个")
    end
end

# ============================================================================
# 统计信息
# ============================================================================

"""
    get_local_storage_info(;market::Union{Symbol,Nothing}=nothing, detailed::Bool=false)

获取本地存储信息
"""
function get_local_storage_info(;
    market::Union{Symbol,Nothing}=nothing,
    detailed::Bool=false
)
    
    println("\n" * "="^70)
    println("本地数据存储信息")
    println("="^70)
    
    markets_to_check = if isnothing(market)
        [:spot, :futures]
    else
        [market]
    end
    
    grand_total_files = 0
    grand_total_size_mb = 0.0
    
    for mkt in markets_to_check
        market_dir = joinpath(LOCAL_DATA_DIR, string(mkt))
        
        println("\n📂 市场: $mkt")
        println("  路径: $market_dir")
        
        if !isdir(market_dir)
            println("  （无数据）")
            continue
        end
        
        total_files = 0
        total_size_mb = 0.0
        symbol_stats = []
        
        for symbol_name in sort(readdir(market_dir))
            symbol_dir = joinpath(market_dir, symbol_name)
            
            if !isdir(symbol_dir)
                continue
            end
            
            files = filter(f -> f != METADATA_FILE, readdir(symbol_dir))
            symbol_files = length(files)
            symbol_size_mb = sum(stat(joinpath(symbol_dir, f)).size for f in files) / (1024 * 1024)
            
            total_files += symbol_files
            total_size_mb += symbol_size_mb
            
            # 获取日期范围
            dates = get_available_dates(symbol_name, mkt)
            date_range = if !isempty(dates)
                "$(dates[1]) 到 $(dates[end])"
            else
                "无"
            end
            
            # 统计格式
            parquet_count = count(f -> endswith(f, ".parquet"), files)
            csv_count = count(f -> endswith(f, ".csv"), files)
            
            push!(symbol_stats, (
                symbol=symbol_name,
                files=symbol_files,
                size_mb=symbol_size_mb,
                date_range=date_range,
                dates=dates,
                parquet_count=parquet_count,
                csv_count=csv_count
            ))
        end
        
        if detailed
            println("\n  交易对详情:")
            for stat in symbol_stats
                println("    📊 $(stat.symbol):")
                println("       文件数: $(stat.files) (Parquet: $(stat.parquet_count), CSV: $(stat.csv_count))")
                println("       大小: $(round(stat.size_mb, digits=2)) MB")
                println("       日期范围: $(stat.date_range)")
                
                # 检查数据完整性
                if !isempty(stat.dates)
                    gaps = find_date_gaps(stat.dates)
                    if !isempty(gaps)
                        println("       ⚠️  缺失日期: $(length(gaps)) 个")
                    end
                end
            end
        else
            println("\n  交易对概览:")
            for stat in symbol_stats
                format_info = if stat.parquet_count > 0 && stat.csv_count > 0
                    "(混合)"
                elseif stat.parquet_count > 0
                    "(Parquet)"
                else
                    "(CSV)"
                end
                println("    📊 $(stat.symbol): $(stat.files) 天, $(round(stat.size_mb, digits=2)) MB $format_info")
            end
        end
        
        println("\n  小计: $total_files 个文件, $(round(total_size_mb, digits=2)) MB")
        
        grand_total_files += total_files
        grand_total_size_mb += total_size_mb
    end
    
    println("\n" * "="^70)
    println("总计: $grand_total_files 个文件, $(round(grand_total_size_mb, digits=2)) MB")
    println("="^70)
end

"""
    find_date_gaps(dates::Vector{Date})::Vector{Date}

找出日期序列中的缺失日期
"""
function find_date_gaps(dates::Vector{Date})::Vector{Date}
    
    if length(dates) < 2
        return Date[]
    end
    
    sorted_dates = sort(dates)
    gaps = Date[]
    
    for i in 1:(length(sorted_dates)-1)
        current = sorted_dates[i]
        next = sorted_dates[i+1]
        
        # 检查是否有缺失的日期
        expected_next = current + Day(1)
        while expected_next < next
            push!(gaps, expected_next)
            expected_next += Day(1)
        end
    end
    
    return gaps
end

"""
    print_storage_summary()

打印存储摘要（简洁版）
"""
function print_storage_summary()
    
    if !isdir(LOCAL_DATA_DIR)
        println("📦 本地存储: 无数据")
        return
    end
    
    total_size_mb = 0.0
    total_files = 0
    parquet_count = 0
    csv_count = 0
    
    for mkt in [:spot, :futures]
        market_dir = joinpath(LOCAL_DATA_DIR, string(mkt))
        
        if isdir(market_dir)
            for symbol_name in readdir(market_dir)
                symbol_dir = joinpath(market_dir, symbol_name)
                
                if isdir(symbol_dir)
                    files = filter(f -> f != METADATA_FILE, readdir(symbol_dir))
                    total_files += length(files)
                    total_size_mb += sum(stat(joinpath(symbol_dir, f)).size for f in files) / (1024 * 1024)
                    
                    parquet_count += count(f -> endswith(f, ".parquet"), files)
                    csv_count += count(f -> endswith(f, ".csv"), files)
                end
            end
        end
    end
    
    if total_files > 0
        format_info = if parquet_count > 0 && csv_count > 0
            "Parquet: $parquet_count, CSV: $csv_count"
        elseif parquet_count > 0
            "Parquet: $parquet_count"
        else
            "CSV: $csv_count"
        end
        println("📦 本地存储: $total_files 个文件, $(round(total_size_mb, digits=2)) MB ($format_info)")
    else
        println("📦 本地存储: 无数据")
    end
end

# ============================================================================
# 格式转换
# ============================================================================

"""
    convert_to_parquet(symbol::String, market::Symbol)

将 CSV 文件转换为 Parquet 格式（安全版本）
"""
function convert_to_parquet(symbol::String, market::Symbol)
    
    println("\n🔄 转换为 Parquet 格式: $symbol ($market)")
    
    dates = get_available_dates(symbol, market)
    
    if isempty(dates)
        println("  没有找到数据")
        return
    end
    
    converted_count = 0
    total_saved_mb = 0.0
    
    for date in dates
        csv_path = get_local_data_path(symbol, date, market, CSV_FORMAT)
        parquet_path = get_local_data_path(symbol, date, market, PARQUET_FORMAT)
        
        # 只转换 CSV 文件
        if isfile(csv_path) && !isfile(parquet_path)
            try
                # 读取 CSV
                df_raw = CSV.read(csv_path, DataFrame)
                
                # 创建新的 DataFrame，确保类型正确
                df = DataFrame(
                    agg_trade_id = Vector{Int64}(df_raw.agg_trade_id),
                    price = Vector{Float64}(df_raw.price),
                    quantity = Vector{Float64}(df_raw.quantity),
                    first_trade_id = Vector{Int64}(df_raw.first_trade_id),
                    last_trade_id = Vector{Int64}(df_raw.last_trade_id),
                    timestamp = Vector{DateTime}(df_raw.timestamp),
                    is_buyer_maker = Vector{Bool}(df_raw.is_buyer_maker),
                    symbol = String.(df_raw.symbol)
                )
                
                # 准备并保存为 Parquet
                df_parquet = prepare_for_parquet(df)
                write_parquet(parquet_path, df_parquet)
                
                # 更新元数据
                file_size = stat(parquet_path).size
                save_metadata(symbol, date, market, nrow(df), file_size)
                
                # 计算节省的空间
                csv_size_mb = stat(csv_path).size / (1024 * 1024)
                parquet_size_mb = file_size / (1024 * 1024)
                saved_mb = csv_size_mb - parquet_size_mb
                
                total_saved_mb += saved_mb
                
                # 删除 CSV 文件
                rm(csv_path)
                
                println("  ✅ $date: $(round(csv_size_mb, digits=2)) MB → $(round(parquet_size_mb, digits=2)) MB (节省 $(round(saved_mb, digits=2)) MB)")
                
                converted_count += 1
                
            catch e
                println("  ❌ $date: 转换失败 - $e")
            end
        end
    end
    
    if converted_count == 0
        println("  没有需要转换的文件")
    else
        println("\n  总计: 转换了 $converted_count 个文件，节省 $(round(total_saved_mb, digits=2)) MB")
    end
end  # ✅ 确保这个 end 存在