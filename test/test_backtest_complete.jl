# test/test_backtest_complete.jl

"""
完整回测系统测试

测试流程：
1. 加载真实Tick数据
2. 初始化回测引擎
3. 运行回测
4. 输出性能报告
"""

using Pkg
Pkg.activate(".")

using Dates
using DataFrames
using Logging

# 加载模块
include("../src/PassivbotJL.jl")
using .PassivbotJL

include("../src/core/events.jl")
include("../src/data/tick_data.jl")
include("../src/data/data_manager.jl")
include("../src/execution/position_manager.jl")  # ✅ 添加这行

# ============================================================================
# 测试配置
# ============================================================================

const TEST_SYMBOL = "BTCUSDT"
const TEST_START = DateTime(2024, 11, 13, 0, 0, 0)
const TEST_END = DateTime(2024, 11, 13, 1, 0, 0)  # 1小时测试
const INITIAL_CAPITAL = 10000.0

# ============================================================================
# 辅助函数
# ============================================================================

"""打印分隔线"""
function print_separator(title::String="")
    println("\n" * "="^70)
    if !isempty(title)
        println(title)
        println("="^70)
    end
end

# ============================================================================
# 步骤1：加载数据
# ============================================================================

function test_data_loading()
    print_separator("步骤1：加载Tick数据")
    
    @info "测试参数" symbol=TEST_SYMBOL start_time=TEST_START end_time=TEST_END
    
    # 尝试从本地加载
    local_file = "data/ticks/$(TEST_SYMBOL)_$(Dates.format(TEST_START, "yyyymmdd"))_1h.csv"
    
    tick_data = if isfile(local_file)
        @info "从本地文件加载" file=local_file
        load_tick_data(local_file)
    else
        @info "从API下载数据..."
        df = fetch_data_for_backtest(
            TEST_SYMBOL,
            TEST_START,
            TEST_END,
            market=:futures,
            force_refresh=false
        )
        
        # 转换列名以匹配tick_data格式
        if hasproperty(df, :agg_trade_id)
            rename!(df, :agg_trade_id => :trade_id)
        end
        
        df
    end
    
    # 测试断言
    if nrow(tick_data) == 0
        error("❌ 数据为空")
    else
        println("  ✅ 数据非空: $(nrow(tick_data)) 条记录")
    end
    
    @info "数据加载成功" rows=nrow(tick_data) 
    println("  时间范围: $(tick_data[1, :timestamp]) 到 $(tick_data[end, :timestamp])")
    println("  价格范围: \$$(minimum(tick_data.price)) - \$$(maximum(tick_data.price))")
    
    return tick_data
end

# ============================================================================
# 步骤2：测试Tick转K线
# ============================================================================

function test_tick_to_bars(tick_data::DataFrame)
    print_separator("步骤2：测试Tick转K线")
    
    @info "聚合K线数据..."
    
    bars_1m = ticks_to_bars(tick_data, "1m")
    bars_5m = ticks_to_bars(tick_data, "5m")
    
    # 测试断言
    if nrow(bars_1m) == 0
        error("❌ 1分钟K线为空")
    else
        println("  ✅ 1分钟K线: $(nrow(bars_1m)) 根")
    end
    
    if nrow(bars_5m) == 0
        error("❌ 5分钟K线为空")
    else
        println("  ✅ 5分钟K线: $(nrow(bars_5m)) 根")
    end
    
    # 显示示例K线
    if nrow(bars_1m) > 0
        println("\n  示例K线 (1m):")
        println("    时间: $(bars_1m[1, :timestamp])")
        println("    开: \$$(round(bars_1m[1, :open], digits=2))")
        println("    高: \$$(round(bars_1m[1, :high], digits=2))")
        println("    低: \$$(round(bars_1m[1, :low], digits=2))")
        println("    收: \$$(round(bars_1m[1, :close], digits=2))")
        println("    量: $(round(bars_1m[1, :volume], digits=4))")
    end
    
    return (bars_1m, bars_5m)
end

# ============================================================================
# 步骤3：创建最小化的回测引擎（不依赖未完成的组件）
# ============================================================================

"""
最小化回测引擎（用于测试数据流）
"""
mutable struct MinimalBacktestEngine
    tick_data::DataFrame
    bar_data::Dict{String, DataFrame}
    current_symbol::Symbol
    current_time::DateTime
    
    # 统计
    ticks_processed::Int
    bars_generated::Dict{String, Int}
    
    function MinimalBacktestEngine(tick_data::DataFrame, symbol::Symbol)
        new(
            tick_data,
            Dict{String, DataFrame}(),
            symbol,
            DateTime(0),
            0,
            Dict{String, Int}()
        )
    end
