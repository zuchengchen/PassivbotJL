# src/execution/order_executor.jl

"""
订单执行器

负责订单的创建、提交、跟踪和管理
"""

using Dates

# ============================================================================
# 订单执行结果
# ============================================================================

"""
    OrderResult

订单执行结果
"""
struct OrderResult
    success::Bool
    order_id::Union{String, Nothing}
    filled_price::Union{Float64, Nothing}
    filled_quantity::Union{Float64, Nothing}
    error_message::Union{String, Nothing}
    timestamp::DateTime
end

# ============================================================================
# 订单执行器
# ============================================================================

"""
    OrderExecutor

订单执行器，管理所有订单操作
"""
mutable struct OrderExecutor
    exchange::AbstractExchange
    max_retries::Int
    retry_delay::Float64  # 秒
    
    # 订单跟踪
    pending_orders::Dict{String, Any}  # order_id => order_info
    filled_orders::Vector{Any}
    failed_orders::Vector{Any}
    
    function OrderExecutor(exchange::AbstractExchange, max_retries::Int=3, retry_delay::Float64=1.0)
        new(
            exchange,
            max_retries,
            retry_delay,
            Dict{String, Any}(),
            [],
            []
        )
    end
end

# ============================================================================
# 限价单执行
# ============================================================================

"""
    execute_limit_order(
        executor::OrderExecutor,
        symbol::Symbol,
        side::Side,
        price::Float64,
        quantity::Float64;
        reduce_only::Bool=false,
        client_order_id::Union{String, Nothing}=nothing
    )::OrderResult

执行限价单

参数：
- executor: 订单执行器
- symbol: 交易对
- side: 方向
- price: 价格
- quantity: 数量
- reduce_only: 是否只减仓
- client_order_id: 自定义订单ID

返回：
- OrderResult
"""
function execute_limit_order(
    executor::OrderExecutor,
    symbol::Symbol,
    side::Side,
    price::Float64,
    quantity::Float64;
    reduce_only::Bool=false,
    client_order_id::Union{String, Nothing}=nothing
)::OrderResult
    
    side_str = side == LONG ? "BUY" : "SELL"
    
    @info "Executing limit order" symbol=symbol side=side_str price=price quantity=quantity
    
    # 重试逻辑
    for attempt in 1:executor.max_retries
        try
            # 提交订单
            order_id = place_order(
                executor.exchange,
                symbol,
                side_str,
                "LIMIT",
                quantity,
                price,
                reduce_only=reduce_only
            )
            
            # 记录挂单
            order_info = Dict(
                "order_id" => order_id,
                "symbol" => symbol,
                "side" => side,
                "price" => price,
                "quantity" => quantity,
                "reduce_only" => reduce_only,
                "status" => "PENDING",
                "created_at" => now()
            )
            
            executor.pending_orders[order_id] = order_info
            
            @info "Limit order placed successfully" order_id=order_id attempt=attempt
            
            return OrderResult(
                true,
                order_id,
                nothing,  # 限价单未立即成交
                nothing,
                nothing,
                now()
            )
            
        catch e
            @error "Failed to place limit order" attempt=attempt error=e
            
            if attempt < executor.max_retries
                @warn "Retrying in $(executor.retry_delay) seconds..."
                sleep(executor.retry_delay)
            else
                # 最后一次尝试失败
                push!(executor.failed_orders, Dict(
                    "symbol" => symbol,
                    "side" => side,
                    "price" => price,
                    "quantity" => quantity,
                    "error" => string(e),
                    "timestamp" => now()
                ))
                
                return OrderResult(
                    false,
                    nothing,
                    nothing,
                    nothing,
                    string(e),
                    now()
                )
            end
        end
    end
    
    # 不应该到达这里
    return OrderResult(false, nothing, nothing, nothing, "Unknown error", now())
end

# ============================================================================
# 市价单执行
# ============================================================================

