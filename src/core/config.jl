# src/core/config.jl

"""
配置管理系统

负责：
1. 定义所有配置结构
2. 从YAML文件加载配置
3. 验证配置合理性
4. 提供配置访问接口
"""

# ============================================================================
# 配置结构定义
# ============================================================================

"""
    TrendConfig

趋势检测配置
"""
struct TrendConfig
    # 时间框架
    timeframe_primary::String          # 主趋势时间框架（如 "15m"）
    timeframe_secondary::String        # 次级确认时间框架（如 "5m"）
    
    # EMA参数
    ema_fast_period::Int               # 快速EMA周期
    ema_slow_period::Int               # 慢速EMA周期
    trend_threshold::Float64           # 趋势判断阈值（EMA分离度）
    
    # ADX参数
    adx_period::Int
    adx_threshold::Float64             # ADX阈值（判断趋势强度）
    
    # 确认要求
    confirmation_required::Bool        # 是否需要双重确认
end

"""
    CCIConfig

CCI指标配置
"""
struct CCIConfig
    period::Int                        # CCI周期
    timeframe::String                  # 时间框架
    
    # 做多阈值（上涨趋势中的超卖）
    long_thresholds::Vector{Float64}   # 如 [-50, -100, -150]
    long_position_sizes::Vector{Float64} # 对应的仓位大小
    
    # 做空阈值（下跌趋势中的超买）
    short_thresholds::Vector{Float64}  # 如 [50, 100, 150]
    short_position_sizes::Vector{Float64}
end

"""
    GridConfig

网格配置
"""
struct GridConfig
    # 基础间距
    base_spacing::Float64              # 基础网格间距
    min_spacing::Float64               # 最小间距
    max_spacing::Float64               # 最大间距
    
    # ATR参数
    use_atr_spacing::Bool              # 是否使用ATR动态间距
    atr_period::Int                    # ATR周期
    atr_timeframe::String              # ATR时间框架
    atr_multiplier_major::Float64      # 主流币ATR倍数
    atr_multiplier_alt::Float64        # 山寨币ATR倍数
    
    # 马丁格尔
    martingale_enabled::Bool
    ddown_factor::Float64              # 加倍系数
    max_levels::Int                    # 最大层数
    
    # 仓位调整
    use_position_adjustment::Bool      # 是否根据仓位调整间距
    position_spacing_factor::Float64   # 仓位对间距的影响系数
    
    # 动态数量调整
    volatility_qty_coeff::Float64      # 波动率对数量的影响
end

"""
    TakeProfitConfig

止盈配置
"""
struct TakeProfitConfig
    min_markup::Float64                # 最小止盈百分比
    markup_range::Float64              # 止盈范围
    n_close_orders::Int                # 止盈订单数量
    
    # 分批止盈（可选）
    partial_exits::Vector{NamedTuple{(:qty_pct, :profit_pct), Tuple{Float64, Float64}}}
    
    # 追踪止盈
    trailing_stop_enabled::Bool
    trailing_activation_pct::Float64   # 激活阈值
    trailing_callback_pct::Float64     # 回调幅度
end

"""
    RiskConfig

风险控制配置
"""
struct RiskConfig
    # 止损
    stop_loss_pct::Float64             # 止损百分比
    max_hold_hours::Int                # 最大持仓时间
    
    # 清算防护
    liquidation_warning_distance::Float64   # 预警距离
    liquidation_danger_distance::Float64    # 危险距离
    liquidation_critical_distance::Float64  # 紧急距离
    
    # 仓位限制
    max_position_value::Float64        # 单仓位最大价值（USD）
end

"""
    DirectionalConfig

方向性配置（做多/做空独立配置）
"""
struct DirectionalConfig
    enabled::Bool
    leverage::Int
    wallet_exposure_limit::Float64
    
    # 子配置
    grid::GridConfig
    take_profit::TakeProfitConfig
    risk::RiskConfig
end

"""
    HedgeConfig

对冲配置
"""
struct HedgeConfig
    enabled::Bool
    
    # 激活条件
    loss_threshold::Float64            # 亏损阈值（百分比）
    liquidation_distance_threshold::Float64
    max_hold_hours::Int
    
    # 对冲网格参数
    initial_size_ratio::Float64        # 初始对冲仓位比例
    max_exposure_ratio::Float64        # 最大对冲敞口
    grid_spacing::Float64
    profit_target::Float64
    asymmetry_ratio::Float64           # 网格不对称比例
    
    # 利润回收
    profit_recycling_enabled::Bool
    recycling_ratio::Float64           # 利润回收比例
