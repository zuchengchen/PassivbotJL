# src/exchange/abstract.jl

"""
交易所抽象接口

定义所有交易所必须实现的接口
这样可以轻松支持多个交易所（Binance, Bybit, OKX等）
"""

# ============================================================================
# 抽象类型
# ============================================================================

"""
    AbstractExchange

所有交易所的抽象基类
"""
abstract type AbstractExchange end

# ============================================================================
# 必须实现的接口函数
# ============================================================================

"""
    get_server_time(exchange::AbstractExchange)

获取交易所服务器时间
"""
function get_server_time(exchange::AbstractExchange)
    error("get_server_time not implemented for $(typeof(exchange))")
end

"""
    get_klines(exchange::AbstractExchange, symbol::Symbol, interval::String, limit::Int)

获取K线数据
"""
function get_klines(exchange::AbstractExchange, symbol::Symbol, interval::String, limit::Int)
    error("get_klines not implemented for $(typeof(exchange))")
end

"""
    get_ticker_price(exchange::AbstractExchange, symbol::Symbol)

获取当前价格
"""
function get_ticker_price(exchange::AbstractExchange, symbol::Symbol)
    error("get_ticker_price not implemented for $(typeof(exchange))")
end

"""
    get_account_balance(exchange::AbstractExchange)

获取账户余额
"""
function get_account_balance(exchange::AbstractExchange)
    error("get_account_balance not implemented for $(typeof(exchange))")
end

"""
    get_position(exchange::AbstractExchange, symbol::Symbol)

获取持仓信息
"""
function get_position(exchange::AbstractExchange, symbol::Symbol)
    error("get_position not implemented for $(typeof(exchange))")
end

"""
    place_order(exchange::AbstractExchange, symbol::Symbol, side::String, 
                order_type::String, quantity::Float64, price::Union{Float64, Nothing})

下单
"""
function place_order(exchange::AbstractExchange, symbol::Symbol, side::String,
                    order_type::String, quantity::Float64, price::Union{Float64, Nothing})
    error("place_order not implemented for $(typeof(exchange))")
end

"""
    cancel_order(exchange::AbstractExchange, symbol::Symbol, order_id::String)

撤单
"""
function cancel_order(exchange::AbstractExchange, symbol::Symbol, order_id::String)
    error("cancel_order not implemented for $(typeof(exchange))")
end

"""
    get_open_orders(exchange::AbstractExchange, symbol::Symbol)

获取未成交订单
"""
function get_open_orders(exchange::AbstractExchange, symbol::Symbol)
    error("get_open_orders not implemented for $(typeof(exchange))")
end