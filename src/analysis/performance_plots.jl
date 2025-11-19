# src/analysis/performance_plots.jl

"""
性能可视化模块
"""

using Plots
using DataFrames
using Dates
using Statistics

gr()  # 使用GR后端

"""
    plot_equity_curve(engine; save_path=nothing)

绘制权益曲线
"""
function plot_equity_curve(engine; save_path=nothing)
    
    if isempty(engine.equity_curve)
        @warn "No equity data to plot"
        return nothing
    end
    
    times = [t[1] for t in engine.equity_curve]
    equities = [t[2] for t in engine.equity_curve]
    
    # 创建图表
    p = plot(
        times,
        equities,
        title = "Equity Curve",
        xlabel = "Time",
        ylabel = "Equity (\$)",
        label = "Equity",
        linewidth = 2,
        color = :blue,
        legend = :topleft,
        size = (1200, 600),
        dpi = 150,
        fmt = :png
    )
    
    # 添加初始资金水平线
    hline!(
        p,
        [engine.initial_capital],
        label = "Initial Capital",
        linestyle = :dash,
        color = :gray,
        linewidth = 1
    )
    
    # 添加盈亏标注
    final_equity = equities[end]
    total_return = final_equity - engine.initial_capital
    return_pct = (total_return / engine.initial_capital) * 100
    
    color = total_return >= 0 ? :green : :red
    
    annotate!(
        p,
        times[end],
        final_equity,
        text(
            "Final: \$$(round(final_equity, digits=2))\nReturn: $(round(return_pct, digits=2))%",
            :right,
            8,
            color
        )
    )
    
    # 保存或显示
    if !isnothing(save_path)
        savefig(p, save_path)
        @info "Equity curve saved to $save_path"
    end
    
    display(p)
    return p
end

"""
    plot_drawdown(engine; save_path=nothing)

绘制回撤曲线
"""
function plot_drawdown(engine; save_path=nothing)
    
    if isempty(engine.equity_curve)
        @warn "No equity data to plot"
        return nothing
    end
    
    times = [t[1] for t in engine.equity_curve]
    equities = [t[2] for t in engine.equity_curve]
    
    # 计算回撤
    peak = engine.initial_capital
    drawdowns = Float64[]
    
    for equity in equities
        if equity > peak
            peak = equity
        end
        
        dd_pct = ((peak - equity) / peak) * 100
        push!(drawdowns, -dd_pct)  # 负值表示回撤
    end
    
    # 创建图表
    p = plot(
        times,
        drawdowns,
        title = "Drawdown Curve",
        xlabel = "Time",
        ylabel = "Drawdown (%)",
        label = "Drawdown",
        linewidth = 2,
        color = :red,
        fill = (0, 0.3, :red),
        legend = :bottomleft,
        size = (1200, 600),
        dpi = 150,
        fmt = :png
    )
    
    # 标注最大回撤
    max_dd_idx = argmin(drawdowns)
    max_dd = drawdowns[max_dd_idx]
    
    scatter!(
        p,
        [times[max_dd_idx]],
        [max_dd],
        label = "Max DD: $(round(abs(max_dd), digits=2))%",
        markersize = 8,
        color = :darkred
    )
    
    # 保存或显示
    if !isnothing(save_path)
        savefig(p, save_path)
        @info "Drawdown curve saved to $save_path"
    end
    
    display(p)
    return p
end

"""
    plot_trades(engine; save_path=nothing)

绘制交易分布（叠加在价格上）
"""
function plot_trades(engine; save_path=nothing)
    
    if isempty(engine.trade_log)
        @warn "No trades to plot"
        return nothing
    end
    
    # 获取15分钟K线
    bars = engine.bar_data["15m"]
    
    # 绘制价格
    p = plot(
        bars.timestamp,
        bars.close,
        title = "Trades on Price Chart",
        xlabel = "Time",
        ylabel = "Price (\$)",
        label = "Close Price",
        linewidth = 1.5,
        color = :black,
        size = (1400, 700),
        dpi = 150,
        fmt = :png
    )
    
    # 分类交易
    buy_main = filter(t -> t["side"] == :BUY && !t["is_hedge"], engine.trade_log)
    sell_main = filter(t -> t["side"] == :SELL && !t["is_hedge"], engine.trade_log)
    hedge = filter(t -> t["is_hedge"], engine.trade_log)
    
    # 绘制买入
    if !isempty(buy_main)
        scatter!(
            p,
            [t["timestamp"] for t in buy_main],
            [t["price"] for t in buy_main],
            label = "Buy (Main)",
            marker = :utriangle,
            markersize = 10,
            color = :green,
            alpha = 0.8
        )
    end
    
    # 绘制卖出
    if !isempty(sell_main)
        scatter!(
            p,
            [t["timestamp"] for t in sell_main],
            [t["price"] for t in sell_main],
            label = "Sell (Main)",
            marker = :dtriangle,
            markersize = 10,
            color = :red,
            alpha = 0.8
        )
    end
    
    # 绘制对冲
    if !isempty(hedge)
        scatter!(
            p,
            [t["timestamp"] for t in hedge],
            [t["price"] for t in hedge],
            label = "Hedge",
            marker = :diamond,
            markersize = 8,
            color = :orange,
            alpha = 0.8
        )
    end
    
    # 保存或显示
    if !isnothing(save_path)
        savefig(p, save_path)
        @info "Trade chart saved to $save_path"
    end
    
    display(p)
    return p
end

"""
    plot_dashboard(engine; save_path=nothing)

综合仪表板
"""
function plot_dashboard(engine; save_path=nothing)
    
    # 创建子图
    p1 = plot_equity_curve(engine)
    p2 = plot_drawdown(engine)
    p3 = plot_trades(engine)
    
    # 组合
    dashboard = plot(
        p1, p2, p3,
        layout = (3, 1),
        size = (1400, 1800),
        dpi = 150
    )
    
    # 保存
    if !isnothing(save_path)
        savefig(dashboard, save_path)
        @info "Dashboard saved to $save_path"
    end
    
    display(dashboard)
    return dashboard
end