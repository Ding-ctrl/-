# Ch01 - UPF 概述与基础概念

## 1.1 什么是 UPF

**UPF (Unified Power Format)** 是 IEEE 1801 标准定义的一种功耗意图描述语言，基于 Tcl 语法。它的核心目的是：

> **在 RTL 设计阶段，用一套标准化的语言来描述芯片的低功耗设计意图，使得这些意图能够贯穿综合、布局布线、仿真验证等整个芯片设计流程。**

### 通俗理解

想象你设计了一栋大楼（芯片），UPF 就是这栋大楼的**电力系统设计图纸**：
- 哪些房间共用一路电源（电源域）
- 哪些区域可以断电（电源开关）
- 断电区域和有电区域之间的门怎么处理（隔离单元）
- 不同电压区域之间怎么通信（电平转换器）
- 断电后哪些数据需要保存（状态保持）

---

## 1.2 UPF 的发展历史

```
2006年 ─── UPF 1.0 (Accellera)
  │          最初由 Synopsys 主导，提交给 Accellera
  │
2007年 ─── CPF 1.0 (Cadence Power Format)
  │          Cadence 推出竞争标准
  │
2009年 ─── IEEE 1801-2009 (UPF 2.0 基础)
  │          UPF 被 IEEE 正式采纳为标准
  │
2013年 ─── IEEE 1801-2013 (UPF 2.0 / 2.1)
  │          引入 Supply Set、Power Model 等重要概念
  │
2015年 ─── IEEE 1801-2015
  │          进一步完善，增强可复用性
  │
2018年 ─── IEEE 1801-2018 (UPF 3.0)
  │          增加对先进工艺节点的支持
  │
2024年 ─── IEEE 1801-2024 (最新)
             持续演进中
```

---

## 1.3 UPF vs CPF

| 对比维度 | UPF (IEEE 1801) | CPF (Cadence) |
|----------|-----------------|---------------|
| 标准化 | IEEE 国际标准 | 行业私有标准 |
| 语法基础 | Tcl | Tcl |
| 工具支持 | Synopsys / Cadence / Mentor 均支持 | 主要 Cadence 工具 |
| 可复用性 | UPF 2.0 引入 Power Model，支持 IP 复用 | 较弱 |
| 市场趋势 | **业界主流**，大多数项目已转向 UPF | 逐渐被 UPF 取代 |
| 仿真支持 | 原生 Simstate 支持 | 需要额外适配 |

> **结论：UPF 2.0 是当前业界低功耗设计的事实标准。**

---

## 1.4 UPF 核心概念模型

### 1.4.1 电源域 (Power Domain)

**定义：** 一组共享相同电源供电策略的逻辑单元集合。

**芯片实体对应：**
```
┌─────────────────────────────────────────────────┐
│ 芯片（Die）                                       │
│  ┌──────────────┐  ┌──────────────┐              │
│  │ 电源域 PD_CPU │  │ 电源域 PD_GPU │              │
│  │ VDD=0.9V     │  │ VDD=0.8V     │              │
│  │              │  │              │              │
│  │  CPU Core    │  │  GPU Core    │              │
│  │  L1 Cache    │  │  Shader      │              │
│  └──────────────┘  └──────────────┘              │
│  ┌─────────────────────────────────────────────┐ │
│  │ 电源域 PD_ALWAYS_ON (常开域)                   │ │
│  │ VDD=0.9V (always on)                         │ │
│  │  PMU │ Interrupt Ctrl │ RTC │ WakeUp Logic   │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

在实际芯片上，每个电源域对应一个**电压岛 (Voltage Island)**：
- 拥有独立的电源网格 (Power Grid / Power Mesh)
- 可以独立控制电压和开关状态
- 域边界需要特殊单元（隔离、电平转换）处理信号

### 1.4.2 供电网络 (Supply Network)

**定义：** 描述电源从 PAD（封装引脚）到各个电源域的分配路径。

**芯片实体对应：**
```
封装引脚(PAD)
    │
    ▼
