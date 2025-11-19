# src/core/types.jl

"""
核心数据类型定义

这个文件定义了系统中所有重要的数据结构
"""

# ============================================================================
# 枚举类型（用于表示状态）
# ============================================================================

"""趋势方向"""
@enum TrendDirection begin
    UPTREND = 1
    DOWNTREND = -1
    RANGING = 0
end

"""趋势强度"""
@enum TrendStrength begin
    WEAK = 1
    MODERATE = 2
    STRONG = 3
end

"""交易方向"""
@enum Side begin
    LONG = 1
    SHORT = -1
end

"""波动率状态"""
@enum VolatilityState begin
    VERY_LOW = 1
    LOW = 2
    MEDIUM = 3
    HIGH = 4
    VERY_HIGH = 5
end

# ============================================================================
# 市场数据结构
# ============================================================================

"""
    Kline

K线数据结构
"""
struct Kline
    timestamp::DateTime
    open::Float64
    high::Float64
    low::Float64
    close::Float64
    volume::Float64
end

"""
    MarketData

市场数据快照
"""
mutable struct MarketData
    symbol::Symbol
    timestamp::DateTime
    price::Float64
    bid::Float64
    ask::Float64
    volume_24h::Float64
    klines::Union{DataFrame, Nothing}
    
    MarketData(symbol::Symbol) = new(
        symbol,
        now(),
        0.0,
        0.0,
        0.0,
        0.0,
        nothing
    )
end

# ============================================================================
# 技术指标结构
# ============================================================================

"""
    TrendState

趋势状态
包含趋势方向、强度、确认状态等信息
"""
struct TrendState
    # 趋势方向
    primary_trend::TrendDirection      # 主趋势（15分钟）
    secondary_trend::TrendDirection    # 次级趋势（5分钟）
    
    # 趋势强度
    strength::TrendStrength
    
    # 确认状态
    confirmed::Bool                    # 是否双重确认
    
    # 指标值
    ema_fast::Float64                  # 快速EMA
    ema_slow::Float64                  # 慢速EMA
    separation_pct::Float64            # EMA分离度（百分比）
    adx::Float64                       # ADX值
    
    # 时间戳
    timestamp::DateTime
end

"""
    CCISignal

CCI入场信号
"""
struct CCISignal
    # 信号方向
    direction::Union{Side, Nothing}    # LONG, SHORT, 或 nothing（无信号）
    
    # 信号强度
    strength::Float64                  # 0.0 - 1.0
    level::Int                         # 1, 2, 3（级别）
    
    # CCI值
    cci_value::Float64
    
    # 建议仓位大小（占计划资金的比例）
    suggested_position_pct::Float64
    
    # 时间戳
    timestamp::DateTime
end

"""
    VolatilityMetrics

波动率指标
"""
struct VolatilityMetrics
    # ATR相关
    atr::Float64                       # 绝对ATR值
    atr_pct::Float64                   # ATR百分比
    
    # 其他波动率
    hl_volatility::Float64             # 高低价波动率
    return_volatility::Float64         # 收益率波动率
    
    # 综合波动率
    composite::Float64
    
    # 波动率状态
    state::VolatilityState
    
    # 时间戳
    timestamp::DateTime
end

# ============================================================================
# 网格和订单结构
# ============================================================================

"""
    GridLevel

单个网格层级
"""
mutable struct GridLevel
    level::Int                         # 层级编号（1, 2, 3...）
    price::Float64                     # 目标价格
    quantity::Float64                  # 数量
    filled::Bool                       # 是否已成交
    order_id::Union{String, Nothing}   # 交易所订单ID
    fill_time::Union{DateTime, Nothing} # 成交时间
end

"""
    MartingaleGrid

马丁格尔网格
代表一个方向的完整网格仓位
"""
mutable struct MartingaleGrid
    # 基本信息
    symbol::Symbol
    side::Side                         # LONG 或 SHORT
    
    # 入场信号
    entry_signal::CCISignal
    trend::TrendState
    
    # 网格配置（当前使用的参数）
    base_spacing::Float64
    current_spacing::Float64           # 动态调整后的间距
    martingale_factor::Float64
    max_levels::Int
    
    # 网格层级
    levels::Vector{GridLevel}
    
    # 仓位统计
    total_quantity::Float64            # 总持仓量
    average_entry::Float64             # 平均入场价
    unrealized_pnl::Float64            # 未实现盈亏
    
    # 风险指标
    wallet_exposure::Float64           # 钱包敞口比例
    liquidation_price::Float64         # 清算价格
    
    # 状态
    active::Bool                       # 是否活跃
    allow_new_entries::Bool            # 是否允许新增网格
    
    # 时间追踪
    creation_time::DateTime
    last_fill_time::Union{DateTime, Nothing}
    
    # 止盈订单
    take_profit_orders::Vector{GridLevel}