"""
    execute_market_order(
        executor::OrderExecutor,
        symbol::Symbol,
        side::Side,
        quantity::Float64;
        reduce_only::Bool=false
    )::OrderResult

执行市价单（立即成交）
"""
function execute_market_order(
    executor::OrderExecutor,
    symbol::Symbol,
    side::Side,
    quantity::Float64;
    reduce_only::Bool=false
)::OrderResult
    
    side_str = side == LONG ? "BUY" : "SELL"
    
    @info "Executing market order" symbol=symbol side=side_str quantity=quantity
    
    for attempt in 1:executor.max_retries
        try
            # 提交市价单
            order_id = place_order(
                executor.exchange,
                symbol,
                side_str,
                "MARKET",
                quantity,
                nothing,
                reduce_only=reduce_only
            )
            
            # 等待成交
            sleep(0.5)
            
            # 查询订单状态
            order_status = get_order_status(executor.exchange, symbol, order_id)
            
            # 记录成交
            filled_info = Dict(
                "order_id" => order_id,
                "symbol" => symbol,
                "side" => side,
                "quantity" => quantity,
                "filled_price" => order_status.avg_price,
                "filled_quantity" => order_status.executed_qty,
                "timestamp" => now()
            )
            
            push!(executor.filled_orders, filled_info)
            
            @info "Market order filled" order_id=order_id price=order_status.avg_price
            
            return OrderResult(
                true,
                order_id,
                order_status.avg_price,
                order_status.executed_qty,
                nothing,
                now()
            )
            
        catch e
            @error "Failed to execute market order" attempt=attempt error=e
            
            if attempt < executor.max_retries
                sleep(executor.retry_delay)
            else
                return OrderResult(false, nothing, nothing, nothing, string(e), now())
            end
        end
    end
    
    return OrderResult(false, nothing, nothing, nothing, "Unknown error", now())
end

# ============================================================================
# 批量订单执行
# ============================================================================

"""
    execute_grid_entry_orders(
        executor::OrderExecutor,
        grid::MartingaleGrid,
        levels::Vector{GridLevel}
    )::Vector{OrderResult}

批量执行网格入场订单
"""
function execute_grid_entry_orders(
    executor::OrderExecutor,
    grid::MartingaleGrid,
    levels::Vector{GridLevel}
)::Vector{OrderResult}
    
    results = OrderResult[]
    
    for level in levels
        result = execute_limit_order(
            executor,
            grid.symbol,
            grid.side,
            level.price,
            level.quantity,
            reduce_only=false
        )
        
        push!(results, result)
        
        # 避免触发速率限制
        sleep(0.1)
    end
    
    return results
end

"""
    execute_take_profit_orders(
        executor::OrderExecutor,
        grid::MartingaleGrid
    )::Vector{OrderResult}

执行止盈订单
"""
function execute_take_profit_orders(
    executor::OrderExecutor,
    grid::MartingaleGrid
)::Vector{OrderResult}
    
    results = OrderResult[]
    
    # 反向方向（平仓）
    close_side = grid.side == LONG ? SHORT : LONG
    
    for tp_order in grid.take_profit_orders
        result = execute_limit_order(
            executor,
            grid.symbol,
            close_side,
            tp_order.price,
            tp_order.quantity,
            reduce_only=true
        )
        
        push!(results, result)
        sleep(0.1)
    end
    
    return results
end

# ============================================================================
# 订单管理
# ============================================================================

"""
    check_order_status(
        executor::OrderExecutor,
        order_id::String,
        symbol::Symbol
    )::Union{NamedTuple, Nothing}

检查订单状态
"""
function check_order_status(
    executor::OrderExecutor,
    order_id::String,
    symbol::Symbol
)::Union{NamedTuple, Nothing}
    
    try
        status = get_order_status(executor.exchange, symbol, order_id)
        
        # 如果订单已成交，从挂单中移除
        if status.status in ["FILLED", "PARTIALLY_FILLED"]
            if haskey(executor.pending_orders, order_id)
                order_info = executor.pending_orders[order_id]
                order_info["status"] = status.status
                order_info["filled_price"] = status.avg_price
                order_info["filled_quantity"] = status.executed_qty
                
                push!(executor.filled_orders, order_info)
                delete!(executor.pending_orders, order_id)
                
                @info "Order filled" order_id=order_id price=status.avg_price qty=status.executed_qty
            end
        end
        
        return status
        
    catch e
        @error "Failed to check order status" order_id=order_id error=e
        return nothing
    end
end

