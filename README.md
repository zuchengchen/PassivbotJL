# PassivbotJL
julia version of Passivbot

**Trend-Following Martingale Grid Trading Bot for Binance Futures**

基于Julia的专业级加密货币交易机器人，实现趋势跟踪+马丁格尔网格策略。

---

## 🌟 特性

- ✅ **趋势跟踪**: 基于EMA和ADX的多时间框架趋势检测
- ✅ **CCI入场信号**: 使用CCI指标捕捉超买超卖机会
- ✅ **动态网格**: 基于ATR自动调整网格间距
- ✅ **马丁格尔加仓**: 智能的分层加仓系统
- ✅ **风险管理**: 多层次风险控制和止损机制
- ✅ **实时监控**: 完整的日志和监控系统
- ✅ **高性能**: Julia语言带来的极致性能

---

## 📋 系统要求

- **Julia**: 1.9 或更高版本
- **操作系统**: Linux (推荐), macOS, Windows
- **内存**: 至少 2GB RAM
- **网络**: 稳定的互联网连接

---

## 🚀 快速开始

### 1. 安装Julia

```bash
# Linux/Mac
curl -fsSL https://install.julialang.org | sh

# 或访问 https://julialang.org/downloads/

2. 克隆项目

Copy code
git clone https://github.com/yourusername/PassivbotJL.git
cd PassivbotJL

Copy code
3. 安装依赖

Copy code
julia --project=. -e 'using Pkg; Pkg.instantiate()'

Copy code
4. 配置
复制配置模板：


Copy code
cp config/strategy.yaml.example config/strategy.yaml

Copy code
编辑 config/strategy.yaml 设置你的参数。

5. 设置API密钥

Copy code
export EXCHANGE_API_KEY="your_api_key"
export EXCHANGE_API_SECRET="your_api_secret"

Copy code
6. 运行（测试网）

Copy code
julia --project=. scripts/run_bot.jl

Copy code
📊 监控
实时监控机器人状态：


Copy code
julia --project=. scripts/monitor.jl

Copy code
查看日志：


Copy code
tail -f logs/passivbot_$(date +%Y-%m-%d).log

Copy code
🧪 测试
运行完整测试套件：


Copy code
# 测试配置
julia --project=. examples/test_config.jl

# 测试市场数据
julia --project=. examples/test_market_data.jl

# 测试技术指标
julia --project=. examples/test_indicators.jl

# 测试策略
julia --project=. examples/test_strategy.jl

# 测试网格
julia --project=. examples/test_grid.jl

# 测试引擎
julia --project=. examples/test_engine.jl

Copy code
⚙️ 配置说明
核心参数

Copy code
# 交易所配置
exchange:
  name: "binance"
  testnet: true  # ⚠️ 生产环境设为 false
  
# 投资组合
portfolio:
  max_symbols: 3
  symbol_universe: 
    - BTCUSDT
    - ETHUSDT
    - BNBUSDT

# 做多配置
long:
  enabled: true
  leverage: 10
  wallet_exposure_limit: 0.05  # 最大5%资金敞口

Copy code
网格参数

Copy code
grid:
  base_spacing: 0.015  # 1.5%基础间距
  max_levels: 10       # 最多10层
  ddown_factor: 1.5    # 马丁格尔系数
  use_atr_spacing: true

Copy code
风险管理

Copy code
risk:
  stop_loss_pct: 5.0           # 5%止损
  max_hold_hours: 168          # 最多持仓7天
  liquidation_warning_distance: 20.0  # 清算警告距离20%

Copy code
完整配置说明见 docs/configuration.md

📈 策略说明
趋势检测
主趋势: EMA快慢线交叉
趋势强度: ADX指标
多时间框架确认: 主要+次要时间框架
入场逻辑
确认趋势方向和强度
等待CCI超买/超卖信号
顺势入场（做多等超卖，做空等超买）
网格管理
动态间距: 基于ATR自动调整
马丁格尔加仓: 逐层增加仓位
分批止盈: 多个止盈点位
风险控制
止损: 固定百分比止损
时间止损: 超时自动平仓
清算保护: 距离清算价过近时平仓
敞口限制: 单个交易对和总敞口限制
🛡️ 安全建议
⚠️ 先用测试网: 充分测试后再上实盘
🔑 保护API密钥: 不要提交到Git
💰 小额开始: 实盘先用小资金测试
📊 监控运行: 定期检查机器人状态
🚨 设置告警: 配置异常告警通知
📁 项目结构
PassivbotJL/
├── src/
│   ├── core/              # 核心类型和配置
│   ├── data/              # 数据和指标
│   ├── exchange/          # 交易所接口
│   ├── strategy/          # 策略逻辑
│   └── execution/         # 订单执行和引擎
├── config/                # 配置文件
├── scripts/               # 启动和工具脚本
├── examples/              # 测试示例
├── logs/                  # 日志文件
└── docs/                  # 文档
🤝 贡献
欢迎提交Issue和Pull Request！

⚖️ 免责声明
本软件仅供学习和研究使用。

⚠️ 加密货币交易存在极高风险
⚠️ 可能导致资金损失
⚠️ 使用本软件的一切后果自负
⚠️ 作者不对任何损失负责
📄 许可证
MIT License

📞 联系方式
GitHub: yourusername/PassivbotJL
Issues: 提交问题
⭐ 如果这个项目对你有帮助，请给个Star！