end

function initialize_minimal!(engine::MinimalBacktestEngine)
    @info "初始化最小化引擎..."
    
    # 预处理K线
    engine.bar_data["1m"] = ticks_to_bars(engine.tick_data, "1m")
    engine.bar_data["5m"] = ticks_to_bars(engine.tick_data, "5m")
    
    engine.bars_generated["1m"] = 0
    engine.bars_generated["5m"] = 0
    
    @info "初始化完成" bars_1m=nrow(engine.bar_data["1m"]) bars_5m=nrow(engine.bar_data["5m"])
end

function run_minimal!(engine::MinimalBacktestEngine)
    @info "开始最小化回测..."
    
    for (idx, row) in enumerate(eachrow(engine.tick_data))
        engine.current_time = row.timestamp
        engine.ticks_processed += 1
        
        # 每1000个tick输出一次进度
        if idx % 1000 == 0
            @debug "处理进度" ticks=idx price=row.price
        end
    end
    
    @info "回测完成" total_ticks=engine.ticks_processed
end

function test_minimal_backtest(tick_data::DataFrame)
    print_separator("步骤3：测试最小化回测引擎")
    
    engine = MinimalBacktestEngine(tick_data, Symbol(TEST_SYMBOL))
    
    initialize_minimal!(engine)
    run_minimal!(engine)
    
    # 测试断言
    if engine.ticks_processed != nrow(tick_data)
        error("❌ Tick处理数量不匹配: $(engine.ticks_processed) vs $(nrow(tick_data))")
    else
        println("  ✅ 成功处理所有tick")
    end
    
    println("  ✅ 处理了 $(engine.ticks_processed) 个tick")
    println("  ✅ 生成 $(nrow(engine.bar_data["1m"])) 根1分钟K线")
    println("  ✅ 生成 $(nrow(engine.bar_data["5m"])) 根5分钟K线")
    
    return engine
end

# ============================================================================
# 步骤4：测试事件系统
# ============================================================================

function test_event_system()
    print_separator("步骤4：测试事件系统")
    
    @info "创建事件队列..."
    queue = EventQueue()
    
    # 测试1：空队列
    if !isempty(queue)
        error("❌ 新队列应该为空")
    else
        println("  ✅ 新队列为空")
    end
    
    # 创建测试事件
    tick1 = TickEvent(
        DateTime(2024, 11, 13, 0, 0, 0),
        :BTCUSDT,
        90000.0,
        0.1,
        true,
        1
    )
    
    tick2 = TickEvent(
        DateTime(2024, 11, 13, 0, 0, 1),
        :BTCUSDT,
        90001.0,
        0.15,
        false,
        2
    )
    
    # 添加事件
    put!(queue, tick2)  # 故意先加后面的
    put!(queue, tick1)
    
    # 测试2：队列长度
    if length(queue) != 2
        error("❌ 队列应该有2个事件")
    else
        println("  ✅ 队列有2个事件")
    end
    
    # 取出事件（应该按时间排序）
    event1 = get!(queue)
    if event1.timestamp != tick1.timestamp
        error("❌ 第一个事件时间不正确")
    else
        println("  ✅ 事件按时间正确排序（第一个）")
    end
    
    event2 = get!(queue)
    if event2.timestamp != tick2.timestamp
        error("❌ 第二个事件时间不正确")
    else
        println("  ✅ 事件按时间正确排序（第二个）")
    end
    
    # 测试3：队列应该空了
    if !isempty(queue)
        error("❌ 队列应该为空")
    else
        println("  ✅ 队列已清空")
    end
    
    println("  ✅ 事件系统测试通过")
end

# ============================================================================
# 步骤5：测试持仓管理器
# ============================================================================

