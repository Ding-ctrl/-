# 芯片设计 AI 优化工具包

> **Chip Design AI Optimization Toolkit** — 让 AI 帮助您完成芯片设计的关键优化任务。

---

## 🚀 我能帮您做什么？ / What can I help you with?

本工具包涵盖芯片设计流程中最核心的四个 AI 辅助优化领域：

| 功能 | 模块 | 说明 |
|------|------|------|
| **布局优化** | `placement` | 模拟退火、贪心算法最小化总线长 |
| **时序分析** | `timing` | 静态时序分析（STA），识别关键路径与时序违规 |
| **功耗优化** | `power` | 动态/静态功耗分析，提供多Vt替换、门控时钟等建议 |
| **布线优化** | `routing` | L形全局布线，生成拥塞热图并检测布线违规 |

---

## 📦 安装 / Installation

```bash
pip install -e ".[dev]"
```

## 🏃 快速开始 / Quick Start

```python
from chip_design import Netlist, Component, Net
from chip_design import PlacementOptimizer, TimingAnalyzer, PowerOptimizer, RoutingOptimizer

# 1. 创建网表 / Create a netlist
netlist = Netlist("my_chip", die_width=200.0, die_height=200.0)

# 2. 添加组件 / Add components
netlist.add_component(Component("FF1",  "FF",   width=3, height=3, delay_ps=20, power_mw=0.5))
netlist.add_component(Component("AND1", "AND2", width=2, height=2, delay_ps=10, power_mw=0.1))
netlist.add_component(Component("OR1",  "OR2",  width=2, height=2, delay_ps=12, power_mw=0.12))
netlist.add_component(Component("BUF1", "BUF",  width=1, height=1, delay_ps=5,  power_mw=0.05))

# 3. 定义连线 / Define nets
netlist.add_net(Net("N1", driver="FF1",  sinks=["AND1", "OR1"]))
netlist.add_net(Net("N2", driver="AND1", sinks=["BUF1"]))
netlist.add_net(Net("N3", driver="OR1",  sinks=["BUF1"]))

# ── 布局优化 / Placement Optimization ──────────────────────────────────
optimizer = PlacementOptimizer(netlist, seed=42)
placed = optimizer.simulated_annealing(max_iterations=20_000)
print(placed.summary())
# Netlist 'my_chip': 4 components, 3 nets, die=200x200µm, HPWL=...µm

# ── 时序分析 / Timing Analysis ──────────────────────────────────────────
analyzer = TimingAnalyzer(placed, clock_period_ps=1000.0)
timing_report = analyzer.analyze()
print(timing_report.summary())
# Timing Report [PASS ✓]
#   Clock period : 1000.0 ps
#   WNS          : 912.3 ps
#   ...

# ── 功耗优化 / Power Optimization ──────────────────────────────────────
power_opt = PowerOptimizer(placed, activity_factor=0.2)
breakdown = power_opt.analyze()
print(breakdown.summary())
# Power Breakdown:
#   Dynamic power : 0.154 mW
#   Leakage power : 0.109 mW
#   Total power   : 0.263 mW
#   Top consumers:
#     FF1                   0.115 mW
#     ...

suggestions = power_opt.suggest_optimizations()
for s in suggestions:
    print(s)

# ── 布线优化 / Routing Optimization ────────────────────────────────────
router = RoutingOptimizer(placed, grid_rows=10, grid_cols=10)
routing_report = router.route()
print(routing_report.summary())
# Routing Report:
#   Total wirelength : 234.56 µm
#   Route segments   : 5
#   Violations       : 0
#   Congestion       : CongestionMap 10x10: avg=..., max=..., hotspots=0
```

---

## 🗂️ 项目结构 / Project Structure

```
chip_design/
├── __init__.py      # 包入口 / Package entry point
├── netlist.py       # 核心数据结构：Component, Net, Netlist
├── placement.py     # 布局优化：模拟退火 / 贪心 / 网格
├── timing.py        # 静态时序分析（STA）
├── power.py         # 功耗分析与优化建议
└── routing.py       # 全局布线与拥塞分析

tests/
├── conftest.py      # 共享测试夹具
├── test_netlist.py
├── test_placement.py
├── test_timing.py
├── test_power.py
└── test_routing.py
```

---

## 🧪 运行测试 / Run Tests

```bash
pytest -v
```

---

## 📚 功能详解 / Feature Details

### 1. 布局优化 (Placement Optimization)

三种算法供选择：

- **网格布局** (`grid_placement`): 将所有组件均匀排布在网格上，适合快速初始化。
- **贪心布局** (`greedy_placement`): 逐个组件选择线长增量最小的位置。
- **模拟退火** (`simulated_annealing`): 全局搜索，同时最小化 HPWL 线长与组件重叠面积。

```python
opt = PlacementOptimizer(netlist, seed=42)

# 快速网格布局
placed_grid   = opt.grid_placement()

# 贪心布局
placed_greedy = opt.greedy_placement()

# 模拟退火（推荐）
placed_sa     = opt.simulated_annealing(
    max_iterations=50_000,
    initial_temperature=100.0,
    cooling_rate=0.9995,
    overlap_penalty=1000.0,
)
```

### 2. 时序分析 (Static Timing Analysis)

基于拓扑 DFS 遍历计算所有路径的延迟：

```python
analyzer = TimingAnalyzer(placed_netlist, clock_period_ps=1000.0)
report   = analyzer.analyze()

print(f"WNS: {report.wns_ps:.1f} ps")  # 最坏负裕量
print(f"TNS: {report.tns_ps:.1f} ps")  # 总负裕量

for path in report.critical_paths:
    print(path)
```

### 3. 功耗优化 (Power Optimization)

分析动态/静态功耗，生成三类优化建议：

| 建议类型 | 说明 |
|---------|------|
| `multi_vt` | 将时序裕量充足的单元替换为高阈值电压版本，降低漏电流 |
| `clock_gating` | 对触发器密集区域插入门控时钟，降低动态功耗 |
| `buffer_removal` | 移除仅驱动单一负载的冗余缓冲器 |

### 4. 布线优化 (Routing Optimization)

L 形双层布线 + 拥塞分析：

```python
router = RoutingOptimizer(
    placed_netlist,
    grid_rows=10,
    grid_cols=10,
    preferred_h_layer=1,   # 水平走线层
    preferred_v_layer=2,   # 垂直走线层
)
report = router.route()

# 查看拥塞热点
for row, col, density in report.congestion_map.hotspots(threshold=0.8):
    print(f"Hotspot at grid ({row},{col}): density={density:.2f}")
```

---

## 📝 License

MIT
