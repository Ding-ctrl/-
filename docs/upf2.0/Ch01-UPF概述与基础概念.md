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
- 每个房间的电源线和地线打包成一组来管理（供电集合 Supply Set）

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

### 1.4.3 供电集合 (Supply Set) — UPF 2.0 核心概念

**定义：** 将一组相关的供电网络（power、ground、以及可选的 nwell/pwell 偏置）打包成一个**逻辑集合**，作为一个整体来描述和传递供电关系。

> Supply Set 是 UPF 2.0 相对于 UPF 1.0 最重要的新增概念之一。在 UPF 1.0 中，power net 和 ground net 是分别独立管理的；UPF 2.0 引入 Supply Set 后，将它们组合为一个整体，大幅简化了层次化设计中的电源描述与 IP 复用。

**为什么需要 Supply Set？**

```
UPF 1.0 方式（分别管理 power 和 ground）：

  set_domain_supply_net PD_CPU \
      -primary_power_net  VDD_CPU \    ← 单独指定 power net
      -primary_ground_net VSS          ← 单独指定 ground net

  set_isolation iso_cpu \
      -isolation_power_net  VDD \      ← 又要单独指定 power net
      -isolation_ground_net VSS        ← 又要单独指定 ground net

  → 每条命令都要分别写 power 和 ground
  → 跨层次传递时，要分别映射每个 net
  → 容易出错，且复用困难


UPF 2.0 方式（Supply Set 统一管理）：

  create_supply_set SS_CPU \
      -function {power  VDD_CPU} \     ← power + ground 打包为一个集合
      -function {ground VSS}

  → 后续命令只需引用 SS_CPU 即可
  → 跨层次传递时，只需映射一个 Supply Set
  → 更简洁、更不容易出错
```

**芯片实体对应：**

Supply Set 本身不直接对应芯片上的新物理结构，而是对**已有供电网络的逻辑分组**。但它在先进工艺中有重要意义：

```
Supply Set 可以包含的成员：

  SS_CPU = {
      power  → VDD_CPU       ← 芯片上: CPU 域的 VDD 电源网格
      ground → VSS           ← 芯片上: CPU 域的 VSS 接地网格
      nwell  → VNW_CPU       ← 芯片上: N 阱偏置电压网络 (可选)
      pwell  → VPW_CPU       ← 芯片上: P 阱偏置电压网络 (可选)
  }

在先进 FinFET 工艺中 (7nm/5nm/3nm)：
  → nwell/pwell 偏置可用于 Forward/Reverse Body Biasing
  → 进一步降低漏电流或提升性能
  → Supply Set 是描述这种需求的标准方式
```

**Supply Set Handle（句柄）：**

UPF 2.0 还引入了 Supply Set Handle，允许通过**间接引用**访问域的供电集合：

```tcl
# 每个电源域自动有一个 .primary handle
# 引用 PD_CPU 的主供电集合，无需知道具体网络名
add_power_state PD_CPU.primary \
    -state {ON  -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {OFF -supply_expr {power == `{OFF}}}

# 在 IP 复用场景中特别有用：
# SoC 集成者不需要知道 IP 内部供电网络的具体名称
# 只需通过 handle 进行映射
```

**Supply Set 在 UPF 流程中的位置：**

```
  create_supply_port  →  create_supply_net  →  create_supply_set  →  关联到域
       (端口)               (网络)              (集合)              (使用)
  
  芯片 PAD         →  金属走线 Power Grid  →  逻辑分组           →  域的供电