电源 Bump / Bond Wire
    │
    ▼
顶层金属 Power Ring
    │
    ├──── Power Strap (垂直/水平金属条)
    │         │
    │         ▼
    │    Power Mesh (电源网格)
    │         │
    │         ▼
    │    Standard Cell VDD/VSS Rail
    │
    └──── 通过 Power Switch ──→ 可关断域的 Virtual VDD
```

### 1.4.3 电源状态 (Power State)

**定义：** 描述在某一时刻，各个电源网络上的电压值组合。

**芯片实体对应：**

| 状态名 | PD_CPU | PD_GPU | PD_ALWAYS_ON | 芯片功耗 |
|--------|--------|--------|-------------|---------|
| FULL_ON | 0.9V ON | 0.8V ON | 0.9V ON | 最高 |
| GPU_OFF | 0.9V ON | OFF | 0.9V ON | 中等 |
| SLEEP | OFF | OFF | 0.9V ON | 最低 |

每种状态对应芯片上不同的电源模式，由 PMU（电源管理单元）硬件控制切换。

### 1.4.4 低功耗策略单元

在 UPF 中描述的各种低功耗策略，最终会变成芯片上的**物理单元**：

| UPF 策略 | 芯片上的物理单元 | 位置 |
|----------|----------------|------|
| Power Switch | MTCMOS 开关管 (Header/Footer) | 电源域内部，连接 VDD 到 Virtual VDD |
| Isolation | 隔离钳位单元 (Clamp Cell) | 电源域边界，输出端口处 |
| Level Shifter | 电平转换单元 | 跨电压域信号路径上 |
| Retention | 保持触发器 (Retention FF) | 替换域内需保持状态的寄存器 |
| Always-On Buffer | 常开缓冲器 | 可关断域内的常开信号路径 |

---

## 1.5 UPF 在芯片设计流程中的角色

```
          ┌──────────────────────────────────────────────┐
          │              系统架构阶段                       │
          │  定义电源域划分、电压规划、功耗预算               │
          └───────────────────┬──────────────────────────┘
                              │
                              ▼
          ┌──────────────────────────────────────────────┐
          │              RTL 设计阶段                       │
          │  编写 UPF 文件 ←──── 描述低功耗意图              │
          └───────────────────┬──────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
     ┌──────────────────┐   ┌──────────────────────┐
     │   功能仿真         │   │   逻辑综合              │
     │   UPF-aware Sim   │   │   Power-Aware Synth   │
     │   (VCS/Xcelium)   │   │   (DC/Genus)          │
     │                    │   │                        │
     │ • 验证隔离逻辑      │   │ • 插入 Isolation Cell  │
     │ • 验证 Retention    │   │ • 插入 Level Shifter   │
     │ • 验证电源状态切换  │   │ • 替换 Retention FF     │
     └────────┬───────────┘   │ • 插入 Power Switch    │
              │               └──────────┬─────────────┘
              │                          │
              │                          ▼
              │          ┌──────────────────────────────┐
              │          │      布局布线 (P&R)             │
              │          │      (ICC2/Innovus)            │
              │          │                                │
              │          │ • Power Domain Floorplan       │
              │          │ • Power Grid/Mesh 实现          │
              │          │ • Switch Cell 排列              │
              │          │ • 特殊单元放置与连接              │
              │          └──────────┬───────────────────┘
              │                     │
              │                     ▼
              │          ┌──────────────────────────────┐
              │          │    签核验证 (Signoff)           │
              │          │                                │
              ├─────────→│ • 低功耗 DRC/LVS 检查          │
              │          │ • IR Drop 分析                  │
              │          │ • Power-Aware STA              │
              │          │ • UPF Formal Verification      │
              │          └──────────────────────────────┘
              │
              ▼
     ┌──────────────────┐
     │   门级仿真         │
     │   Gate-Level Sim  │
     │   + UPF           │
     └──────────────────┘