"""
    cancel_pending_order(
        executor::OrderExecutor,
        order_id::String,
        symbol::Symbol
    )::Bool

取消挂单
"""
function cancel_pending_order(
    executor::OrderExecutor,
    order_id::String,
    symbol::Symbol
)::Bool
    
    try
        cancel_order(executor.exchange, symbol, order_id)
        
        # 从挂单中移除
        if haskey(executor.pending_orders, order_id)
            delete!(executor.pending_orders, order_id)
        end
        
        @info "Order cancelled" order_id=order_id
        return true
        
    catch e
        @error "Failed to cancel order" order_id=order_id error=e
        return false
    end
end

"""
    cancel_all_pending_orders(
        executor::OrderExecutor,
        symbol::Symbol
    )::Int

取消某交易对的所有挂单

返回：取消的订单数量
"""
function cancel_all_pending_orders(
    executor::OrderExecutor,
    symbol::Symbol
)::Int
    
    try
        cancel_all_orders(executor.exchange, symbol)
        
        # 清理本地记录
        cancelled_count = 0
        for (order_id, order_info) in executor.pending_orders
            if order_info["symbol"] == symbol
                delete!(executor.pending_orders, order_id)
                cancelled_count += 1
            end
        end
        
        @info "All orders cancelled for $symbol" count=cancelled_count
        return cancelled_count
        
    catch e
        @error "Failed to cancel all orders" symbol=symbol error=e
        return 0
    end
end

"""
    update_pending_orders(executor::OrderExecutor)

更新所有挂单状态
"""
function update_pending_orders(executor::OrderExecutor)
    
    order_ids = collect(keys(executor.pending_orders))
    
    for order_id in order_ids
        order_info = executor.pending_orders[order_id]
        symbol = order_info["symbol"]
        
        check_order_status(executor, order_id, symbol)
        
        # 避免速率限制
        sleep(0.05)
    end
end

# ============================================================================
# 紧急平仓
# ============================================================================

"""
    emergency_close_position(
        executor::OrderExecutor,
        symbol::Symbol,
        quantity::Float64,
        side::Side
    )::OrderResult

紧急平仓（使用市价单）
"""
function emergency_close_position(
    executor::OrderExecutor,
    symbol::Symbol,
    quantity::Float64,
    side::Side
)::OrderResult
    
    @warn "EMERGENCY CLOSE initiated" symbol=symbol quantity=quantity side=side
    
    # 先取消所有挂单
    cancel_all_pending_orders(executor, symbol)
    
    # 反向市价单平仓
    close_side = side == LONG ? SHORT : LONG
    
    result = execute_market_order(
        executor,
        symbol,
        close_side,
        quantity,
        reduce_only=true
    )
    
    if result.success
        @info "Emergency close successful"
    else
        @error "Emergency close FAILED" error=result.error_message
    end
    
    return result
end

# ============================================================================
# 统计和报告
# ============================================================================

"""
    get_execution_stats(executor::OrderExecutor)::NamedTuple

获取执行统计
"""
function get_execution_stats(executor::OrderExecutor)::NamedTuple
    
    total_filled = length(executor.filled_orders)
    total_failed = length(executor.failed_orders)
    total_pending = length(executor.pending_orders)
    
    # 计算成功率
    total_attempted = total_filled + total_failed
    success_rate = if total_attempted > 0
        total_filled / total_attempted
    else
        0.0
    end
    
    return (
        total_filled = total_filled,
        total_failed = total_failed,
        total_pending = total_pending,
        success_rate = success_rate,
        pending_order_ids = collect(keys(executor.pending_orders))
    )
end

"""
    print_execution_summary(executor::OrderExecutor)

打印执行摘要
"""
function print_execution_summary(executor::OrderExecutor)
    
    stats = get_execution_stats(executor)
    
    println("\n" * "="^70)
    println("订单执行摘要")
    println("="^70)
    
    println("已成交订单: $(stats.total_filled)")
    println("失败订单: $(stats.total_failed)")
    println("挂单中: $(stats.total_pending)")
    println("成功率: $(round(stats.success_rate * 100, digits=1))%")
    
    if stats.total_pending > 0
        println("\n挂单列表:")
        for order_id in stats.pending_order_ids
            order_info = executor.pending_orders[order_id]
            println("  - $order_id: $(order_info["symbol"]) $(order_info["side"]) @ \$$(order_info["price"])")
        end
    end
    
    println("="^70)
end