# examples/manage_local_data.jl

"""
本地数据管理工具

提供交互式命令行界面管理本地数据
"""

using Dates

include("../src/data/data_manager.jl")

function print_menu()
    println("\n" * "="^70)
    println("本地数据管理工具")
    println("="^70)
    println("\n选项:")
    println("  1. 查看存储信息")
    println("  2. 查看存储信息（详细）")
    println("  3. 验证数据完整性")
    println("  4. 修复损坏数据")
    println("  5. 清理旧数据（预览）")
    println("  6. 清理旧数据（执行）")
    println("  7. 查看回测缓存")
    println("  8. 清理回测缓存")
    println("  9. 下载指定日期数据")
    println("  0. 退出")
    println("\n" * "="^70)
end

function get_user_input(prompt::String)::String
    print(prompt)
    return strip(readline())
end

function main()
    
    while true
        print_menu()
        
        choice = get_user_input("\n请选择操作 (0-9): ")
        
        if choice == "0"
            println("\n再见！")
            break
            
        elseif choice == "1"
            # 查看存储信息
            get_local_storage_info()
            
        elseif choice == "2"
            # 查看存储信息（详细）
            get_local_storage_info(detailed=true)
            
        elseif choice == "3"
            # 验证数据
            symbol = get_user_input("交易对 (如 BTCUSDT): ")
            market_str = get_user_input("市场 (spot/futures, 默认 futures): ")
            market = isempty(market_str) ? :futures : Symbol(market_str)
            
            println("\n验证 $symbol ($market) 的数据...")
            
            dates = get_available_dates(symbol, market)
            
            if isempty(dates)
                println("  没有找到本地数据")
            else
                valid_count = 0
                invalid_count = 0
                
                for date in dates
                    is_valid = validate_local_data(symbol, date, market)
                    
                    if is_valid
                        valid_count += 1
                    else
                        invalid_count += 1
                        println("  ❌ $date")
                    end
                end
                
                println("\n总计:")
                println("  ✅ 有效: $valid_count")
                println("  ❌ 无效: $invalid_count")
            end
            
        elseif choice == "4"
            # 修复数据
            symbol = get_user_input("交易对 (如 BTCUSDT): ")
            market_str = get_user_input("市场 (spot/futures, 默认 futures): ")
            market = isempty(market_str) ? :futures : Symbol(market_str)
            
            repair_local_data(symbol, market)
            
        elseif choice == "5"
            # 清理旧数据（预览）
            days_str = get_user_input("清理多少天前的数据 (默认 30): ")
            days = isempty(days_str) ? 30 : parse(Int, days_str)
            
            market_str = get_user_input("市场 (spot/futures/all, 默认 all): ")
            market = if isempty(market_str) || market_str == "all"
                nothing
            else
                Symbol(market_str)
            end
            
            clean_local_data(older_than_days=days, market=market, dry_run=true)
            
        elseif choice == "6"
            # 清理旧数据（执行）
            days_str = get_user_input("清理多少天前的数据 (默认 30): ")
            days = isempty(days_str) ? 30 : parse(Int, days_str)
            
            market_str = get_user_input("市场 (spot/futures/all, 默认 all): ")
            market = if isempty(market_str) || market_str == "all"
                nothing
            else
                Symbol(market_str)
            end
            
            confirm = get_user_input("确认删除？(yes/no): ")
            
            if lowercase(confirm) == "yes"
                clean_local_data(older_than_days=days, market=market, dry_run=false)
                println("\n✅ 清理完成")
            else
                println("\n❌ 取消操作")
            end
            
        elseif choice == "7"
            # 查看回测缓存
            get_cache_info()
            
        elseif choice == "8"
            # 清理回测缓存
            days_str = get_user_input("清理多少天前的缓存 (默认 7): ")
            days = isempty(days_str) ? 7 : parse(Int, days_str)
            
            confirm = get_user_input("确认删除？(yes/no): ")
            
            if lowercase(confirm) == "yes"
                clear_backtest_cache(older_than_days=days)
                println("\n✅ 清理完成")
            else
                println("\n❌ 取消操作")
            end
            
        elseif choice == "9"
            # 下载指定日期数据
            symbol = get_user_input("交易对 (如 BTCUSDT): ")
            
            start_str = get_user_input("开始日期 (yyyy-mm-dd, 如 2024-11-10): ")
            end_str = get_user_input("结束日期 (yyyy-mm-dd, 如 2024-11-12): ")
            
            market_str = get_user_input("市场 (spot/futures, 默认 futures): ")
            market = isempty(market_str) ? :futures : Symbol(market_str)
            
            try
                start_date = Date(start_str, "yyyy-mm-dd")
                end_date = Date(end_str, "yyyy-mm-dd")
                
                start_time = DateTime(start_date)
                end_time = DateTime(end_date, Time(23, 59, 59))
                
                println("\n开始下载...")
                
                df = fetch_data(
                    symbol,
                    start_time,
                    end_time,
                    market=market,
                    use_cache=true,
                    verbose=true
                )
                
                println("\n✅ 下载完成: $(nrow(df)) 笔交易")
                
            catch e
                println("\n❌ 错误: $e")
            end
            
        else
            println("\n❌ 无效选项，请重新选择")
        end
        
        println("\n按回车继续...")
        readline()
    end
end

# 运行主程序
println("启动本地数据管理工具...")
main()