```

---

## 1.6 UPF 文件的基本结构

一个典型的 UPF 文件结构如下：

```tcl
# ============================================
# UPF 文件：top_power_intent.upf
# 适用于：SoC 顶层
# ============================================

# ----- 1. UPF 版本声明 -----
upf_version 2.0

# ----- 2. 创建电源域 -----
create_power_domain PD_TOP -include_scope
create_power_domain PD_CPU -elements {u_cpu}
create_power_domain PD_GPU -elements {u_gpu}

# ----- 3. 定义供电网络 -----
create_supply_net VDD -domain PD_TOP
create_supply_net VSS -domain PD_TOP
create_supply_net VDD_CPU -domain PD_CPU
create_supply_net VDD_GPU -domain PD_GPU

# ----- 4. 创建供电端口 -----
create_supply_port VDD -direction in
create_supply_port VSS -direction in

# ----- 5. 连接供电网络 -----
connect_supply_net VDD -ports {VDD}
connect_supply_net VSS -ports {VSS}

# ----- 6. 设置域的供电 -----
set_domain_supply_net PD_TOP \
    -primary_power_net VDD \
    -primary_ground_net VSS

set_domain_supply_net PD_CPU \
    -primary_power_net VDD_CPU \
    -primary_ground_net VSS

# ----- 7. 定义电源开关 -----
create_power_switch SW_CPU \
    -domain PD_CPU \
    -input_supply_port {vin VDD} \
    -output_supply_port {vout VDD_CPU} \
    -control_port {cpu_pwr_en} \
    -on_state {on_state vin {cpu_pwr_en}}

# ----- 8. 设置隔离策略 -----
set_isolation iso_cpu \
    -domain PD_CPU \
    -isolation_power_net VDD \
    -isolation_ground_net VSS \
    -clamp_value 0 \
    -applies_to outputs

# ----- 9. 设置电平转换策略 -----
set_level_shifter ls_cpu_to_gpu \
    -domain PD_CPU \
    -applies_to outputs \
    -rule both

# ----- 10. 设置保持策略 -----
set_retention ret_cpu \
    -domain PD_CPU \
    -retention_power_net VDD \
    -retention_ground_net VSS \
    -save_signal {save_cpu high} \
    -restore_signal {restore_cpu high}

# ----- 11. 定义电源状态 -----
add_power_state PD_TOP.primary -state {FULL_ON -supply_expr {power == `{FULL_ON, 0.9}}}
add_power_state PD_CPU.primary -state {ON -supply_expr {power == `{FULL_ON, 0.9}}} \
                               -state {OFF -supply_expr {power == `{OFF}}}
```

---

## 1.7 UPF 2.0 相对于 UPF 1.0 的主要改进

| 特性 | UPF 1.0 | UPF 2.0 |
|------|---------|---------|
| Supply Set | ❌ | ✅ 将 power/ground 组合为集合 |
| Power Model | ❌ | ✅ 可复用的低功耗意图封装 |
| Simstate | 有限 | ✅ 增强仿真状态控制 |
| 层次化支持 | 基础 | ✅ 大幅增强，支持 IP 集成 |
| Supply Set Handle | ❌ | ✅ 简化跨层次供电描述 |
| Repeater | ❌ | ✅ 跨域信号中继 |
| 端口属性 | 基础 | ✅ `set_port_attributes` 增强 |
| 策略合并 | ❌ | ✅ 支持策略的自动推断与合并 |

---

## 1.8 本章小结

- UPF 是**描述芯片低功耗意图**的标准语言，不是设计语言
- UPF 中的每条命令最终都会映射到芯片上的**物理结构或逻辑行为**
- UPF 2.0 是当前业界主流，相比 1.0 在**可复用性和层次化**方面有重大改进
- 理解 UPF 的关键是理解命令背后的**芯片物理实现**

> **下一章：** [Ch02 - 电源域定义命令](Ch02-电源域定义命令.md)
