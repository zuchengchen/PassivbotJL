# examples/convert_to_parquet.jl

"""
CSV 到 Parquet 格式转换工具

批量转换本地存储的 CSV 文件为 Parquet 格式
"""

using Dates

include("../src/data/data_manager.jl")

println("\n" * "="^70)
println("CSV → Parquet 格式转换工具")
println("="^70)

# 获取所有交易对
function get_all_symbols(market::Symbol)
    market_dir = joinpath(LOCAL_DATA_DIR, string(market))
    
    if !isdir(market_dir)
        return String[]
    end
    
    symbols = String[]
    for name in readdir(market_dir)
        symbol_dir = joinpath(market_dir, name)
        if isdir(symbol_dir)
            push!(symbols, name)
        end
    end
    
    return sort(symbols)
end

# 主菜单
function main()
    
    println("\n选择操作:")
    println("  1. 转换单个交易对")
    println("  2. 转换所有交易对 (Spot)")
    println("  3. 转换所有交易对 (Futures)")
    println("  4. 转换所有交易对 (全部市场)")
    println("  5. 查看存储统计")
    println("  0. 退出")
    
    print("\n请选择 (0-5): ")
    choice = strip(readline())
    
    if choice == "0"
        println("\n再见！")
        return
        
    elseif choice == "1"
        # 转换单个交易对
        print("交易对 (如 BTCUSDT): ")
        symbol = strip(readline())
        
        print("市场 (spot/futures, 默认 futures): ")
        market_str = strip(readline())
        market = isempty(market_str) ? :futures : Symbol(market_str)
        
        convert_to_parquet(symbol, market)
        
    elseif choice == "2"
        # 转换所有 Spot
        symbols = get_all_symbols(:spot)
        
        if isempty(symbols)
            println("\n没有找到 Spot 数据")
        else
            println("\n找到 $(length(symbols)) 个 Spot 交易对")
            print("确认转换？(yes/no): ")
            confirm = strip(readline())
            
            if lowercase(confirm) == "yes"
                for symbol in symbols
                    convert_to_parquet(symbol, :spot)
                end
                println("\n✅ 全部完成")
            end
        end
        
    elseif choice == "3"
        # 转换所有 Futures
        symbols = get_all_symbols(:futures)
        
        if isempty(symbols)
            println("\n没有找到 Futures 数据")
        else
            println("\n找到 $(length(symbols)) 个 Futures 交易对")
            print("确认转换？(yes/no): ")
            confirm = strip(readline())
            
            if lowercase(confirm) == "yes"
                for symbol in symbols
                    convert_to_parquet(symbol, :futures)
                end
                println("\n✅ 全部完成")
            end
        end
        
    elseif choice == "4"
        # 转换全部
        spot_symbols = get_all_symbols(:spot)
        futures_symbols = get_all_symbols(:futures)
        total = length(spot_symbols) + length(futures_symbols)
        
        if total == 0
            println("\n没有找到数据")
        else
            println("\n找到:")
            println("  Spot: $(length(spot_symbols)) 个交易对")
            println("  Futures: $(length(futures_symbols)) 个交易对")
            println("  总计: $total 个交易对")
            
            print("\n确认转换？(yes/no): ")
            confirm = strip(readline())
            
            if lowercase(confirm) == "yes"
                for symbol in spot_symbols
                    convert_to_parquet(symbol, :spot)
                end
                
                for symbol in futures_symbols
                    convert_to_parquet(symbol, :futures)
                end
                
                println("\n✅ 全部完成")
            end
        end
        
    elseif choice == "5"
        # 查看统计
        get_local_storage_info(detailed=true)
        
    else
        println("\n❌ 无效选项")
    end
end

# 运行
main()

println("\n" * "="^70)