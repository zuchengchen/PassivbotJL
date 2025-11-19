# src/config/config_loader.jl

"""
配置文件加载器

支持：
- YAML配置文件
- 环境变量覆盖
- 配置验证
"""

using YAML
using Logging

"""
    load_config(config_path::String)::Dict

加载配置文件
"""
function load_config(config_path::String)::Dict
    
    if !isfile(config_path)
        error("Config file not found: $config_path")
    end
    
    @info "Loading config" path=config_path
    
    config = YAML.load_file(config_path)
    
    # 环境变量覆盖
    override_from_env!(config)
    
    # 验证配置
    validate_config!(config)
    
    @info "Config loaded successfully"
    
    return config
end

"""
    override_from_env!(config::Dict)

使用环境变量覆盖配置
"""
function override_from_env!(config::Dict)
    
    # API Key
    if haskey(ENV, "EXCHANGE_API_KEY")
        if !haskey(config, "exchange")
            config["exchange"] = Dict()
        end
        config["exchange"]["api_key"] = ENV["EXCHANGE_API_KEY"]
        @info "API Key loaded from environment variable"
    end
    
    # API Secret
    if haskey(ENV, "EXCHANGE_API_SECRET")
        if !haskey(config, "exchange")
            config["exchange"] = Dict()
        end
        config["exchange"]["api_secret"] = ENV["EXCHANGE_API_SECRET"]
        @info "API Secret loaded from environment variable"
    end
    
    # Testnet开关
    if haskey(ENV, "EXCHANGE_TESTNET")
        testnet = lowercase(ENV["EXCHANGE_TESTNET"]) in ["true", "1", "yes"]
        config["exchange"]["testnet"] = testnet
        @info "Testnet mode" enabled=testnet
    end
end

"""
    validate_config!(config::Dict)

验证配置有效性
"""
function validate_config!(config::Dict)
    
    # 检查必需字段
    if !haskey(config, "exchange")
        error("Missing 'exchange' section in config")
    end
    
    exchange = config["exchange"]
    
    # 检查API密钥
    if !haskey(exchange, "api_key") || isempty(exchange["api_key"])
        @warn "API Key not configured"
    end
    
    if !haskey(exchange, "api_secret") || isempty(exchange["api_secret"])
        @warn "API Secret not configured"
    end
    
    # 验证数值范围
    if haskey(config, "long")
        long = config["long"]
        
        if haskey(long, "leverage")
            leverage = long["leverage"]
            if leverage < 1 || leverage > 125
                @warn "Invalid leverage" value=leverage
            end
        end
        
        if haskey(long, "wallet_exposure_limit")
            exposure = long["wallet_exposure_limit"]
            if exposure < 0 || exposure > 1
                @warn "Invalid wallet exposure" value=exposure
            end
        end
    end
    
    @debug "Config validation passed"
end

"""
    get_api_credentials(config::Dict)

获取API凭证
"""
function get_api_credentials(config::Dict)
    
    if !haskey(config, "exchange")
        error("No exchange config found")
    end
    
    exchange = config["exchange"]
    
    api_key = get(exchange, "api_key", "")
    api_secret = get(exchange, "api_secret", "")
    testnet = get(exchange, "testnet", false)
    
    if isempty(api_key) || isempty(api_secret)
        error("API credentials not configured")
    end
    
    return (
        api_key = api_key,
        api_secret = api_secret,
        testnet = testnet
    )
end

"""
    print_config_summary(config::Dict)

打印配置摘要
"""
function print_config_summary(config::Dict)
    
    println("\n" * "="^70)
    println("配置摘要")
    println("="^70)
    
    if haskey(config, "strategy")
        strategy = config["strategy"]
        println("\n策略:")
        println("  名称: $(get(strategy, "name", "N/A"))")
        println("  版本: $(get(strategy, "version", "N/A"))")
    end
    
    if haskey(config, "exchange")
        exchange = config["exchange"]
        println("\n交易所:")
        println("  名称: $(get(exchange, "name", "N/A"))")
        println("  测试网: $(get(exchange, "testnet", false) ? "✅ 是" : "❌ 否")")
        
        api_key = get(exchange, "api_key", "")
        if !isempty(api_key)
            masked = api_key[1:min(8, length(api_key))] * "..." * api_key[max(1, end-4):end]
            println("  API Key: $masked")
        else
            println("  API Key: ⚠️  未配置")
        end
    end
    
    if haskey(config, "long")
        long = config["long"]
        println("\n做多配置:")
        println("  启用: $(get(long, "enabled", false) ? "✅" : "❌")")
        println("  杠杆: $(get(long, "leverage", "N/A"))x")
        println("  最大敞口: $(get(long, "wallet_exposure_limit", 0)*100)%")
        
        if haskey(long, "grid")
            grid = long["grid"]
            println("  网格间距: $(get(grid, "base_spacing", 0)*100)%")
        end
    end
    
    if haskey(config, "short")
        short = config["short"]
        println("\n做空配置:")
        println("  启用: $(get(short, "enabled", false) ? "✅" : "❌")")
    end
    
    if haskey(config, "hedge")
        hedge = config["hedge"]
        println("\n对冲配置:")
        println("  启用: $(get(hedge, "enabled", false) ? "✅" : "❌")")
        
        if haskey(hedge, "activation")
            activation = hedge["activation"]
            println("  触发条件:")
            println("    亏损阈值: $(get(activation, "loss_threshold", 0))%")
            println("    清算距离: $(get(activation, "liquidation_distance", 0))%")
        end
    end
    
    if haskey(config, "portfolio")
        portfolio = config["portfolio"]
        println("\n投资组合:")
        println("  最大品种数: $(get(portfolio, "max_symbols", 0))")
        println("  保留资金: $(get(portfolio, "reserved_capital_pct", 0))%")
        
        if haskey(portfolio, "symbol_selection") && haskey(portfolio["symbol_selection"], "universe")
            universe = portfolio["symbol_selection"]["universe"]
            println("  交易品种: $(join(universe, ", "))")
        end
    end
    
    println("\n" * "="^70)
end