# test/test_live_orders_with_config.jl

using Pkg
Pkg.activate(".")

using Dates

include("../src/config/config_loader.jl")
include("../src/live/live_order_client.jl")

println("="^70)
println("实盘订单测试（使用配置文件）")
println("="^70)

# 加载配置
config_path = "config/strategy.yaml"

println("\n📋 加载配置文件: $config_path")

try
    config = load_config(config_path)
    print_config_summary(config)
    
    # 获取API凭证
    creds = get_api_credentials(config)
    
    println("\n" * "="^70)
    println("开始测试")
    println("="^70)
    
    # 创建订单客户端
    client = LiveOrderClient(creds.api_key, creds.api_secret, market=:futures)
    
    # 如果是测试网，修改base_url
    if creds.testnet
        client.base_url = "https://testnet.binancefuture.com"
        println("\n⚠️  使用测试网: $(client.base_url)")
    else
        println("\n⚠️⚠️⚠️  警告：使用主网！请确认！⚠️⚠️⚠️")
        print("确认使用主网？(输入 'YES' 继续): ")
        confirm = readline()
        if confirm != "YES"
            println("已取消")
            exit(0)
        end
    end
    
    # ========================================================================
    # 测试1: 账户信息
    # ========================================================================
    println("\n📊 测试1: 查询账户信息")
    println("-"^70)
    
    try
        account = get_account(client)
        
        println("✅ 账户查询成功！")
        println("  可用余额: \$$(account.availableBalance)")
        println("  总权益: \$$(account.totalWalletBalance)")
        
        if haskey(account, :assets)
            println("\n  资产明细:")
            for asset in account.assets
                balance = parse(Float64, asset.walletBalance)
                if balance > 0
                    println("    $(asset.asset): $(asset.walletBalance)")
                end
            end
        end
        
    catch e
        println("❌ 账户查询失败: $e")
        println("\n请检查:")
        println("  1. API Key是否正确")
        println("  2. API Key是否启用了期货权限")
        println("  3. 是否使用了正确的网络（测试网/主网）")
        exit(1)
    end
    
    # ========================================================================
    # 测试2: 持仓查询
    # ========================================================================
    println("\n📊 测试2: 查询当前持仓")
    println("-"^70)
    
    try
        positions = get_position(client)
        
        has_position = false
        for pos in positions
            amt = parse(Float64, pos.positionAmt)
            if amt != 0
                has_position = true
                println("  持仓: $(pos.symbol)")
                println("    方向: $(amt > 0 ? "做多" : "做空")")
                println("    数量: $(abs(amt))")
                println("    入场价: \$$(pos.entryPrice)")
                println("    标记价: \$$(pos.markPrice)")
                println("    未实现盈亏: \$$(pos.unRealizedProfit)")
                println("    持仓价值: \$$(pos.notional)")
                println()
            end
        end
        
        if !has_position
            println("  ✅ 当前无持仓")
        end
        
    catch e
        println("❌ 持仓查询失败: $e")
    end
    
    # ========================================================================
    # 测试3: 未完成订单
    # ========================================================================
    println("\n📊 测试3: 查询未完成订单")
    println("-"^70)
    
    try
        orders = get_open_orders(client)
        
        if isempty(orders)
            println("  ✅ 无未完成订单")
        else
            println("  未完成订单数: $(length(orders))")
            for order in orders
                println("    订单 #$(order.orderId):")
                println("      交易对: $(order.symbol)")
                println("      方向: $(order.side)")
                println("      数量: $(order.origQty)")
                println("      价格: \$$(order.price)")
                println("      状态: $(order.status)")
                println()
            end
        end
        
    catch e
        println("❌ 订单查询失败: $e")
    end
    
    # ========================================================================
    # 测试4: 下单测试（可选）
    # ========================================================================
    println("\n📊 测试4: 下单测试（可选）")
    println("-"^70)
    
    if creds.testnet
        print("是否测试下单？(y/N): ")
        test_order = lowercase(strip(readline()))
        
        if test_order == "y" || test_order == "yes"
            
            # 从配置获取交易对
            symbols = config["portfolio"]["symbol_selection"]["universe"]
            test_symbol = symbols[1]  # 使用第一个
            
            try
                # 获取当前价格
                price_url = "$(client.base_url)/fapi/v1/ticker/price?symbol=$test_symbol"
                price_data = HTTP.get(price_url)
                current_price = JSON3.read(String(price_data.body)).price
                current_price = parse(Float64, current_price)
                
                # ✅ 计算合适的订单数量（确保订单金额>=$100）
                min_notional = 120.0  # 留点余量
                order_quantity = ceil(min_notional / current_price, digits=3)
                order_value = order_quantity * current_price
                
                # 下单价格（低于市价5%，不会立即成交）
                order_price = round(current_price * 0.95, digits=1)
                
                println("\n⚠️  即将在测试网下单！")
                println("交易对: $test_symbol")
                println("当前价: \$$(current_price)")
                println("数量: $(order_quantity) (价值: \$$(round(order_value, digits=2)))")
                println("挂单价: \$$(order_price)")
                println("类型: 限价单")
                
                print("\n确认下单？(yes/NO): ")
                confirm = lowercase(strip(readline()))
                
                if confirm == "yes"
                    try
                        println("\n📤 下单中...")
                        
                        order = place_limit_order(
                            client,
                            test_symbol,
                            "BUY",
                            order_quantity,
                            order_price,
                            timeInForce="GTC"
                        )
                        
                        println("✅ 下单成功！")
                        println("  订单ID: $(order.orderId)")
                        println("  客户端ID: $(order.clientOrderId)")
                        println("  状态: $(order.status)")
                        println("  订单数量: $(order.origQty)")
                        println("  订单价格: \$$(order.price)")
                        
                        # 等待
                        println("\n⏳ 等待5秒...")
                        sleep(5)
                        
                        # 查询订单
                        println("\n📊 查询订单状态...")
                        order_status = get_order(client, test_symbol, order.orderId)
                        println("  状态: $(order_status.status)")
                        println("  已成交: $(order_status.executedQty)")
                        println("  未成交: $(parse(Float64, order_status.origQty) - parse(Float64, order_status.executedQty))")
                        
                        # 撤销
                        print("\n是否撤销此订单？(y/N): ")
                        cancel_confirm = lowercase(strip(readline()))
                        
                        if cancel_confirm == "y" || cancel_confirm == "yes"
                            println("\n🗑️  撤销订单...")
                            cancel_result = cancel_order(client, test_symbol, order.orderId)
                            println("✅ 订单已撤销")
                            println("  订单ID: $(cancel_result.orderId)")
                            println("  状态: $(cancel_result.status)")
                        else
                            println("\n⚠️  订单未撤销，仍在挂单中")
                            println("  可以稍后手动撤销或等待成交")
                        end
                        
                    catch e
                        println("❌ 下单失败: $e")
                        
                        # 尝试解析错误信息
                        if isa(e, HTTP.Exceptions.StatusError)
                            try
                                error_body = String(e.response.body)
                                error_data = JSON3.read(error_body)
                                println("\n错误详情:")
                                println("  错误代码: $(error_data.code)")
                                println("  错误信息: $(error_data.msg)")
                                
                                # 针对常见错误给出建议
                                if error_data.code == -4164
                                    println("\n💡 建议:")
                                    println("  - 订单金额太小，Binance要求最小\$100")
                                    println("  - 当前订单金额: \$$(round(order_value, digits=2))")
                                    println("  - 请增加订单数量")
                                elseif error_data.code == -1021
                                    println("\n💡 建议:")
                                    println("  - 时间戳问题，请同步系统时间")
                                    println("  - 运行: sudo ntpdate -s time.nist.gov")
                                elseif error_data.code == -1022
                                    println("\n💡 建议:")
                                    println("  - 签名验证失败")
                                    println("  - 检查API Secret是否正确")
                                end
                            catch
                                # 无法解析错误
                            end
                        end
                    end
                else
                    println("已取消下单测试")
                end
                
            catch e
                println("❌ 获取价格失败: $e")
            end
        else
            println("跳过下单测试")
        end
    else
        println("⚠️  主网模式，跳过下单测试")
        println("如需测试下单，请在测试网进行")
    end
    
    # ========================================================================
    # 测试5: 查询所有订单（包括历史订单）
    # ========================================================================
    println("\n📊 测试5: 查询最近订单历史")
    println("-"^70)
    
    if creds.testnet
        try
            # 查询所有订单（包括已完成的）
            all_orders = get_open_orders(client)
            
            if !isempty(all_orders)
                println("  最近订单:")
                for (i, order) in enumerate(all_orders[1:min(5, length(all_orders))])
                    println("    $(i). $(order.symbol) $(order.side) $(order.origQty) @ \$$(order.price)")
                    println("       状态: $(order.status)")
                end
            else
                println("  ✅ 无历史订单")
            end
            
        catch e
            println("❌ 查询失败: $e")
        end
    end
    
    # ========================================================================
    # 统计
    # ========================================================================
    println("\n" * "="^70)
    println("测试完成")
    println("="^70)
    
    print_order_stats(client)
    
    println("\n✅ 所有测试完成！")
    
    if creds.testnet
        println("\n💡 提示:")
        println("  - 当前使用测试网，资金是虚拟的")
        println("  - 测试网地址: https://testnet.binancefuture.com")
        println("  - 可以在网站上查看订单和持仓")
        println("  - 测试满意后可以切换到主网")
        println("  - 切换方法: 修改 config/strategy.yaml 中的 testnet: false")
        println("\n⚠️  重要提醒:")
        println("  - 主网交易使用真实资金，请谨慎操作")
        println("  - 建议先在测试网运行至少24小时")
        println("  - 确保理解所有风险参数")
    else
        println("\n⚠️  警告:")
        println("  - 当前使用主网，请谨慎操作！")
        println("  - 建议先在测试网充分测试")
        println("  - 确保风险控制参数正确")
    end
    
catch e
    println("\n❌ 测试失败: $e")
    println("\n请检查:")
    println("  1. 配置文件是否存在: $config_path")
    println("  2. YAML格式是否正确")
    println("  3. API密钥是否已填写")
    println("  4. 网络连接是否正常")
    
    # 打印详细错误信息
    if isa(e, LoadError) || isa(e, SystemError)
        println("\n详细错误:")
        showerror(stdout, e)
        println()
    end
    
    rethrow(e)
end