end

"""
    PortfolioConfig

投资组合配置
"""
struct PortfolioConfig
    max_symbols::Int                   # 最大交易对数量
    allocation_method::Symbol          # :equal, :volatility_adjusted
    reserved_capital_pct::Float64      # 保留资金比例
    
    # 交易对选择
    symbol_universe::Vector{Symbol}    # 可选交易对列表
    min_volatility::Float64
    max_volatility::Float64
    min_volume_usd::Float64
    max_correlation::Float64
    rebalance_hours::Int               # 重新选择交易对的间隔
end

"""
    ExchangeConfig

交易所配置
"""
struct ExchangeConfig
    name::Symbol                       # :binance, :bybit, etc.
    api_key::String
    api_secret::String
    testnet::Bool                      # 是否使用测试网
    
    # API限制
    rate_limit_per_minute::Int
    order_timeout_seconds::Int
    max_retries::Int
end

"""
    StrategyConfig

完整策略配置（顶层配置）
"""
struct StrategyConfig
    name::String
    version::String
    
    # 子配置
    trend::TrendConfig
    cci::CCIConfig
    long::DirectionalConfig
    short::DirectionalConfig
    hedge::HedgeConfig
    portfolio::PortfolioConfig
    exchange::ExchangeConfig
    
    # 执行参数
    loop_interval_seconds::Int         # 主循环间隔
    
    # 通知配置
    telegram_enabled::Bool
    telegram_token::String
    telegram_chat_id::String
end

# ============================================================================
# 配置加载函数
# ============================================================================

"""
    load_config(config_path::String)::StrategyConfig

从YAML文件加载配置
"""
function load_config(config_path::String)::StrategyConfig
    @info "Loading configuration from: $config_path"
    
    # 读取YAML文件
    if !isfile(config_path)
        error("Configuration file not found: $config_path")
    end
    
    yaml_data = YAML.load_file(config_path)
    
    # 解析各个部分
    trend_config = parse_trend_config(yaml_data["trend"])
    cci_config = parse_cci_config(yaml_data["cci"])
    long_config = parse_directional_config(yaml_data["long"])
    short_config = parse_directional_config(yaml_data["short"])
    hedge_config = parse_hedge_config(yaml_data["hedge"])
    portfolio_config = parse_portfolio_config(yaml_data["portfolio"])
    exchange_config = parse_exchange_config(yaml_data["exchange"])
    
    # 创建完整配置
    config = StrategyConfig(
        yaml_data["strategy"]["name"],
        yaml_data["strategy"]["version"],
        trend_config,
        cci_config,
        long_config,
        short_config,
        hedge_config,
        portfolio_config,
        exchange_config,
        get(yaml_data["execution"], "loop_interval_seconds", 60),
        get(yaml_data["notifications"], "telegram_enabled", false),
        get(yaml_data["notifications"], "telegram_token", ""),
        get(yaml_data["notifications"], "telegram_chat_id", "")
    )
    
    # 验证配置
    validate_config(config)
    
    @info "Configuration loaded successfully"
    return config
end

# ============================================================================
# 配置解析辅助函数
# ============================================================================

function parse_trend_config(data::Dict)::TrendConfig
    return TrendConfig(
        data["timeframe_primary"],
        data["timeframe_secondary"],
        data["ema_fast_period"],
        data["ema_slow_period"],
        data["trend_threshold"],
        data["adx_period"],
        data["adx_threshold"],
        get(data, "confirmation_required", true)
    )
end

function parse_cci_config(data::Dict)::CCIConfig
    return CCIConfig(
        data["period"],
        data["timeframe"],
        Float64.(data["long_thresholds"]),
        Float64.(data["long_position_sizes"]),
        Float64.(data["short_thresholds"]),
        Float64.(data["short_position_sizes"])
    )
end

function parse_grid_config(data::Dict)::GridConfig
    return GridConfig(
        data["base_spacing"],
        data["min_spacing"],
        data["max_spacing"],
        get(data, "use_atr_spacing", true),
        get(data, "atr_period", 14),
        get(data, "atr_timeframe", "5m"),
        get(data, "atr_multiplier_major", 1.8),
        get(data, "atr_multiplier_alt", 1.3),
        get(data["martingale"], "enabled", true),
        data["martingale"]["ddown_factor"],
        data["martingale"]["max_levels"],
        get(data, "use_position_adjustment", true),
        get(data, "position_spacing_factor", 2.0),
        get(data, "volatility_qty_coeff", 20.0)
    )