end

"""
    HedgeGrid

对冲网格
用于被套仓位的反向对冲
"""
mutable struct HedgeGrid
    # 关联的主网格
    parent_grid::MartingaleGrid
    
    # 激活信息
    activation_trigger::Symbol         # :loss, :time, :liquidation_risk
    activation_time::DateTime
    
    # 配置
    direction::Side                    # 与parent相反
    initial_size_ratio::Float64        # 初始仓位比例
    max_exposure_ratio::Float64        # 最大敞口比例
    
    # 网格设置
    grid_spacing::Float64
    profit_target::Float64
    
    # 利润回收
    recycling_enabled::Bool
    recycling_ratio::Float64           # 利润用于减少主仓位的比例
    total_recycled::Float64            # 已回收总额
    
    # 网格层级
    levels::Vector{GridLevel}
    
    # 统计
    total_profit::Float64
    total_trades::Int
    
    # 状态
    active::Bool
end

# ============================================================================
# 账户和仓位结构
# ============================================================================

"""
    AccountBalance

账户余额
"""
mutable struct AccountBalance
    total_balance::Float64             # 总余额
    available_balance::Float64         # 可用余额
    margin_balance::Float64            # 保证金余额
    unrealized_pnl::Float64            # 未实现盈亏
    
    # 时间戳
    last_update::DateTime
end

"""
    Position

交易所实际仓位（用于核对）
"""
struct Position
    symbol::Symbol
    side::Side
    size::Float64
    entry_price::Float64
    mark_price::Float64
    liquidation_price::Float64
    unrealized_pnl::Float64
    leverage::Int
end

# ============================================================================
# 交易状态
# ============================================================================

"""
    TradingState

全局交易状态
包含所有活跃的网格、账户信息等
"""
mutable struct TradingState
    # 账户信息
    account::AccountBalance
    
    # 活跃网格（按symbol索引）
    active_grids::Dict{Symbol, MartingaleGrid}
    
    # 对冲网格
    hedge_grids::Dict{Symbol, Union{HedgeGrid, Nothing}}
    
    # 市场数据缓存
    market_data::Dict{Symbol, MarketData}
    
    # 最近更新时间
    last_update::DateTime
    
    TradingState() = new(
        AccountBalance(0.0, 0.0, 0.0, 0.0, now()),
        Dict{Symbol, MartingaleGrid}(),
        Dict{Symbol, Union{HedgeGrid, Nothing}}(),
        Dict{Symbol, MarketData}(),
        now()
    )
end

# ============================================================================
# 辅助构造函数
# ============================================================================

"""
    create_grid_level(level::Int, price::Float64, quantity::Float64)

创建网格层级的便捷函数
"""
function create_grid_level(level::Int, price::Float64, quantity::Float64)
    return GridLevel(level, price, quantity, false, nothing, nothing)
end

"""
    Base.show 重载（用于漂亮打印）
"""
function Base.show(io::IO, trend::TrendState)
    print(io, "TrendState(")
    print(io, "$(trend.primary_trend), ")
    print(io, "strength=$(trend.strength), ")
    print(io, "ADX=$(round(trend.adx, digits=1)), ")
    print(io, "confirmed=$(trend.confirmed))")
end

function Base.show(io::IO, signal::CCISignal)
    print(io, "CCISignal(")
    if !isnothing(signal.direction)
        print(io, "$(signal.direction), ")
        print(io, "level=$(signal.level), ")
        print(io, "CCI=$(round(signal.cci_value, digits=1))")
    else
        print(io, "NO SIGNAL")
    end
    print(io, ")")
end

function Base.show(io::IO, grid::MartingaleGrid)
    print(io, "MartingaleGrid(")
    print(io, "$(grid.symbol) $(grid.side), ")
    print(io, "qty=$(round(grid.total_quantity, digits=4)), ")
    print(io, "avg=$(round(grid.average_entry, digits=2)), ")
    print(io, "PnL=$(round(grid.unrealized_pnl, digits=2)), ")
    print(io, "levels=$(length(grid.levels)))")
end