```

### 1.4.4 电源状态 (Power State)

**定义：** 描述在某一时刻，各个电源网络上的电压值组合。

**芯片实体对应：**

| 状态名 | PD_CPU | PD_GPU | PD_ALWAYS_ON | 芯片功耗 |
|--------|--------|--------|-------------|---------|
| FULL_ON | 0.9V ON | 0.8V ON | 0.9V ON | 最高 |
| GPU_OFF | 0.9V ON | OFF | 0.9V ON | 中等 |
| SLEEP | OFF | OFF | 0.9V ON | 最低 |

每种状态对应芯片上不同的电源模式，由 PMU（电源管理单元）硬件控制切换。

### 1.4.5 低功耗策略单元

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
create_supply_net VDD -domain PD_TOP       ;# 全局常开电源
create_supply_net VSS -domain PD_TOP       ;# 全局地线
create_supply_net VDD_CPU -domain PD_CPU   ;# CPU 虚拟电源（由 SW_CPU 开关输出）
create_supply_net VDD_GPU -domain PD_GPU   ;# GPU 虚拟电源（由 SW_GPU 开关输出）

# ----- 4. 创建供电端口（芯片 PAD 级别）-----
create_supply_port VDD -direction in      ;# 主电源 PAD
create_supply_port VSS -direction in      ;# 主地线 PAD

# ----- 5. 连接供电网络到端口 -----
connect_supply_net VDD -ports {VDD}
connect_supply_net VSS -ports {VSS}

# ----- 6. 定义供电集合 (UPF 2.0) -----
create_supply_set SS_TOP \
    -function {power VDD} \
    -function {ground VSS}

create_supply_set SS_CPU \
    -function {power VDD_CPU} \
    -function {ground VSS}

create_supply_set SS_GPU \
    -function {power VDD_GPU} \
    -function {ground VSS}

# ----- 7. 设置域的供电 -----
set_domain_supply_net PD_TOP \
    -primary_power_net VDD \
    -primary_ground_net VSS

set_domain_supply_net PD_CPU \
    -primary_power_net VDD_CPU \
    -primary_ground_net VSS

set_domain_supply_net PD_GPU \
    -primary_power_net VDD_GPU \
    -primary_ground_net VSS

# ----- 8. 定义电源开关 -----
# CPU 域电源开关：VDD 经过 SW_CPU 切换后输出 VDD_CPU
create_power_switch SW_CPU \
    -domain PD_CPU \
    -input_supply_port {vin VDD} \
    -output_supply_port {vout VDD_CPU} \
    -control_port {ctrl cpu_pwr_en} \
    -on_state {cpu_on vin {ctrl}} \
    -ack_port {ack cpu_pwr_ack {cpu_on}}

# GPU 域电源开关：VDD 经过 SW_GPU 切换后输出 VDD_GPU
create_power_switch SW_GPU \
    -domain PD_GPU \
    -input_supply_port {vin VDD} \
    -output_supply_port {vout VDD_GPU} \
    -control_port {ctrl gpu_pwr_en} \
    -on_state {gpu_on vin {ctrl}} \
    -ack_port {ack gpu_pwr_ack {gpu_on}}

# ----- 9. 设置隔离策略 -----
set_isolation iso_cpu \
    -domain PD_CPU \
    -isolation_power_net VDD \
    -isolation_ground_net VSS \
    -clamp_value 0 \
    -applies_to outputs

set_isolation iso_gpu \
    -domain PD_GPU \
    -isolation_power_net VDD \
    -isolation_ground_net VSS \
    -clamp_value 0 \
    -applies_to outputs

# ----- 10. 设置电平转换策略 -----
set_level_shifter ls_cpu_to_top \
    -domain PD_CPU \
    -applies_to outputs \
    -rule both

set_level_shifter ls_gpu_to_top \
    -domain PD_GPU \
    -applies_to outputs \
    -rule both

# ----- 11. 设置保持策略 -----
set_retention ret_cpu \
    -domain PD_CPU \
    -retention_power_net VDD \
    -retention_ground_net VSS \
    -save_signal {save_cpu high} \
    -restore_signal {restore_cpu high}

set_retention ret_gpu \
    -domain PD_GPU \
    -retention_power_net VDD \
    -retention_ground_net VSS \
    -save_signal {save_gpu high} \
    -restore_signal {restore_gpu high}

# ----- 12. 定义电源状态 -----
add_power_state PD_TOP.primary -state {FULL_ON -supply_expr {power == `{FULL_ON, 0.9}}}
add_power_state PD_CPU.primary -state {ON  -supply_expr {power == `{FULL_ON, 0.9}}} \
                               -state {OFF -supply_expr {power == `{OFF}}}
