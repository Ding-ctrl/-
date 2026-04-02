# 第9章 UPF实战编写指南

## 9.1 引言

Unified Power Format (UPF) 是 IEEE 1801 标准定义的低功耗设计意图描述语言，是连接低功耗架构设计与 EDA 工具实现的**核心桥梁**。前面章节介绍了电源域、隔离、保持、电平转换等概念，本章聚焦于如何在实际项目中**从零编写完整的 UPF 文件**，覆盖从简单单域到复杂多域 SoC 的各种场景。

掌握 UPF 实战编写能力，是从"理解低功耗理论"到"独立完成低功耗项目"的关键跨越。

## 9.2 UPF 基础语法回顾

### 9.2.1 UPF 版本演进

```
UPF版本历史:

UPF 1.0 (2007)  ── IEEE 1801-2009
  │  基础电源域、隔离、保持、电平转换
  │
UPF 2.0 (2009)  ── IEEE 1801-2013
  │  增强：供电网络建模、电源状态覆盖
  │
UPF 2.1 (2013)  ── IEEE 1801-2015
  │  增强：供电集合(Supply Set)、简化策略
  │
UPF 3.0 (2015)  ── IEEE 1801-2018
  │  增强：多级UPF、Liberty扩展、仿真语义
  │
UPF 3.1 (2018)  ── IEEE 1801-2024 (Draft)
     增强：电源状态机增强、工具互操作性
```

### 9.2.2 核心命令分类

| 类别 | 命令 | 功能描述 |
|------|------|----------|
| **电源域** | `create_power_domain` | 创建电源域，指定包含的设计元素 |
| **供电网络** | `create_supply_net` | 创建供电网络 |
| | `create_supply_port` | 创建供电端口 |
| | `create_supply_set` | 创建供电集合（UPF 2.1+） |
| | `connect_supply_net` | 连接供电网络 |
| **电源开关** | `create_power_switch` | 定义电源开关控制 |
| **隔离** | `set_isolation` | 设置隔离策略 |
| | `set_isolation_control` | 指定隔离控制信号 |
| **保持** | `set_retention` | 设置状态保持策略 |
| | `set_retention_control` | 指定保持控制信号 |
| **电平转换** | `set_level_shifter` | 设置电平转换策略 |
| **电源状态** | `create_pst` | 创建电源状态表(已废弃) |
| | `add_power_state` | 添加电源状态（UPF 2.0+） |
| **映射** | `map_isolation_cell` | 映射隔离单元到库单元 |
| | `map_retention_cell` | 映射保持单元到库单元 |
| | `map_level_shifter_cell` | 映射电平转换单元 |

## 9.3 从零编写：单电源域 UPF

### 9.3.1 最简单的 UPF 文件

即使只有一个电源域（Always-On），也需要 UPF 来描述供电意图：

```tcl
###############################################
# 文件: simple_design.upf
# 描述: 单电源域UPF示例
###############################################

# 1. 设置UPF版本（推荐）
set_scope /top

# 2. 创建顶层电源域
create_power_domain PD_TOP

# 3. 创建供电网络
create_supply_net VDD -domain PD_TOP
create_supply_net VSS -domain PD_TOP

# 4. 创建供电端口
create_supply_port VDD -direction in
create_supply_port VSS -direction in

# 5. 连接供电端口到供电网络
connect_supply_net VDD -ports {VDD}
connect_supply_net VSS -ports {VSS}

# 6. 设置主供电（primary supply）
set_domain_supply_strategy PD_TOP \
    -supply {primary -power VDD -ground VSS}
```

### 9.3.2 理解供电集合 (Supply Set)

UPF 2.1 引入了 Supply Set 的概念，简化了多电压场景下的供电关联：

```tcl
# UPF 2.1 风格：使用 Supply Set
create_supply_set SS_TOP \
    -function {power VDD} \
    -function {ground VSS}

# 创建电源域并关联 Supply Set
create_power_domain PD_TOP \
    -supply {primary SS_TOP}
```

**Supply Set vs 传统方式对比：**

| 特性 | 传统方式 (UPF 1.0) | Supply Set (UPF 2.1+) |
|------|---------------------|------------------------|
| 供电关联 | 逐个 net 关联 | 集合关联 |
| 多电压管理 | 复杂，多行命令 | 简洁，一个集合即可 |
| 可维护性 | 修改时易遗漏 | 集中管理 |
| 工具支持 | 广泛 | 主流工具均支持 |

