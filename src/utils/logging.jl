# src/utils/logging.jl

"""
日志系统

提供：
1. 统一的日志格式
2. 文件日志和控制台日志
3. 日志级别控制
4. 结构化日志
"""

using Logging
using LoggingExtras  # 新增这一行
using Dates

# ============================================================================
# 自定义日志格式
# ============================================================================

"""
    ColoredConsoleLogger

带颜色的控制台日志
"""
struct ColoredConsoleLogger <: AbstractLogger
    stream::IO
    min_level::LogLevel
end

ColoredConsoleLogger(stream::IO=stderr) = ColoredConsoleLogger(stream, Logging.Info)

function Logging.handle_message(logger::ColoredConsoleLogger, level, message, _module, group, id, file, line; kwargs...)
    if level < logger.min_level
        return
    end
    
    # 时间戳
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    
    # 日志级别
    level_str = string(level)
    
    # 格式化消息
    formatted = "[$timestamp] [$level_str] $message"
    
    # 添加额外信息
    if !isempty(kwargs)
        formatted *= " | " * join(["$k=$v" for (k,v) in kwargs], ", ")
    end
    
    println(logger.stream, formatted)
    flush(logger.stream)
end

Logging.min_enabled_level(logger::ColoredConsoleLogger) = logger.min_level
Logging.shouldlog(logger::ColoredConsoleLogger, level, _module, group, id) = level >= logger.min_level
Logging.catch_exceptions(logger::ColoredConsoleLogger) = false

# ============================================================================
# 文件日志
# ============================================================================

"""
    setup_file_logger(log_dir::String="logs")

设置文件日志记录器
"""
function setup_file_logger(log_dir::String="logs")
    # 创建日志目录
    if !isdir(log_dir)
        mkpath(log_dir)
    end
    
    # 日志文件名（按日期）
    date_str = Dates.format(now(), "yyyy-mm-dd")
    log_file = joinpath(log_dir, "passivbot_$(date_str).log")
    
    # 创建文件logger
    file_stream = open(log_file, "a")
    file_logger = SimpleLogger(file_stream, Logging.Debug)
    
    @info "File logging enabled: $log_file"
    
    return file_logger
end

# ============================================================================
# 组合logger（同时输出到控制台和文件）
# ============================================================================

"""
    setup_logging(;
        console_level::LogLevel=Logging.Info,
        file_level::LogLevel=Logging.Debug,
        log_dir::String="logs"
    )

设置组合日志系统
"""
function setup_logging(;
    console_level::LogLevel=Logging.Info,
    file_level::LogLevel=Logging.Debug,
    log_dir::String="logs"
)
    # 控制台logger
    console_logger = ColoredConsoleLogger(stderr, console_level)
    
    # 文件logger
    file_logger = setup_file_logger(log_dir)
    
    # 组合logger（同时输出）
    combined_logger = TeeLogger(
        MinLevelLogger(console_logger, console_level),
        MinLevelLogger(file_logger, file_level)
    )
    
    global_logger(combined_logger)
    
    @info "Logging system initialized"
    @info "Console level: $console_level"
    @info "File level: $file_level"
end

# ============================================================================
# 结构化日志辅助函数
# ============================================================================

"""
    log_trade(side::Side, symbol::Symbol, price::Float64, quantity::Float64, pnl::Float64)

记录交易日志
"""
function log_trade(side::Side, symbol::Symbol, price::Float64, quantity::Float64, pnl::Float64)
    @info "TRADE" side=side symbol=symbol price=price quantity=quantity pnl=pnl
end

"""
    log_grid_update(grid::MartingaleGrid)

记录网格状态
"""
function log_grid_update(grid::MartingaleGrid)
    @info "GRID UPDATE" symbol=grid.symbol side=grid.side total_qty=grid.total_quantity avg_entry=grid.average_entry unrealized_pnl=grid.unrealized_pnl levels=length(grid.levels)
end

"""
    log_market_state(symbol::Symbol, trend::TrendState, cci::CCISignal, volatility::VolatilityMetrics)

记录市场状态
"""
function log_market_state(symbol::Symbol, trend::TrendState, cci::CCISignal, volatility::VolatilityMetrics)
    @debug "MARKET STATE" symbol=symbol trend=trend.primary_trend adx=trend.adx cci=cci.cci_value volatility=volatility.composite
end

"""
    log_error_with_context(error::Exception, context::String)

记录带上下文的错误
"""
function log_error_with_context(error::Exception, context::String)
    @error "ERROR in $context" exception=(error, catch_backtrace())
end

# ============================================================================
# 性能日志
# ============================================================================

"""
    @timed_log

宏：记录函数执行时间
"""
macro timed_log(ex)
    quote
        local start_time = time()
        local result = $(esc(ex))
        local elapsed = time() - start_time
        @debug "Function execution time" expression=$(string(ex)) elapsed_seconds=elapsed
        result
    end
end