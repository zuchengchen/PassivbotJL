# src/strategy/grid_spacing.jl

"""
动态网格间距计算模块

基于ATR、波动率和仓位状态计算最优网格间距
"""

using DataFrames

# ============================================================================
# 网格间距计算
# ============================================================================

"""
    calculate_grid_spacing(
        volatility::VolatilityMetrics,
        position_margin_ratio::Float64,
        config::GridConfig,
        is_major_coin::Bool=true
    )::Float64

计算动态网格间距

参数：
- volatility: 波动率指标
- position_margin_ratio: 当前仓位保证金占比（0.0-1.0）
- config: 网格配置
- is_major_coin: 是否为主流币（BTC/ETH）

返回：
- 网格间距（百分比）
"""
function calculate_grid_spacing(
    volatility::VolatilityMetrics,
    position_margin_ratio::Float64,
    config::GridConfig,
    is_major_coin::Bool=true
)::Float64
    
    # ========================================================================
    # 第一步：基于ATR的基础间距
    # ========================================================================
    
    if config.use_atr_spacing
        # 根据币种类型选择ATR倍数
        atr_multiplier = if is_major_coin
            config.atr_multiplier_major
        else
            config.atr_multiplier_alt
        end
        
        # ATR基础间距
        atr_based_spacing = volatility.atr_pct * atr_multiplier
        
        @debug "ATR-based spacing" atr_pct=volatility.atr_pct multiplier=atr_multiplier spacing=atr_based_spacing
    else
        atr_based_spacing = config.base_spacing
    end
    
    # ========================================================================
    # 第二步：仓位调整
    # ========================================================================
    
    # 仓位越大，间距越宽（降低加仓频率）
    position_multiplier = if config.use_position_adjustment
        1.0 + (position_margin_ratio * config.position_spacing_factor)
    else
        1.0
    end
    
    @debug "Position adjustment" ratio=position_margin_ratio multiplier=position_multiplier
    
    # ========================================================================
    # 第三步：波动率状态调整
    # ========================================================================
    
    # 根据波动率状态微调
    volatility_multiplier = if volatility.state == VERY_HIGH
        1.3  # 极高波动，间距加大30%
    elseif volatility.state == HIGH
        1.15  # 高波动，间距加大15%
    elseif volatility.state == VERY_LOW
        0.85  # 极低波动，间距缩小15%
    else
        1.0  # 正常波动
    end
    
    @debug "Volatility adjustment" state=volatility.state multiplier=volatility_multiplier
    
    # ========================================================================
    # 第四步：计算最终间距
    # ========================================================================
    
    # 综合计算
    final_spacing = max(
        config.base_spacing,  # 不低于基础间距
        atr_based_spacing * position_multiplier * volatility_multiplier
    )
    
    # 限制在配置的范围内
    final_spacing = clamp(final_spacing, config.min_spacing, config.max_spacing)
    
    @info "Grid spacing calculated" 
        atr_spacing=round(atr_based_spacing*100, digits=2)
        position_mult=round(position_multiplier, digits=2)
        vol_mult=round(volatility_multiplier, digits=2)
        final_spacing_pct=round(final_spacing*100, digits=2)
    
    return final_spacing
end