## 9.4 双电源域 UPF 实战

### 9.4.1 场景描述

典型的双域场景：一个 Always-On 域和一个可关断域。

```
双电源域架构:

                    ┌─────────────────────────┐
     VDD_AON ──────►│      PD_AON             │
                    │  (Always-On Domain)     │
     VSS ──────────►│  ┌───────────────┐      │
                    │  │  PMU          │      │
                    │  │  Wakeup Ctrl  │      │
                    │  │  Retention Reg│      │
                    │  └───────────────┘      │
                    │         │ pwr_ctrl      │
                    │         ▼               │
                    │  ┌──────────────┐       │
                    │  │ Power Switch │       │
                    │  └──────┬───────┘       │
                    │         │ VDD_SW        │
                    ├─────────┼───────────────┤
     VDD_CORE ─────►│        ▼               │
                    │  ┌───────────────┐      │
                    │  │  PD_CORE      │      │
                    │  │  (Switchable)  │      │
                    │  │  CPU / Logic  │      │
                    │  └───────────────┘      │
                    └─────────────────────────┘
```

### 9.4.2 完整 UPF 文件

```tcl
###############################################
# 文件: dual_domain.upf
# 描述: 双电源域UPF，含关断/隔离/保持
###############################################

# ============================================
# 1. 电源域定义
# ============================================

# 顶层 Always-On 域
create_power_domain PD_AON -include_scope

# 可关断域 - 指定包含的模块
create_power_domain PD_CORE \
    -elements {u_cpu u_dma u_periph}

# ============================================
# 2. 供电网络创建
# ============================================

# Always-On 供电
create_supply_net VDD_AON -domain PD_AON
create_supply_net VSS     -domain PD_AON

# 可关断域供电（开关前后）
create_supply_net VDD_CORE    -domain PD_CORE
create_supply_net VDD_CORE_SW -domain PD_CORE

# 供电端口
create_supply_port VDD_AON  -direction in
create_supply_port VDD_CORE -direction in
create_supply_port VSS      -direction in

# 连接
connect_supply_net VDD_AON  -ports {VDD_AON}
connect_supply_net VDD_CORE -ports {VDD_CORE}
connect_supply_net VSS      -ports {VSS}

# 设置主供电
create_supply_set SS_AON \
    -function {power VDD_AON} \
    -function {ground VSS}

create_supply_set SS_CORE \
    -function {power VDD_CORE_SW} \
    -function {ground VSS}

associate_supply_set SS_AON  -handle PD_AON.primary
associate_supply_set SS_CORE -handle PD_CORE.primary

# ============================================
# 3. 电源开关
# ============================================

create_power_switch SW_CORE \
    -domain         PD_CORE \
    -input_supply_port  {vin  VDD_CORE} \
    -output_supply_port {vout VDD_CORE_SW} \
    -control_port       {ctrl pmu/core_pwr_en} \
    -on_state           {on_state vin {ctrl}} \
    -off_state          {off_state {!ctrl}}

# ============================================
# 4. 隔离策略
# ============================================

# 从可关断域输出到AON域的信号需要隔离
set_isolation iso_core_to_aon \
    -domain PD_CORE \
    -isolation_power_net VDD_AON \
    -isolation_ground_net VSS \
    -applies_to outputs \
    -clamp_value 0

set_isolation_control iso_core_to_aon \
    -domain PD_CORE \
    -isolation_signal pmu/iso_core_en \
    -isolation_sense high \
    -location parent

# ============================================
# 5. 状态保持策略
# ============================================

set_retention ret_core \
    -domain PD_CORE \
    -retention_power_net VDD_AON \
    -retention_ground_net VSS

set_retention_control ret_core \
    -domain PD_CORE \
    -save_signal    {pmu/ret_save    high} \
    -restore_signal {pmu/ret_restore high}

# ============================================
# 6. 电源状态定义
# ============================================

add_power_state PD_AON.primary \
    -state {AON_ON  -supply_expr {power == `{FULL_ON, 0.9}}}