end

function parse_take_profit_config(data::Dict)::TakeProfitConfig
    # 解析分批止盈
    partial_exits = if haskey(data, "partial_exits")
        [
            (qty_pct=Float64(pe["qty_pct"]), profit_pct=Float64(pe["profit_pct"]))
            for pe in data["partial_exits"]
        ]
    else
        NamedTuple{(:qty_pct, :profit_pct), Tuple{Float64, Float64}}[]
    end
    
    return TakeProfitConfig(
        data["min_markup"],
        data["markup_range"],
        data["n_close_orders"],
        partial_exits,
        get(data, "trailing_stop_enabled", false),
        get(data, "trailing_activation_pct", 3.0),
        get(data, "trailing_callback_pct", 1.5)
    )
end

function parse_risk_config(data::Dict)::RiskConfig
    return RiskConfig(
        data["stop_loss_pct"],
        data["max_hold_hours"],
        get(data, "liquidation_warning_distance", 35.0),
        get(data, "liquidation_danger_distance", 25.0),
        get(data, "liquidation_critical_distance", 15.0),
        get(data, "max_position_value", 10000.0)
    )
end

function parse_directional_config(data::Dict)::DirectionalConfig
    return DirectionalConfig(
        data["enabled"],
        data["leverage"],
        data["wallet_exposure_limit"],
        parse_grid_config(data["grid"]),
        parse_take_profit_config(data["take_profit"]),
        parse_risk_config(data["risk"])
    )
end

function parse_hedge_config(data::Dict)::HedgeConfig
    return HedgeConfig(
        data["enabled"],
        data["activation"]["loss_threshold"],
        data["activation"]["liquidation_distance"],
        data["activation"]["max_hold_hours"],
        data["grid"]["initial_size_ratio"],
        data["grid"]["max_exposure_ratio"],
        data["grid"]["spacing"],
        data["grid"]["profit_target"],
        get(data["grid"], "asymmetry_ratio", 0.7),
        data["profit_recycling"]["enabled"],
        data["profit_recycling"]["ratio"]
    )
end

function parse_portfolio_config(data::Dict)::PortfolioConfig
    # 将字符串转换为Symbol
    symbols = [Symbol(s) for s in data["symbol_selection"]["universe"]]
    
    return PortfolioConfig(
        data["max_symbols"],
        Symbol(data["allocation_method"]),
        data["reserved_capital_pct"],
        symbols,
        data["symbol_selection"]["min_volatility"],
        data["symbol_selection"]["max_volatility"],
        data["symbol_selection"]["min_volume_usd"],
        data["symbol_selection"]["max_correlation"],
        data["symbol_selection"]["rebalance_hours"]
    )
end

function parse_exchange_config(data::Dict)::ExchangeConfig
    # 从环境变量读取敏感信息（更安全）
    api_key = get(ENV, "EXCHANGE_API_KEY", get(data, "api_key", ""))
    api_secret = get(ENV, "EXCHANGE_API_SECRET", get(data, "api_secret", ""))
    
    return ExchangeConfig(
        Symbol(data["name"]),
        api_key,
        api_secret,
        get(data, "testnet", false),
        get(data, "rate_limit_per_minute", 1200),
        get(data, "order_timeout_seconds", 30),
        get(data, "max_retries", 3)
    )
end

# ============================================================================
# 配置验证
# ============================================================================