"""
    calculate_grid_spacing_from_market(
        exchange::AbstractExchange,
        symbol::Symbol,
        position_margin_ratio::Float64,
        config::GridConfig
    )::Float64

从市场数据直接计算网格间距
"""
function calculate_grid_spacing_from_market(
    exchange::AbstractExchange,
    symbol::Symbol,
    position_margin_ratio::Float64,
    config::GridConfig
)::Float64
    
    # 获取K线数据
    required_periods = config.atr_period + 20
    klines = get_klines(exchange, symbol, config.atr_timeframe, required_periods)
    
    # 计算波动率
    atr = calculate_atr(klines, config.atr_period)
    atr_pct = atr[end] / klines[end, :close]
    
    # 计算综合波动率
    hl_vol = mean((klines[end-19:end, :high] .- klines[end-19:end, :low]) ./ 
                   klines[end-19:end, :close])
    
    returns = diff(log.(klines[end-19:end, :close]))
    return_vol = std(returns)
    
    composite_vol = 0.5 * atr_pct + 0.3 * hl_vol + 0.2 * return_vol
    
    # 波动率状态
    vol_state = if composite_vol < 0.01
        VERY_LOW
    elseif composite_vol < 0.02
        LOW
    elseif composite_vol < 0.04
        MEDIUM
    elseif composite_vol < 0.06
        HIGH
    else
        VERY_HIGH
    end
    
    volatility = VolatilityMetrics(
        atr[end],
        atr_pct,
        hl_vol,
        return_vol,
        composite_vol,
        vol_state,
        now()
    )
    
    # 判断是否为主流币
    is_major = symbol in [:BTCUSDT, :ETHUSDT]
    
    return calculate_grid_spacing(volatility, position_margin_ratio, config, is_major)
end

# ============================================================================
# 网格价格计算
# ============================================================================

"""
    calculate_grid_levels(
        entry_price::Float64,
        side::Side,
        spacing::Float64,
        num_levels::Int,
        ddown_factor::Float64=1.5
    )::Vector{NamedTuple}

计算网格层级价格和数量

参数：
- entry_price: 入场价格
- side: 方向（LONG/SHORT）
- spacing: 网格间距（百分比）
- num_levels: 网格层数
- ddown_factor: 马丁格尔系数

返回：
- Vector of (level, price, quantity_multiplier)
"""
function calculate_grid_levels(
    entry_price::Float64,
    side::Side,
    spacing::Float64,
    num_levels::Int,
    ddown_factor::Float64=1.5
)::Vector{NamedTuple{(:level, :price, :quantity_multiplier), Tuple{Int, Float64, Float64}}}
    
    levels = NamedTuple{(:level, :price, :quantity_multiplier), Tuple{Int, Float64, Float64}}[]
    
    for i in 1:num_levels
        # 价格计算
        price = if side == LONG
            # 做多：价格向下分布
            entry_price * (1.0 - spacing * i)
        else  # SHORT
            # 做空：价格向上分布
            entry_price * (1.0 + spacing * i)
        end
        
        # 数量倍数（马丁格尔）
        quantity_multiplier = ddown_factor ^ (i - 1)
        
        push!(levels, (
            level = i,
            price = price,
            quantity_multiplier = quantity_multiplier
        ))
    end
    
    return levels
end

"""
    calculate_take_profit_levels(
        average_entry::Float64,
        total_quantity::Float64,
        side::Side,
        config::TakeProfitConfig
    )::Vector{NamedTuple}

计算止盈层级

返回：
- Vector of (price, quantity, profit_pct)
"""
function calculate_take_profit_levels(
    average_entry::Float64,
    total_quantity::Float64,
    side::Side,
    config::TakeProfitConfig
)::Vector{NamedTuple{(:price, :quantity, :profit_pct), Tuple{Float64, Float64, Float64}}}
    
    levels = NamedTuple{(:price, :quantity, :profit_pct), Tuple{Float64, Float64, Float64}}[]
    
    # 如果配置了分批止盈
    if !isempty(config.partial_exits)
        for exit_config in config.partial_exits
            profit_pct = exit_config.profit_pct / 100.0
            qty_pct = exit_config.qty_pct
            
            # 计算止盈价格
            price = if side == LONG
                average_entry * (1.0 + profit_pct)
            else  # SHORT
                average_entry * (1.0 - profit_pct)
            end
            
            quantity = total_quantity * qty_pct
            
            push!(levels, (
                price = price,
                quantity = quantity,
                profit_pct = profit_pct * 100
            ))
        end
    else
        # 默认止盈方式：均匀分布
        for i in 1:config.n_close_orders
            # 利润范围内均匀分布
            profit_pct = config.min_markup + 
                        (config.markup_range / config.n_close_orders) * i
            
            price = if side == LONG
                average_entry * (1.0 + profit_pct)
            else
                average_entry * (1.0 - profit_pct)
            end
            
            # 均匀分配数量
            quantity = total_quantity / config.n_close_orders
            
            push!(levels, (
                price = price,
                quantity = quantity,
                profit_pct = profit_pct * 100
            ))
        end
    end
    
    return levels
