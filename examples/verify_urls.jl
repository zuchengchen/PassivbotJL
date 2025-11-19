# examples/verify_urls.jl

"""
验证Binance Vision URL格式
"""

using HTTP
using Dates

const VISION_BASE_URL = "https://data.binance.vision"

function test_url(url::String)
    println("测试URL: $url")
    
    try
        # 使用 GET 请求并设置 range header 来只获取部分数据（更快）
        # 或者直接用 GET 请求检查状态
        response = HTTP.request("HEAD", url, status_exception=false)
        
        if response.status == 200
            # 获取文件大小
            content_length = nothing
            for (key, value) in response.headers
                if lowercase(key) == "content-length"
                    content_length = value
                    break
                end
            end
            
            size_mb = if !isnothing(content_length)
                parse(Int, content_length) / 1024 / 1024
            else
                0.0
            end
            
            println("  ✅ 成功 ($(round(size_mb, digits=2)) MB)")
            return true
            
        elseif response.status == 404
            println("  ❌ 失败: 文件不存在 (404)")
            return false
        else
            println("  ⚠️  状态码: $(response.status)")
            return false
        end
        
    catch e
        println("  ❌ 失败: $(typeof(e))")
        if isdefined(Main, :InteractiveUtils)
            showerror(stdout, e)
        end
        return false
    end
end

println("\n" * "="^70)
println("Binance Vision URL 格式验证")
println("="^70)

# 测试不同的URL格式
symbol = "BTCUSDT"
test_date = Date(2024, 11, 12)  # 使用已知存在的历史日期
date_str = Dates.format(test_date, "yyyy-mm-dd")

println("\n交易对: $symbol")
println("日期: $test_date")
println()

# 测试 aggTrades
println("\n【aggTrades 格式测试】")

# 格式: /data/futures/um/daily/aggTrades/BTCUSDT/BTCUSDT-aggTrades-2024-11-12.zip
url1 = "$(VISION_BASE_URL)/data/futures/um/daily/aggTrades/$(symbol)/$(symbol)-aggTrades-$(date_str).zip"
test_url(url1)

# 测试 klines
println("\n【Klines 格式测试】")

interval = "1m"

# 格式: /data/futures/um/daily/klines/BTCUSDT/1m/BTCUSDT-1m-2024-11-12.zip
url2 = "$(VISION_BASE_URL)/data/futures/um/daily/klines/$(symbol)/$(interval)/$(symbol)-$(interval)-$(date_str).zip"
test_url(url2)

# 测试月度数据
println("\n【月度数据格式测试】")

year = 2024
month = 10
month_str = lpad(month, 2, '0')

# 格式: /data/futures/um/monthly/aggTrades/BTCUSDT/BTCUSDT-aggTrades-2024-10.zip
url3 = "$(VISION_BASE_URL)/data/futures/um/monthly/aggTrades/$(symbol)/$(symbol)-aggTrades-$(year)-$(month_str).zip"
test_url(url3)

# 测试现货数据
println("\n【现货数据格式测试】")

# 格式: /data/spot/daily/aggTrades/BTCUSDT/BTCUSDT-aggTrades-2024-11-12.zip
url4 = "$(VISION_BASE_URL)/data/spot/daily/aggTrades/$(symbol)/$(symbol)-aggTrades-$(date_str).zip"
test_url(url4)

println("\n" * "="^70)
println("验证完成")
println("="^70)