"""
    validate_config(config::StrategyConfig)

验证配置的合理性，给出警告和错误
"""
function validate_config(config::StrategyConfig)
    warnings = String[]
    errors = String[]
    
    # 1. 杠杆检查
    if config.long.leverage > 10
        push!(warnings, "⚠️  Long leverage $(config.long.leverage)x is high, recommend ≤10x")
    end
    
    if config.short.leverage > 7
        push!(warnings, "⚠️  Short leverage $(config.short.leverage)x is high, recommend ≤7x")
    end
    
    # 2. 做空应该更保守
    if config.short.enabled
        if config.short.leverage >= config.long.leverage
            push!(errors, "❌ Short leverage should be LOWER than long")
        end
        
        if config.short.wallet_exposure_limit >= config.long.wallet_exposure_limit
            push!(warnings, "⚠️  Short exposure should be LOWER than long")
        end
    end
    
    # 3. 网格间距检查
    if config.long.grid.min_spacing >= config.long.grid.max_spacing
        push!(errors, "❌ min_spacing must be < max_spacing")
    end
    
    if config.long.grid.base_spacing < config.long.grid.min_spacing
        push!(warnings, "⚠️  base_spacing is below min_spacing")
    end
    
    # 4. 马丁格尔系数检查
    if config.long.grid.ddown_factor > 2.5
        push!(warnings, "⚠️  Long ddown_factor $(config.long.grid.ddown_factor) is very aggressive")
    end
    
    # 5. CCI阈值检查
    if length(config.cci.long_thresholds) != length(config.cci.long_position_sizes)
        push!(errors, "❌ CCI long_thresholds and long_position_sizes length mismatch")
    end
    
    # 6. 总敞口检查
    total_exposure = config.long.wallet_exposure_limit + config.short.wallet_exposure_limit
    if total_exposure > 2.5
        push!(warnings, "⚠️  Total exposure $(total_exposure) is very high, recommend ≤2.0")
    end
    
    # 7. API密钥检查
    if isempty(config.exchange.api_key) || isempty(config.exchange.api_secret)
        push!(errors, "❌ Exchange API credentials not set")
    end
    
    # 输出结果
    if !isempty(errors)
        @error "Configuration validation FAILED:"
        for err in errors
            @error "  $err"
        end
        error("Configuration has errors, please fix them")
    end
    
    if !isempty(warnings)
        @warn "Configuration validation warnings:"
        for warn in warnings
            @warn "  $warn"
        end
    else
        @info "✅ Configuration validation passed"
    end
end

# ============================================================================
# 配置显示
# ============================================================================

"""
    print_config_summary(config::StrategyConfig)

打印配置摘要
"""
function print_config_summary(config::StrategyConfig)
    println("\n" * "="^70)
    println("STRATEGY CONFIGURATION SUMMARY")
    println("="^70)
    
    println("\n📊 STRATEGY: $(config.name) v$(config.version)")
    
    println("\n📈 TREND DETECTION:")
    println("  Primary timeframe: $(config.trend.timeframe_primary)")
    println("  EMA periods: $(config.trend.ema_fast_period)/$(config.trend.ema_slow_period)")
    println("  ADX threshold: $(config.trend.adx_threshold)")
    
    println("\n📉 CCI SIGNALS:")
    println("  Period: $(config.cci.period)")
    println("  Long thresholds: $(config.cci.long_thresholds)")
    println("  Short thresholds: $(config.cci.short_thresholds)")
    
    println("\n🔵 LONG CONFIGURATION:")
    println("  Enabled: $(config.long.enabled)")
    println("  Leverage: $(config.long.leverage)x")
    println("  Exposure limit: $(config.long.wallet_exposure_limit*100)%")
    println("  Grid spacing: $(config.long.grid.base_spacing*100)%")
    println("  Max levels: $(config.long.grid.max_levels)")
    println("  Ddown factor: $(config.long.grid.ddown_factor)")
    
    println("\n🔴 SHORT CONFIGURATION:")
    println("  Enabled: $(config.short.enabled)")
    if config.short.enabled
        println("  Leverage: $(config.short.leverage)x")
        println("  Exposure limit: $(config.short.wallet_exposure_limit*100)%")
        println("  Grid spacing: $(config.short.grid.base_spacing*100)%")
        println("  Max levels: $(config.short.grid.max_levels)")
    end
    
    println("\n🛡️  HEDGE CONFIGURATION:")
    println("  Enabled: $(config.hedge.enabled)")
    if config.hedge.enabled
        println("  Loss threshold: $(config.hedge.loss_threshold)%")
        println("  Initial size: $(config.hedge.initial_size_ratio*100)%")
    end
    
    println("\n💼 PORTFOLIO:")
    println("  Max symbols: $(config.portfolio.max_symbols)")
    println("  Allocation: $(config.portfolio.allocation_method)")
    println("  Reserved capital: $(config.portfolio.reserved_capital_pct)%")
    
    println("\n🔌 EXCHANGE:")
    println("  Name: $(config.exchange.name)")
    println("  Testnet: $(config.exchange.testnet)")
    
    println("\n" * "="^70)
end