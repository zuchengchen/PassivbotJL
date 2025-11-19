#!/usr/bin/env julia

# scripts/monitor.jl

"""
PassivbotJL 监控脚本

实时监控机器人状态、持仓和盈亏
"""

using PassivbotJL
using Dates
using Printf

function main()
    
    # 加载配置
    config = load_config("config/strategy.yaml")
    
    # 连接交易所
    exchange = BinanceFutures(config.exchange)
    
    println("\n" * "="^70)
    println("PassivbotJL Monitor")
    println("="^70)
    println("Press Ctrl+C to exit")
    println()
    
    try
        while true
            # 清屏（Unix）
            if Sys.isunix()
                run(`clear`)
            end
            
            println("="^70)
            println("📊 Real-time Monitor - $(now())")
            println("="^70)
            
            # ================================================================
            # 账户信息
            # ================================================================
            
            try
                balance = get_account_balance(exchange)
                account_info = get_account_info(exchange)
                
                println("\n💰 Account Status:")
                println("  Total Balance: \$$(round(balance.balance, digits=2))")
                println("  Available: \$$(round(balance.available, digits=2))")
                println("  Unrealized PNL: \$$(round(balance.cross_unrealized_pnl, digits=2))")
                println("  Total Margin: \$$(round(account_info.total_margin_balance, digits=2))")
                
            catch e
                println("  ❌ Failed to get account info: $e")
            end
            
            # ================================================================
            # 持仓信息
            # ================================================================
            
            try
                positions = get_all_positions(exchange)
                
                println("\n📈 Open Positions: $(length(positions))")
                
                if !isempty(positions)
                    println()
                    println("  " * rpad("Symbol", 12) * rpad("Side", 8) * 
                           rpad("Size", 12) * rpad("Entry", 12) * 
                           rpad("Mark", 12) * "PNL")
                    println("  " * "-"^68)
                    
                    total_pnl = 0.0
                    
                    for pos in positions
                        pnl_pct = (pos.unrealized_pnl / (pos.entry_price * pos.size)) * 100
                        pnl_str = @sprintf("\$%.2f (%.1f%%)", pos.unrealized_pnl, pnl_pct)
                        
                        # 颜色（简化版）
                        pnl_indicator = pos.unrealized_pnl >= 0 ? "🟢" : "🔴"
                        
                        println("  " * 
                               rpad(string(pos.symbol), 12) *
                               rpad(string(pos.side), 8) *
                               rpad(@sprintf("%.4f", pos.size), 12) *
                               rpad(@sprintf("\$%.2f", pos.entry_price), 12) *
                               rpad(@sprintf("\$%.2f", pos.mark_price), 12) *
                               pnl_indicator * " " * pnl_str)
                        
                        total_pnl += pos.unrealized_pnl
                    end
                    
                    println("  " * "-"^68)
                    println("  Total Unrealized PNL: \$$(round(total_pnl, digits=2))")
                end
                
            catch e
                println("  ❌ Failed to get positions: $e")
            end
            
            # ================================================================
            # 挂单信息
            # ================================================================
            
            try
                # 检查配置的交易对的挂单
                total_orders = 0
                
                for symbol in config.portfolio.symbol_universe
                    try
                        orders = get_open_orders(exchange, symbol)
                        
                        if !isempty(orders)
                            if total_orders == 0
                                println("\n📋 Open Orders:")
                            end
                            
                            println("\n  $symbol: $(length(orders)) orders")
                            
                            for order in orders[1:min(3, length(orders))]  # 只显示前3个
                                println("    - $(order.side) $(order.quantity) @ \$$(order.price)")
                            end
                            
                            if length(orders) > 3
                                println("    ... and $(length(orders) - 3) more")
                            end
                            
                            total_orders += length(orders)
                        end
                    catch
                        # 忽略单个交易对的错误
                    end
                end
                
                if total_orders == 0
                    println("\n📋 Open Orders: None")
                end
                
            catch e
                println("  ❌ Failed to get orders: $e")
            end
            
            # ================================================================
            # 市场概览
            # ================================================================
            
            println("\n📊 Market Overview:")
            
            for symbol in config.portfolio.symbol_universe[1:min(3, length(config.portfolio.symbol_universe))]
                try
                    price = get_ticker_price(exchange, symbol)
                    ticker = PassivbotJL.get_ticker_24hr(exchange, symbol)
                    
                    change_indicator = ticker.price_change_percent >= 0 ? "🟢" : "🔴"
                    
                    println("  $symbol: \$$(round(price, digits=2)) " *
                           "$change_indicator $(round(ticker.price_change_percent, digits=2))% (24h)")
                catch
                    # 忽略错误
                end
            end
            
            println("\n" * "="^70)
            println("Next update in 10 seconds... (Ctrl+C to exit)")
            
            # 等待10秒
            sleep(10)
        end
        
    catch e
        if isa(e, InterruptException)
            println("\n\nMonitor stopped.")
        else
            @error "Monitor crashed" exception=e
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end