end

# ============================================================================
# 辅助函数
# ============================================================================

"""
    calculate_average_entry_price(
        levels::Vector{GridLevel}
    )::Float64

计算平均入场价格
"""
function calculate_average_entry_price(levels::Vector{GridLevel})::Float64
    total_value = 0.0
    total_quantity = 0.0
    
    for level in levels
        if level.filled
            total_value += level.price * level.quantity
            total_quantity += level.quantity
        end
    end
    
    if total_quantity == 0.0
        return 0.0
    end
    
    return total_value / total_quantity
end

"""
    calculate_unrealized_pnl(
        levels::Vector{GridLevel},
        current_price::Float64,
        side::Side
    )::Float64

计算未实现盈亏
"""
function calculate_unrealized_pnl(
    levels::Vector{GridLevel},
    current_price::Float64,
    side::Side
)::Float64
    
    pnl = 0.0
    
    for level in levels
        if level.filled
            if side == LONG
                pnl += (current_price - level.price) * level.quantity
            else  # SHORT
                pnl += (level.price - current_price) * level.quantity
            end
        end
    end
    
    return pnl
end

"""
    calculate_liquidation_distance(
        average_entry::Float64,
        liquidation_price::Float64,
        side::Side
    )::Float64

计算距离清算价的距离（百分比）
"""
function calculate_liquidation_distance(
    average_entry::Float64,
    liquidation_price::Float64,
    side::Side
)::Float64
    
    if liquidation_price == 0.0
        return Inf
    end
    
    distance = if side == LONG
        (average_entry - liquidation_price) / average_entry
    else  # SHORT
        (liquidation_price - average_entry) / average_entry
    end
    
    return abs(distance)
end

"""
    should_add_grid_level(
        grid::MartingaleGrid,
        current_price::Float64,
        config::GridConfig
    )::Bool

判断是否应该添加新的网格层级
"""
function should_add_grid_level(
    grid::MartingaleGrid,
    current_price::Float64,
    config::GridConfig
)::Bool
    
    # 检查是否允许新增
    if !grid.allow_new_entries
        return false
    end
    
    # 检查是否达到最大层数
    filled_levels = count(l -> l.filled, grid.levels)
    if filled_levels >= config.max_levels
        @debug "Max grid levels reached"
        return false
    end
    
    # 检查当前价格是否触发新层级
    if isempty(grid.levels)
        return true
    end
    
    # 找到最后一个成交的层级
    last_filled_level = nothing
    for level in reverse(grid.levels)
        if level.filled
            last_filled_level = level
            break
        end
    end
    
    if isnothing(last_filled_level)
        return true
    end
    
    # 计算价格变化
    price_change = if grid.side == LONG
        (last_filled_level.price - current_price) / last_filled_level.price
    else  # SHORT
        (current_price - last_filled_level.price) / last_filled_level.price
    end
    
    # 如果价格变化超过网格间距，应该添加新层级
    return price_change >= grid.current_spacing
end

"""
    calculate_next_grid_quantity(
        grid::MartingaleGrid,
        base_quantity::Float64
    )::Float64

计算下一个网格层级的数量
"""
function calculate_next_grid_quantity(
    grid::MartingaleGrid,
    base_quantity::Float64
)::Float64
    
    # 当前层级数
    current_level = count(l -> l.filled, grid.levels) + 1
    
    # 马丁格尔倍数
    multiplier = grid.martingale_factor ^ (current_level - 1)
    
    return base_quantity * multiplier
end