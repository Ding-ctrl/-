# UPF 2.0 (IEEE 1801) 完全参考手册

> **Unified Power Format 2.0 —— 每个命令的定义与对实际芯片的作用**

---

## 📖 文档说明

本文档是一份面向芯片设计工程师的 **UPF 2.0 实用参考手册**，旨在：

1. **系统梳理** UPF 2.0 (IEEE 1801-2015/2018) 中每一条核心命令的语法与语义
2. **对照实际芯片**，解释每条命令在硅片上到底会产生什么样的物理结构或逻辑行为
3. **提供实战案例**，帮助读者从"能写 UPF"到"理解 UPF 背后的芯片"

---

## 📚 章节目录

| 章节 | 标题 | 核心内容 |
|------|------|----------|
| [Ch01](Ch01-UPF概述与基础概念.md) | UPF 概述与基础概念 | UPF 的历史、与 CPF 的区别、核心概念模型 |
| [Ch02](Ch02-电源域定义命令.md) | 电源域定义命令 | `create_power_domain`、域的层次结构、对芯片的影响 |
| [Ch03](Ch03-供电网络命令.md) | 供电网络命令 | `create_supply_port`、`create_supply_net`、`create_supply_set`、`connect_supply_net` |
| [Ch04](Ch04-电源开关命令.md) | 电源开关命令 | `create_power_switch`、`map_power_switch`、Header/Footer Switch |
| [Ch05](Ch05-隔离策略命令.md) | 隔离策略命令 | `set_isolation`、`use_interface_cell`、隔离单元原理 |
| [Ch06](Ch06-电平转换命令.md) | 电平转换命令 | `set_level_shifter`、HL/LH 转换、对芯片时序的影响 |
| [Ch07](Ch07-状态保持命令.md) | 状态保持命令 | `set_retention`、Balloon Latch、Always-On 逻辑 |
| [Ch08](Ch08-电源状态与状态表.md) | 电源状态与状态表 | `add_power_state`、`create_pst`、状态转换约束 |
| [Ch09](Ch09-UPF2.0新增特性与高级命令.md) | UPF 2.0 新增特性与高级命令 | Supply Set、Repeater、Simstate、`begin_power_model` |
| [Ch10](Ch10-完整SoC低功耗设计实战.md) | 完整 SoC 低功耗设计实战案例 | 多核 SoC 全流程 UPF 编写与验证 |

---

## 🔑 UPF 2.0 命令速查表

### 电源域与供电网络
| 命令 | 芯片上的作用 |
|------|------------|
| `create_power_domain` | 划分可独立控制电源的区域 → 芯片上的电压岛 |
| `create_supply_port` | 定义电源接口引脚 → 芯片 PAD 或 bump 上的电源引脚 |
| `create_supply_net` | 定义电源网络 → 芯片上的 VDD/VSS 金属走线 |
| `create_supply_set` | 将 power/ground 打包为一组 → 简化供电关系描述 |
| `connect_supply_net` | 连接供电网络 → 电源网格(Power Grid)的拓扑连接 |
| `set_domain_supply_net` | 为域指定供电 → 确定哪块芯片区域接哪路电源 |

### 低功耗策略
| 命令 | 芯片上的作用 |
|------|------------|
| `create_power_switch` | 定义电源开关 → MTCMOS Header/Footer 开关管 |
| `set_isolation` | 定义隔离策略 → 域边界插入隔离单元(Clamp Cell) |
| `set_level_shifter` | 定义电平转换 → 跨电压域信号路径插入 Level Shifter |
| `set_retention` | 定义保持策略 → 寄存器替换为带 Balloon Latch 的 Retention FF |
| `map_power_switch` | 映射开关到库单元 → 指定使用哪个工艺库中的 Switch Cell |

### 电源状态管理
| 命令 | 芯片上的作用 |
|------|------------|
| `add_power_state` | 定义供电状态 → 描述各电源网络的电压值组合 |
| `create_pst` | 创建状态表 → 定义芯片合法的电源模式组合 |

### UPF 2.0 高级命令
| 命令 | 芯片上的作用 |
|------|------------|
| `begin_power_model` / `end_power_model` | 定义可复用电源模型 → IP 核的低功耗封装 |
| `apply_power_model` | 应用电源模型 → 将 IP 的低功耗意图实例化 |
| `set_simstate_behavior` | 定义仿真行为 → 控制关断域在仿真中的信号表现 |
| `set_port_attributes` | 设置端口属性 → 描述 IP 端口的电源相关特性 |
| `set_repeater` | 定义 Repeater → 跨域信号路径上的缓冲/中继单元 |

---

## 🎯 适用读者

- 芯片前端设计工程师（RTL → 低功耗意图描述）
- 芯片后端实现工程师（综合 → Place & Route → 低功耗验证）
- 低功耗验证工程师（UPF-aware 仿真 / Formal Verification）
- 芯片架构师（系统级电源架构规划）

---

## 📌 参考标准

- **IEEE 1801-2009** (UPF 1.0)
- **IEEE 1801-2013** (UPF 2.0)
- **IEEE 1801-2015** (UPF 2.1)
- **IEEE 1801-2018** (UPF 3.0 / UPF 3.1)
- Synopsys / Cadence / Mentor 工具手册

---

*本文档持续更新，欢迎提出改进建议。*