function test_position_manager()
    print_separator("步骤5：测试持仓管理器")
    
    # 不要重复include，因为已经在测试开始时加载了
    # include("../src/execution/position_manager.jl")  # ❌ 删除这行
    
    @info "创建持仓管理器..."
    pm = PositionManager()
    
    # 创建FillEvent（不依赖events.jl中的定义）
    # 使用简单的NamedTuple代替
    fill1 = (
        timestamp = DateTime(2024, 11, 13, 0, 0, 0),
        symbol = :BTCUSDT,
        side = :BUY,
        quantity = 0.1,
        fill_price = 90000.0,
        commission = 3.6,
        order_id = "order_1",
        client_order_id = "client_1",
        grid_level = 1,
        is_hedge = false
    )
    
    on_fill!(pm, fill1)
    
    # 测试1：应该有持仓
    if !has_position(pm, :BTCUSDT, false)
        error("❌ 应该有主仓位")
    else
        println("  ✅ 成功开仓")
    end
    
    position = get_position_record(pm, :BTCUSDT, false)  # ✅ 使用新名称
    
    # 测试2：仓位大小
    if position.size != 0.1
        error("❌ 仓位大小不正确: $(position.size)")
    else
        println("  ✅ 仓位大小正确: $(position.size) BTC")
    end
    
    # 测试3：入场价
    if position.entry_price != 90000.0
        error("❌ 入场价不正确: $(position.entry_price)")
    else
        println("  ✅ 入场价正确: \$$(position.entry_price)")
    end
    
    # 更新价格
    update_price!(pm, :BTCUSDT, 91000.0, DateTime(2024, 11, 13, 0, 1, 0))
    
    position = get_position_record(pm, :BTCUSDT, false)  # ✅ 使用新名称
    expected_pnl = (91000.0 - 90000.0) * 0.1  # 100.0
    
    # 测试4：浮盈计算
    if abs(position.unrealized_pnl - expected_pnl) > 0.01
        error("❌ 浮盈计算不正确: $(position.unrealized_pnl) vs $expected_pnl")
    else
        println("  ✅ 浮盈计算正确: \$$(round(position.unrealized_pnl, digits=2))")
    end
    
    # 测试平仓
    fill2 = (
        timestamp = DateTime(2024, 11, 13, 0, 2, 0),
        symbol = :BTCUSDT,
        side = :SELL,
        quantity = 0.1,
        fill_price = 91000.0,
        commission = 3.64,
        order_id = "order_2",
        client_order_id = "client_2",
        grid_level = nothing,
        is_hedge = false
    )
    
    on_fill!(pm, fill2)
    
    # 测试5：应该没有持仓了
    if has_position(pm, :BTCUSDT, false)
        error("❌ 不应该有持仓了")
    else
        println("  ✅ 成功平仓")
    end
    
    # 测试6：交易统计
    if pm.total_trades != 1
        error("❌ 交易次数不正确: $(pm.total_trades)")
    else
        println("  ✅ 交易次数正确: $(pm.total_trades)")
    end
    
    if pm.winning_trades != 1
        error("❌ 盈利交易次数不正确: $(pm.winning_trades)")
    else
        println("  ✅ 盈利交易: $(pm.winning_trades)")
    end
    
    println("  ✅ 已实现盈亏: \$$(round(pm.total_realized_pnl, digits=2))")
    println("  ✅ 持仓管理器测试通过")
end

# ============================================================================
# 主测试函数
# ============================================================================

function run_all_tests()
    print_separator("🧪 开始完整回测系统测试")
    
    println("\n测试环境:")
    println("  Julia版本: $(VERSION)")
    println("  工作目录: $(pwd())")
    println("  测试时间: $(now())")
    
    try
        # 步骤1：加载数据
        tick_data = test_data_loading()
        
        # 步骤2：测试K线转换
        bars_1m, bars_5m = test_tick_to_bars(tick_data)
        
        # 步骤3：最小化回测
        engine = test_minimal_backtest(tick_data)
        
        # 步骤4：事件系统
        test_event_system()
        
        # 步骤5：持仓管理器
        test_position_manager()
        
        print_separator("✅ 所有测试通过！")
        
        println("\n测试总结:")
        println("  ✅ 数据加载: 通过")
        println("  ✅ Tick转K线: 通过")
        println("  ✅ 最小化回测引擎: 通过")
        println("  ✅ 事件系统: 通过")
        println("  ✅ 持仓管理器: 通过")
        
        println("\n下一步:")
        println("  1. 创建 BacktestBroker（模拟交易所）")
        println("  2. 创建 SignalGenerator（信号生成器）")
        println("  3. 创建 MainGridManager（主网格管理器）")
        println("  4. 创建 HedgeGridManager（对冲网格管理器）")
        println("  5. 集成完整的回测引擎")
        
        return true
        
    catch e
        print_separator("❌ 测试失败")
        println("\n错误信息:")
        showerror(stdout, e, catch_backtrace())
        println()
        return false
    end
end

# ============================================================================
# 运行测试
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    success = run_all_tests()
    exit(success ? 0 : 1)
end