add_power_state PD_GPU.primary -state {ON  -supply_expr {power == `{FULL_ON, 0.9}}} \
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

## 1.8 UPF 在主流 EDA 工具中的支持

### 1.8.1 综合工具

| 工具 | 厂商 | UPF 支持版本 | 主要功能 |
|------|------|-------------|---------|
| Design Compiler (DC) | Synopsys | UPF 2.0/2.1 | 功耗意图驱动综合，自动插入 ISO/LS/Retention |
| Genus | Cadence | UPF 2.0/2.1 | 低功耗综合，支持 CPF→UPF 转换 |
| Precision RTL | Siemens EDA | UPF 2.0 | FPGA/ASIC 低功耗综合 |

### 1.8.2 仿真工具

| 工具 | 厂商 | 关键能力 |
|------|------|---------|
| VCS | Synopsys | UPF-aware 仿真，Simstate 控制，Power-Aware Coverage |
| Xcelium | Cadence | 原生 UPF 支持，多域并行仿真 |
| Questa | Siemens EDA | UPF 仿真，自动检测低功耗违规 |

### 1.8.3 布局布线工具

| 工具 | 厂商 | 关键能力 |
|------|------|---------|
| ICC2 (Fusion Compiler) | Synopsys | Power Domain Floorplan，Power Grid 自动生成 |
| Innovus | Cadence | 多电压域布局，Switch Cell 自动放置 |
| Aprisa | Siemens EDA | 低功耗 P&R 支持 |

### 1.8.4 验证工具

| 工具 | 厂商 | 关键能力 |
|------|------|---------|
| VC LP | Synopsys | 低功耗形式验证，UPF vs RTL 一致性检查 |
| Conformal LP | Cadence | 低功耗等价性验证 |
| Formality | Synopsys | Power-Aware 逻辑等价性 |

### 1.8.5 分析工具

| 工具 | 厂商 | 关键能力 |
|------|------|---------|
| PrimeTime PX | Synopsys | 功耗分析，IR Drop 估算 |
| Voltus | Cadence | 动态/静态功耗分析，EM/IR 分析 |
| PowerPro | Siemens EDA | RTL 功耗优化建议 |

> **工具链典型流程：** Design Compiler (综合+UPF) → ICC2 (P&R+Power Grid) → PrimeTime PX (功耗签核) → VCS (Power-Aware 仿真) → VC LP (形式验证)

---

## 1.9 UPF 编写的常见误区与最佳实践

### 误区 1：将 UPF 视为"附加项"

```
❌ 错误做法：先完成 RTL 设计，最后补写 UPF
   → 可能发现域划分与 RTL 架构冲突
   → 跨域信号过多导致面积爆炸
   → 时序闭合困难

✅ 正确做法：架构阶段同步规划 UPF
   → 域划分影响 RTL 模块划分
   → 跨域信号在架构阶段就需要最小化
   → UPF 和 RTL 协同迭代
```

### 误区 2：过度使用 Retention

```
❌ 错误做法：对域内所有寄存器都做 Retention
   → Retention FF 面积增加 30-50%
   → 域内所有 FF 替换导致面积/功耗/时序恶化

✅ 正确做法：只对关键寄存器做 Retention
   → 状态机、配置寄存器、关键上下文
   → 数据寄存器可从内存重新加载
   → 使用 -elements 精确指定
```

### 误区 3：忽视跨域时序

```
❌ 错误做法：不考虑 ISO/LS 对时序的影响
   → 关键路径穿越域边界
   → ISO Cell + Level Shifter 引入 0.2-0.5ns 延迟
   → 时序闭合失败

✅ 正确做法：在架构阶段优化跨域路径
   → 关键路径不跨域，或预留时序裕量
   → 使用 Combo Cell 减少延迟
   → STA 约束中包含 ISO/LS 延迟
```

### 误区 4：Supply Set 与 Supply Net 混用

```
❌ 错误做法（UPF 2.0 项目中仍用 1.0 风格）：
   set_isolation iso_cpu \
       -isolation_power_net VDD \
       -isolation_ground_net VSS

✅ 正确做法（UPF 2.0 推荐）：
   set_isolation iso_cpu \
       -isolation_supply_set SS_ALWAYS_ON
   → 使用 Supply Set 统一管理，更简洁
   → 跨层次传递时只需映射一个 Supply Set
```

### 误区 5：遗漏 Always-On 逻辑

```
❌ 错误做法：可关断域内的唤醒逻辑未使用 Always-On 供电
   → 域关断后无法检测唤醒事件
   → 芯片无法从睡眠状态唤醒

✅ 正确做法：明确标识 Always-On 信号
   → 唤醒检测、中断传递等使用 Always-On Buffer
   → 在 UPF 中用 set_repeater 或 always-on cell 描述
```

---

## 1.10 本章小结

- UPF 是**描述芯片低功耗意图**的标准语言，不是设计语言
- UPF 中的每条命令最终都会映射到芯片上的**物理结构或逻辑行为**
- UPF 2.0 是当前业界主流，相比 1.0 在**可复用性和层次化**方面有重大改进
- 理解 UPF 的关键是理解命令背后的**芯片物理实现**

> **下一章：** [Ch02 - 电源域定义命令](Ch02-电源域定义命令.md)