add_power_state PD_CORE.primary \
    -state {CORE_ON  -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {CORE_OFF -supply_expr {power == `{OFF}}}

# 系统级电源状态
add_power_state PD_AON \
    -state {SYS_ACTIVE  -logic_expr {PD_AON.primary == AON_ON && \
                                      PD_CORE.primary == CORE_ON}} \
    -state {SYS_STANDBY -logic_expr {PD_AON.primary == AON_ON && \
                                      PD_CORE.primary == CORE_OFF}}
```

### 9.4.3 常见错误与调试

**错误1：隔离方向遗漏**
```tcl
# 错误：只隔离了输出，忽略了双向信号
set_isolation iso_core -domain PD_CORE -applies_to outputs

# 正确：分别处理输出和输入输出
set_isolation iso_core_out -domain PD_CORE -applies_to outputs
set_isolation iso_core_inout -domain PD_CORE -applies_to inouts
```

**错误2：保持信号时序违反**
```tcl
# save 和 restore 信号必须在供电稳定窗口内有效
# save: 必须在电源关断前 assert
# restore: 必须在电源恢复并稳定后 assert

# 典型时序：
# 1. assert isolation_enable
# 2. assert save_signal (保存寄存器)
# 3. de-assert save_signal
# 4. 关断电源开关
# ...
# 5. 打开电源开关（等待电压稳定）
# 6. assert restore_signal (恢复寄存器)
# 7. de-assert restore_signal
# 8. de-assert isolation_enable
```

**错误3：缺少供电网络连接**
```tcl
# 错误：隔离单元使用了已关断域的供电
set_isolation iso_core -domain PD_CORE \
    -isolation_power_net VDD_CORE_SW  # 错! 关断后此供电无效

# 正确：隔离单元必须使用 Always-On 供电
set_isolation iso_core -domain PD_CORE \
    -isolation_power_net VDD_AON      # 正确，AON域始终有供电
```

## 9.5 多电源域 SoC UPF 实战

### 9.5.1 典型移动 SoC 电源域架构

```
移动SoC多电源域架构:

┌──────────────────────────────────────────────────────────┐
│ PD_TOP (Always-On, 0.9V)                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐   │
│  │ PMU/PMIC │  │ RTC/WDT  │  │ Wakeup Controller   │   │
│  │ Interface│  │          │  │                      │   │
│  └──────────┘  └──────────┘  └──────────────────────┘   │
│                                                          │
│  ┌────────────────────┐  ┌────────────────────────────┐  │
│  │ PD_CPU (0.6~1.1V)  │  │ PD_GPU (0.6~1.0V)         │  │
│  │ ┌────┐ ┌────┐      │  │ ┌──────────────────────┐  │  │
│  │ │CPU0│ │CPU1│ ...   │  │ │ Shader Core Array    │  │  │
│  │ └────┘ └────┘       │  │ │ Texture Unit         │  │  │
│  │ L2 Cache            │  │ └──────────────────────┘  │  │
│  │ [DVFS + Power-Gating]│  │ [DVFS + Power-Gating]    │  │
│  └────────────────────┘  └────────────────────────────┘  │
│                                                          │
│  ┌────────────────────┐  ┌────────────────────────────┐  │
│  │ PD_MODEM (0.9V)    │  │ PD_PERIPH (0.9V)          │  │
│  │ ┌──────┐ ┌──────┐  │  │ ┌────┐ ┌────┐ ┌────────┐ │  │
│  │ │ DSP  │ │ RF   │  │  │ │UART│ │SPI │ │USB Ctrl│ │  │
│  │ └──────┘ └──────┘  │  │ └────┘ └────┘ └────────┘ │  │
│  │ [Power-Gating]     │  │ [Clock-Gating]            │  │
│  └────────────────────┘  └────────────────────────────┘  │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │ PD_MEM (0.9V / 0.6V Retention)                   │    │
│  │ DDR Controller + PHY                              │    │
│  │ [DVFS + Self-Refresh]                             │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

### 9.5.2 完整多域 UPF

```tcl
###############################################
# 文件: mobile_soc.upf
# 描述: 多电源域移动SoC UPF
# 版本: UPF 2.1
###############################################

set upf_version 2.1

# ============================================
# 1. 电源域层次定义
# ============================================

# 顶层 Always-On 域
create_power_domain PD_TOP -include_scope

# CPU 域（支持 DVFS + Power Gating）
create_power_domain PD_CPU \
    -elements {u_cpu_subsys}

# GPU 域（支持 DVFS + Power Gating）
create_power_domain PD_GPU \
    -elements {u_gpu_subsys}

# Modem 域（支持 Power Gating）
create_power_domain PD_MODEM \
    -elements {u_modem}

# 外设域（仅 Clock Gating，不关断）
create_power_domain PD_PERIPH \
    -elements {u_uart u_spi u_i2c u_usb}

# 存储控制器域
create_power_domain PD_MEM \
    -elements {u_ddr_ctrl u_ddr_phy}

# ============================================
# 2. 供电网络 - 全局
# ============================================

create_supply_net VDD_AON   -domain PD_TOP
create_supply_net VSS       -domain PD_TOP

# CPU/GPU DVFS 供电（电压可调）
create_supply_net VDD_CPU      -domain PD_CPU
create_supply_net VDD_CPU_SW   -domain PD_CPU
create_supply_net VDD_GPU      -domain PD_GPU
create_supply_net VDD_GPU_SW   -domain PD_GPU

# 固定电压域供电
create_supply_net VDD_MODEM    -domain PD_MODEM
create_supply_net VDD_MODEM_SW -domain PD_MODEM
create_supply_net VDD_PERIPH   -domain PD_PERIPH
create_supply_net VDD_MEM      -domain PD_MEM

# 端口和连接
create_supply_port VDD_AON    -direction in
create_supply_port VDD_CPU    -direction in
create_supply_port VDD_GPU    -direction in
create_supply_port VDD_MODEM  -direction in
create_supply_port VDD_PERIPH -direction in
create_supply_port VDD_MEM    -direction in
create_supply_port VSS        -direction in

connect_supply_net VDD_AON    -ports {VDD_AON}
connect_supply_net VDD_CPU    -ports {VDD_CPU}
connect_supply_net VDD_GPU    -ports {VDD_GPU}
connect_supply_net VDD_MODEM  -ports {VDD_MODEM}
connect_supply_net VDD_PERIPH -ports {VDD_PERIPH}
connect_supply_net VDD_MEM    -ports {VDD_MEM}
connect_supply_net VSS        -ports {VSS}

# ============================================
# 3. Supply Sets
# ============================================

create_supply_set SS_AON \
    -function {power VDD_AON} -function {ground VSS}
create_supply_set SS_CPU \
    -function {power VDD_CPU_SW} -function {ground VSS}
create_supply_set SS_GPU \
    -function {power VDD_GPU_SW} -function {ground VSS}
create_supply_set SS_MODEM \
    -function {power VDD_MODEM_SW} -function {ground VSS}
create_supply_set SS_PERIPH \
    -function {power VDD_PERIPH} -function {ground VSS}
create_supply_set SS_MEM \
    -function {power VDD_MEM} -function {ground VSS}

associate_supply_set SS_AON    -handle PD_TOP.primary
associate_supply_set SS_CPU    -handle PD_CPU.primary
associate_supply_set SS_GPU    -handle PD_GPU.primary
associate_supply_set SS_MODEM  -handle PD_MODEM.primary
associate_supply_set SS_PERIPH -handle PD_PERIPH.primary
associate_supply_set SS_MEM    -handle PD_MEM.primary

# ============================================
# 4. 电源开关
# ============================================

create_power_switch SW_CPU \
    -domain PD_CPU \
    -input_supply_port  {vin  VDD_CPU} \
    -output_supply_port {vout VDD_CPU_SW} \
    -control_port       {ctrl u_pmu/cpu_pwr_en} \
    -on_state           {on  vin {ctrl}} \
    -off_state          {off {!ctrl}}

create_power_switch SW_GPU \
    -domain PD_GPU \
    -input_supply_port  {vin  VDD_GPU} \
    -output_supply_port {vout VDD_GPU_SW} \
    -control_port       {ctrl u_pmu/gpu_pwr_en} \
    -on_state           {on  vin {ctrl}} \
    -off_state          {off {!ctrl}}

create_power_switch SW_MODEM \
    -domain PD_MODEM \
    -input_supply_port  {vin  VDD_MODEM} \
    -output_supply_port {vout VDD_MODEM_SW} \
    -control_port       {ctrl u_pmu/modem_pwr_en} \
    -on_state           {on  vin {ctrl}} \
    -off_state          {off {!ctrl}}

# ============================================
# 5. 隔离策略 - 每个可关断域
# ============================================

# CPU 域隔离
set_isolation iso_cpu \
    -domain PD_CPU \
    -isolation_power_net VDD_AON \
    -isolation_ground_net VSS \
    -applies_to outputs \
    -clamp_value 0

set_isolation_control iso_cpu \
    -domain PD_CPU \
    -isolation_signal u_pmu/iso_cpu_en \
    -isolation_sense high \
    -location parent

# GPU 域隔离
set_isolation iso_gpu \
    -domain PD_GPU \
    -isolation_power_net VDD_AON \
    -isolation_ground_net VSS \
    -applies_to outputs \
    -clamp_value 0

set_isolation_control iso_gpu \
    -domain PD_GPU \
    -isolation_signal u_pmu/iso_gpu_en \
    -isolation_sense high \
    -location parent

# Modem 域隔离
set_isolation iso_modem \
    -domain PD_MODEM \
    -isolation_power_net VDD_AON \
    -isolation_ground_net VSS \
    -applies_to outputs \
    -clamp_value 0

set_isolation_control iso_modem \
    -domain PD_MODEM \
    -isolation_signal u_pmu/iso_modem_en \
    -isolation_sense high \
    -location parent

# ============================================
# 6. 状态保持策略
# ============================================

# CPU 域保持（关键寄存器）
set_retention ret_cpu \
    -domain PD_CPU \
    -retention_power_net VDD_AON \
    -retention_ground_net VSS \
    -elements {u_cpu_subsys/u_cpu_core/u_arch_regs \
               u_cpu_subsys/u_cpu_core/u_pc_reg \
               u_cpu_subsys/u_cpu_core/u_sp_reg}

set_retention_control ret_cpu \
    -domain PD_CPU \
    -save_signal    {u_pmu/ret_cpu_save    posedge} \
    -restore_signal {u_pmu/ret_cpu_restore posedge}

# GPU 域保持（上下文状态）
set_retention ret_gpu \
    -domain PD_GPU \
    -retention_power_net VDD_AON \
    -retention_ground_net VSS

set_retention_control ret_gpu \
    -domain PD_GPU \
    -save_signal    {u_pmu/ret_gpu_save    posedge} \
    -restore_signal {u_pmu/ret_gpu_restore posedge}

# ============================================
# 7. 电平转换
# ============================================

# CPU域(多电压)到AON域的电平转换
set_level_shifter ls_cpu_to_aon \
    -domain PD_CPU \
    -applies_to outputs \
    -rule both \
    -location parent

# GPU域(多电压)到AON域的电平转换
set_level_shifter ls_gpu_to_aon \
    -domain PD_GPU \
    -applies_to outputs \
    -rule both \
    -location parent

# AON域到CPU域的电平转换
set_level_shifter ls_aon_to_cpu \
    -domain PD_CPU \
    -applies_to inputs \
    -rule both \
    -location self

# ============================================
# 8. 电源状态
# ============================================

# 各域电源状态
add_power_state PD_TOP.primary \
    -state {AON_ON -supply_expr {power == `{FULL_ON, 0.9}}}

add_power_state PD_CPU.primary \
    -state {CPU_FULL   -supply_expr {power == `{FULL_ON, 1.1}}} \
    -state {CPU_NOM    -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {CPU_LOW    -supply_expr {power == `{FULL_ON, 0.7}}} \
    -state {CPU_RET    -supply_expr {power == `{FULL_ON, 0.6}}} \
    -state {CPU_OFF    -supply_expr {power == `{OFF}}}

add_power_state PD_GPU.primary \
    -state {GPU_FULL   -supply_expr {power == `{FULL_ON, 1.0}}} \
    -state {GPU_NOM    -supply_expr {power == `{FULL_ON, 0.8}}} \
    -state {GPU_LOW    -supply_expr {power == `{FULL_ON, 0.65}}} \
    -state {GPU_OFF    -supply_expr {power == `{OFF}}}

add_power_state PD_MODEM.primary \
    -state {MODEM_ON   -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {MODEM_OFF  -supply_expr {power == `{OFF}}}

# 系统级电源状态
add_power_state PD_TOP \
    -state {SYS_ACTIVE \
        -logic_expr {PD_CPU.primary == CPU_NOM && \
                     PD_GPU.primary == GPU_NOM && \
                     PD_MODEM.primary == MODEM_ON}} \
    -state {SYS_IDLE \
        -logic_expr {PD_CPU.primary == CPU_LOW && \
                     PD_GPU.primary == GPU_OFF && \
                     PD_MODEM.primary == MODEM_ON}} \
    -state {SYS_STANDBY \
        -logic_expr {PD_CPU.primary == CPU_RET && \
                     PD_GPU.primary == GPU_OFF && \
                     PD_MODEM.primary == MODEM_OFF}} \
    -state {SYS_SHUTDOWN \
        -logic_expr {PD_CPU.primary == CPU_OFF && \
                     PD_GPU.primary == GPU_OFF && \
                     PD_MODEM.primary == MODEM_OFF}}
```

## 9.6 多级 UPF (Successive Refinement)

### 9.6.1 概念

多级 UPF 是 UPF 3.0 引入的关键特性，允许在设计的不同层次和不同阶段逐步细化电源意图：

```
多级UPF应用:

                设计阶段                    UPF 层次
            ┌──────────────┐
            │  架构阶段     │ ──────► Golden UPF (顶层电源意图)
            └──────┬───────┘            │
                   │                    │ 逐步细化
            ┌──────▼───────┐            ▼
            │  RTL 阶段     │ ──────► Block-Level UPF (模块UPF)
            └──────┬───────┘            │
                   │                    │ 实现细节
            ┌──────▼───────┐            ▼
            │  综合/物理实现 │ ──────► Implementation UPF (工具更新)
            └──────────────┘
```

### 9.6.2 顶层 UPF (Golden UPF)

```tcl
###############################################
# 文件: top_golden.upf
# 描述: 顶层Golden UPF（架构阶段）
###############################################

# 加载子模块UPF
load_upf cpu_subsys.upf -scope u_cpu_subsys
load_upf gpu_subsys.upf -scope u_gpu_subsys

# 顶层只定义全局策略
create_power_domain PD_TOP -include_scope

# 定义域间关系（不涉及实现细节）
create_supply_net VDD_AON -domain PD_TOP -resolve parallel
create_supply_net VSS     -domain PD_TOP -resolve parallel
```

### 9.6.3 模块级 UPF (Block-Level UPF)

```tcl
###############################################
# 文件: cpu_subsys.upf
# 描述: CPU子系统模块级UPF
###############################################

# 模块自身的电源域
create_power_domain PD_CPU_LOCAL -include_scope

# 模块看到的供电（由上层传入）
create_supply_port VDD_CPU -direction in
create_supply_port VSS     -direction in

create_supply_net VDD_CPU_INT -domain PD_CPU_LOCAL
create_supply_net VSS_INT     -domain PD_CPU_LOCAL

connect_supply_net VDD_CPU_INT -ports VDD_CPU
connect_supply_net VSS_INT     -ports VSS

# 模块内的电源策略
set_isolation iso_cpu_internal \
    -domain PD_CPU_LOCAL \
    -applies_to outputs \
    -clamp_value 0

# 模块内的保持策略
set_retention ret_cpu_internal \
    -domain PD_CPU_LOCAL \
    -retention_power_net VDD_CPU_INT
```

## 9.7 Liberty 库扩展与 UPF 映射

### 9.7.1 低功耗库单元属性

Liberty (.lib) 文件中包含低功耗相关的单元属性：

```
低功耗Liberty属性:

cell (ISO_CLAMP_LH) {
    ├── is_isolation_cell : true;           // 标记为隔离单元
    ├── isolation_cell_data_pin : "D";      // 数据输入引脚
    ├── isolation_cell_enable_pin : "EN";   // 使能引脚
    │
    ├── pg_pin (VDD) {                      // 电源引脚
    │   voltage_name : VDD;
    │   pg_type : primary_power;
    │   }
    ├── pg_pin (VDDB) {                     // 备用电源引脚
    │   voltage_name : VDDB;
    │   pg_type : backup_power;
    │   }
    │
    └── leakage_power() {                   // 漏电功耗
        value : 0.0012;
        when : "!EN";
        }
}

cell (RET_DFF) {
    ├── is_retention_cell : true;
    ├── retention_cell {
    │   save_pin : "SAVE";
    │   restore_pin : "RESTORE";
    │   retention_pin : "Q";
    │   }
    └── ...
}
```

### 9.7.2 UPF 到库单元映射

```tcl
# 映射隔离单元到具体库单元
map_isolation_cell iso_cpu \
    -domain PD_CPU \
    -lib_cells {ISO_CLAMP_LH ISO_CLAMP_HL}

# 映射保持寄存器到具体库单元
map_retention_cell ret_cpu \
    -domain PD_CPU \
    -lib_cells {RET_DFF_V2}

# 映射电平转换器
map_level_shifter_cell ls_cpu_to_aon \
    -domain PD_CPU \
    -lib_cells {LS_HL_V1 LS_LH_V1}
```

### 9.7.3 多阈值电压 (Multi-Vt) 库选择

```tcl
# 在UPF中约束Multi-Vt使用比例
# （通常通过综合工具约束而非UPF，但了解其关系很重要）

# 各Vt库的特性对比
# ┌──────────┬──────────┬──────────┬──────────┐
# │ 类型     │ 速度     │ 漏电     │ 面积     │
# ├──────────┼──────────┼──────────┼──────────┤
# │ HVT      │ 慢       │ 最低     │ 大       │
# │ SVT      │ 中等     │ 中等     │ 中等     │
# │ LVT      │ 快       │ 高       │ 中等     │
# │ ULVT     │ 最快     │ 最高     │ 小       │
# └──────────┴──────────┴──────────┴──────────┘
```

## 9.8 UPF 验证与调试

### 9.8.1 UPF 一致性检查

```tcl
# Synopsys 工具中的UPF检查命令
# Design Compiler
check_mv_design -verbose

# VCS PA-Sim
# 编译时自动检查UPF语法和一致性
vcs -upf design.upf -power_top top ...

# Cadence 工具
# Conformal Low Power (CLP)
read_power_intent -upf design.upf
check_power_intent
```

### 9.8.2 常见 UPF 检查项

| 检查项 | 描述 | 严重级别 |
|--------|------|----------|
| 供电网络未连接 | supply net 没有通过 port 连接到外部 | Error |
| 隔离策略缺失 | 跨域信号无隔离保护 | Error |
| 电平转换缺失 | 不同电压域间无电平转换 | Error |
| 保持策略未指定 | 可关断域的寄存器无保持 | Warning |
| 电源状态不可达 | 定义了不可达的状态组合 | Warning |
| 控制信号域不匹配 | 控制信号来自被关断的域 | Error |
| 重复策略定义 | 同一信号有多个冲突策略 | Error |
| 供电集合函数缺失 | Supply Set 缺少 power/ground | Error |

### 9.8.3 UPF 调试技巧

```tcl
# 1. 查看电源域信息
report_power_domain -all
report_power_domain PD_CPU -verbose

# 2. 查看供电网络
report_supply_net -all
report_supply_net VDD_CPU -connections

# 3. 查看隔离策略
report_isolation_cell -all
report_isolation -domain PD_CPU

# 4. 查看保持策略
report_retention_cell -all

# 5. 查看电源状态
report_power_state -all

# 6. 查看跨域信号
report_crossing -domain PD_CPU
```

## 9.9 UPF 编写最佳实践

### 9.9.1 命名规范

```tcl
# 推荐的UPF命名规范

# 电源域:  PD_<功能模块>
# 示例:    PD_CPU, PD_GPU, PD_AON

# 供电网络: VDD_<域名>, VSS_<域名>
# 开关后:   VDD_<域名>_SW
# 示例:     VDD_CPU, VDD_CPU_SW

# 电源开关: SW_<域名>
# 示例:     SW_CPU, SW_GPU

# 隔离策略: iso_<源域>_to_<目标域> 或 iso_<域名>
# 示例:     iso_cpu_to_aon, iso_gpu

# 保持策略: ret_<域名>
# 示例:     ret_cpu, ret_gpu

# 电平转换: ls_<源域>_to_<目标域>
# 示例:     ls_cpu_to_aon

# 供电集合: SS_<域名>
# 示例:     SS_AON, SS_CPU
```

### 9.9.2 UPF 文件组织

```
推荐的UPF文件组织结构:

project/
├── upf/
│   ├── top.upf                    # 顶层Golden UPF
│   ├── blocks/
│   │   ├── cpu_subsys.upf         # CPU子系统UPF
│   │   ├── gpu_subsys.upf         # GPU子系统UPF
│   │   ├── modem.upf              # Modem子系统UPF
│   │   └── periph.upf             # 外设子系统UPF
│   ├── impl/
│   │   ├── top_impl.upf           # 物理实现补充UPF
│   │   └── power_switch_map.upf   # 电源开关映射
│   └── verify/
│       ├── pa_sim_config.upf      # PA仿真配置
│       └── power_state_check.tcl  # 状态检查脚本
```

### 9.9.3 可维护性建议

```tcl
# 1. 使用变量参数化
set CPU_VOLTAGE_NOM 0.9
set CPU_VOLTAGE_LOW 0.7
set AON_VOLTAGE     0.9

add_power_state PD_CPU.primary \
    -state {CPU_NOM -supply_expr {power == `{FULL_ON, $CPU_VOLTAGE_NOM}}} \
    -state {CPU_LOW -supply_expr {power == `{FULL_ON, $CPU_VOLTAGE_LOW}}}

# 2. 使用过程封装重复模式
proc create_switchable_domain {name elements pwr_en iso_en} {
    create_power_domain $name -elements $elements
    
    create_supply_net VDD_${name}    -domain $name
    create_supply_net VDD_${name}_SW -domain $name
    
    create_power_switch SW_${name} \
        -domain $name \
        -input_supply_port  {vin  VDD_${name}} \
        -output_supply_port {vout VDD_${name}_SW} \
        -control_port       "ctrl $pwr_en" \
        -on_state           {on vin {ctrl}} \
        -off_state          {off {!ctrl}}
    
    set_isolation iso_${name} \
        -domain $name \
        -isolation_power_net VDD_AON \
        -applies_to outputs \
        -clamp_value 0
    
    set_isolation_control iso_${name} \
        -domain $name \
        -isolation_signal $iso_en \
        -isolation_sense high \
        -location parent
}

# 使用封装过程
create_switchable_domain PD_CPU   {u_cpu}   u_pmu/cpu_pwr_en   u_pmu/iso_cpu_en
create_switchable_domain PD_GPU   {u_gpu}   u_pmu/gpu_pwr_en   u_pmu/iso_gpu_en
create_switchable_domain PD_MODEM {u_modem} u_pmu/modem_pwr_en u_pmu/iso_modem_en
```

## 9.10 实战练习

### 练习1：基础 UPF 编写

**题目：** 为一个包含以下模块的简单 SoC 编写 UPF 文件：
- 一个 Always-On 控制器
- 一个可关断的 DSP 模块
- 要求支持状态保持

### 练习2：多电压域 UPF

**题目：** 扩展练习1，增加：
- DSP 支持两种电压模式（0.9V 高性能，0.7V 低功耗）
- 添加电平转换策略
- 定义完整的电源状态表

### 练习3：UPF 错误修复

**题目：** 找出以下 UPF 中的所有错误并修正：

```tcl
# 有错误的UPF（共有5处错误）
create_power_domain PD_TOP -include_scope
create_power_domain PD_CORE -elements {u_core}

create_supply_net VDD -domain PD_TOP
create_supply_net VSS -domain PD_TOP

# 错误1: 电源开关输出用了原始供电名称
create_power_switch SW_CORE \
    -domain PD_CORE \
    -input_supply_port  {vin VDD} \
    -output_supply_port {vout VDD} \
    -control_port {ctrl pwr_en} \
    -on_state {on vin {ctrl}}

# 错误2: 隔离用了可关断域供电
set_isolation iso_core \
    -domain PD_CORE \
    -isolation_power_net VDD \
    -applies_to inputs

# 错误3: 保持没有指定保持供电
set_retention ret_core \
    -domain PD_CORE

# 错误4: 保持控制信号来自被关断域
set_retention_control ret_core \
    -domain PD_CORE \
    -save_signal {u_core/save_sig posedge}

# 错误5: 缺少 off_state 定义
```

**参考答案要点：**
1. 电源开关输出应该是独立的 VDD_SW 网络
2. 隔离应该用 Always-On 供电且应用于 outputs
3. 保持需要指定 retention_power_net 为 Always-On 供电
4. 保持控制信号应来自 Always-On 域
5. 电源开关需要定义 off_state

## 9.11 本章小结

本章从实战角度系统介绍了 UPF 编写方法：

| 知识点 | 关键掌握 |
|--------|----------|
| UPF 基础语法 | 电源域、供电网络、Supply Set 的创建和关联 |
| 单/双域 UPF | 从最简单到含隔离/保持/开关的完整流程 |
| 多域 SoC UPF | 实际移动 SoC 的完整多域 UPF 编写 |
| 多级 UPF | Golden UPF + Block UPF 的分层策略 |
| Liberty 映射 | 库单元属性与 UPF 策略的映射关系 |
| 验证与调试 | UPF 检查项、调试命令和常见错误 |
| 最佳实践 | 命名规范、文件组织、参数化编写 |

**下一章**将介绍如何在 Synopsys/Cadence EDA 工具中使用这些 UPF 文件完成综合、物理实现和功耗签核的完整流程。
