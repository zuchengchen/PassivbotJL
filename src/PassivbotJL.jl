# src/PassivbotJL.jl

module PassivbotJL

using Dates
using Statistics
using Logging
using Printf

using HTTP
using JSON3
using DataFrames
using CSV
using YAML
using StatsBase
using SHA
using LoggingExtras

# ============================================================================
# 包含子模块
# ============================================================================

# 核心类型
include("core/types.jl")

# 配置管理
include("core/config.jl")

# 工具函数
include("utils/logging.jl")

# 交易所接口
include("exchange/abstract.jl")
include("exchange/binance.jl")

# 数据和指标
include("data/indicators.jl")

# 策略模块
include("strategy/trend.jl")
include("strategy/cci.jl")
include("strategy/market_analyzer.jl")
include("strategy/grid_spacing.jl")
include("strategy/grid_manager.jl")

# 执行模块
include("execution/order_executor.jl")
include("execution/trading_engine.jl")

# ============================================================================
# 导出
# ============================================================================

# 枚举类型和值
export TrendDirection, UPTREND, DOWNTREND, RANGING
export TrendStrength, WEAK, MODERATE, STRONG
export Side, LONG, SHORT
export VolatilityState, VERY_LOW, LOW, MEDIUM, HIGH, VERY_HIGH

# 数据结构
export TrendState, CCISignal, VolatilityMetrics
export GridLevel, MartingaleGrid, HedgeGrid
export TradingState, AccountBalance, Position
export StrategyConfig, ExchangeConfig
export MarketAnalysis

# 交易所
export AbstractExchange, BinanceFutures
export get_server_time, get_klines, get_ticker_price, get_ticker_24hr
export get_account_balance, get_account_info, get_position, get_all_positions
export set_leverage, set_margin_type
export place_order, cancel_order, cancel_all_orders, get_open_orders, get_order_status

# 技术指标
export calculate_ema, calculate_atr, calculate_atr_percentage
export calculate_adx, calculate_cci, calculate_rsi
export calculate_bollinger_bands, calculate_all_indicators
export validate_indicators

# 策略函数
export detect_trend, detect_trend_from_symbol
export is_trending, is_strong_trend, trend_direction_matches
export get_trend_description, should_trade_on_trend
export generate_cci_signal, generate_cci_signal_from_symbol
export has_entry_signal, is_strong_signal, should_enter_position
export get_signal_description
export analyze_market, analyze_multiple_symbols
export find_trading_opportunities, print_market_analysis

# 网格函数
export calculate_grid_spacing, calculate_grid_spacing_from_market
export calculate_grid_levels, calculate_take_profit_levels
export calculate_average_entry_price, calculate_unrealized_pnl
export calculate_liquidation_distance
export create_martingale_grid, add_grid_entry, mark_level_filled
export update_grid_metrics, create_take_profit_orders
export check_grid_health, print_grid_status
export should_add_grid_level, calculate_next_grid_quantity

# 订单执行
export OrderExecutor, OrderResult
export execute_limit_order, execute_market_order
export execute_grid_entry_orders, execute_take_profit_orders
export cancel_pending_order, cancel_all_pending_orders
export emergency_close_position
export check_order_status, update_pending_orders
export get_execution_stats, print_execution_summary

# 交易引擎
export TradingEngine
export start_engine, stop, cleanup
export main_loop_iteration
export manage_existing_grids, scan_for_opportunities
export perform_risk_checks
export create_new_grid, close_grid
export print_engine_status, print_final_stats

# 配置函数
export load_config, validate_config, print_config_summary

# 日志函数
export setup_logging, log_trade, log_grid_update, log_market_state

# ============================================================================
# 模块初始化
# ============================================================================

function __init__()
    setup_logging(console_level=Logging.Info)
    
    @info """
    ╔════════════════════════════════════════════════════════════╗
    ║                   PassivbotJL v0.1.0                       ║
    ║          Trend Following Martingale Grid System            ║
    ╚════════════════════════════════════════════════════════════╝
    """
end

end # module