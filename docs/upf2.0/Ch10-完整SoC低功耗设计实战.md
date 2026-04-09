# Ch10 - 完整 SoC 低功耗设计实战案例

## 概述

本章通过一个**完整的多核移动 SoC** 案例，将前面所有章节的 UPF 命令串联起来，展示从架构规划到 UPF 编写的完整流程。

---

## 10.1 设计目标

### SoC 架构

```
┌──────────────────────────────────────────────────────────┐
│                     移动 SoC "MobileStar"                  │
│                                                           │
│  ┌───────────────────────────────┐  ┌──────────────────┐ │
│  │      CPU Subsystem            │  │   GPU Subsystem   │ │
│  │  ┌──────┐  ┌──────┐          │  │  ┌────────────┐  │ │
│  │  │Core0 │  │Core1 │          │  │  │  Shader    │  │ │
│  │  │ARM A55│  │ARM A55│         │  │  │  Array     │  │ │
│  │  └──────┘  └──────┘          │  │  └────────────┘  │ │
│  │  ┌──────┐  ┌──────┐          │  │  ┌────────────┐  │ │
│  │  │Core2 │  │Core3 │          │  │  │  Texture   │  │ │
│  │  │ARM A76│  │ARM A76│         │  │  │  Unit      │  │ │
│  │  └──────┘  └──────┘          │  │  └────────────┘  │ │
│  │  ┌────────────────────┐      │  │                   │ │
│  │  │    L2 Cache (2MB)  │      │  │                   │ │
│  │  └────────────────────┘      │  └──────────────────┘ │
│  └───────────────────────────────┘                       │
│                                                           │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  NPU (AI)    │  │  DDR Ctrl    │  │  Peripherals  │  │
│  │  Neural Proc │  │  + PHY       │  │  UART/SPI/I2C │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Always-On Domain                                    │ │
│  │  PMU | GIC | Timer | RTC | WakeUp | Debug            │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  电源引脚: VDD(0.9V) | VDD_GPU(0.8V) | VDDQ(1.1V) | VSS │
└──────────────────────────────────────────────────────────┘
```

### 功耗模式规划

| 模式 | CPU | GPU | NPU | DDR | 外设 | 常开域 | 典型场景 |
|------|-----|-----|-----|-----|------|--------|---------|
| **FULL** | 4核@0.9V | ON@0.8V | ON | ON | ON | ON | 游戏/AI |
| **PERF** | 2大核@0.9V | ON@0.8V | OFF | ON | ON | ON | 日常使用 |
| **NORMAL** | 2小核@0.75V | OFF | OFF | ON | 部分 | ON | 后台运行 |
| **IDLE** | 1小核@0.75V | OFF | OFF | Self-Refresh | 部分 | ON | 轻负载 |
| **SLEEP** | Retention | OFF | OFF | Self-Refresh | OFF | ON | 深度睡眠 |
| **OFF** | OFF | OFF | OFF | OFF | OFF | ON | 关机(RTC) |

---

## 10.2 完整 UPF 文件

### 10.2.1 顶层 UPF

```tcl
# ================================================================
# File: mobile_star_top.upf
# Description: MobileStar SoC Top-Level UPF
# Standard: IEEE 1801-2013 (UPF 2.0)
# ================================================================

upf_version 2.0

# ================================================================
# Section 1: 电源域定义
# ================================================================

# 顶层域（常开域）
# 芯片上: 包含 PMU, GIC, Timer, RTC, WakeUp Logic
# 这些逻辑在任何功耗模式下都不会断电
create_power_domain PD_TOP -include_scope

# CPU 子系统域
create_power_domain PD_CPU -elements {u_cpu_subsys}

# CPU 各核心独立域（支持大小核独立关断）
create_power_domain PD_CORE0 -elements {u_cpu_subsys/u_core0}  ;# A55 小核
create_power_domain PD_CORE1 -elements {u_cpu_subsys/u_core1}  ;# A55 小核
create_power_domain PD_CORE2 -elements {u_cpu_subsys/u_core2}  ;# A76 大核
create_power_domain PD_CORE3 -elements {u_cpu_subsys/u_core3}  ;# A76 大核

# GPU 域
create_power_domain PD_GPU -elements {u_gpu}

# NPU 域
create_power_domain PD_NPU -elements {u_npu}

# DDR 控制器域（通常不关断，但支持低功耗模式）
create_power_domain PD_DDR -elements {u_ddr_ctrl}

# 外设域
create_power_domain PD_PERI -elements {u_peripherals}

# ================================================================
# Section 2: 供电端口与网络
# ================================================================

# --- 顶层电源端口（芯片 PAD）---
create_supply_port VDD   -direction in   ;# 主电源 0.9V
create_supply_port VSS   -direction in   ;# 主地线
create_supply_port VDDQ  -direction in   ;# DDR I/O 电源 1.1V

# --- 全局供电网络 ---
create_supply_net VDD   -domain PD_TOP
create_supply_net VSS   -domain PD_TOP
create_supply_net VDDQ  -domain PD_TOP

# --- 可切换供电网络 ---
create_supply_net VDD_SW_CORE0 -domain PD_CORE0    ;# Core0 Virtual VDD
create_supply_net VDD_SW_CORE1 -domain PD_CORE1    ;# Core1 Virtual VDD
create_supply_net VDD_SW_CORE2 -domain PD_CORE2    ;# Core2 Virtual VDD
create_supply_net VDD_SW_CORE3 -domain PD_CORE3    ;# Core3 Virtual VDD
create_supply_net VDD_SW_GPU   -domain PD_GPU      ;# GPU Virtual VDD
create_supply_net VDD_SW_NPU   -domain PD_NPU      ;# NPU Virtual VDD
create_supply_net VDD_SW_PERI  -domain PD_PERI     ;# 外设 Virtual VDD

# --- 连接端口到网络 ---
connect_supply_net VDD  -ports {VDD}
connect_supply_net VSS  -ports {VSS}
connect_supply_net VDDQ -ports {VDDQ}

# --- 定义供电集合 (UPF 2.0 Supply Set) ---
# Supply Set 将 power/ground 网络逻辑分组，便于复用与层次化集成
create_supply_set SS_TOP \
    -function {power VDD} \
    -function {ground VSS}

create_supply_set SS_CPU \
    -function {power VDD} \
    -function {ground VSS}

create_supply_set SS_CORE0 \
    -function {power VDD_SW_CORE0} \
    -function {ground VSS}

create_supply_set SS_CORE1 \
    -function {power VDD_SW_CORE1} \
    -function {ground VSS}

create_supply_set SS_CORE2 \
    -function {power VDD_SW_CORE2} \
    -function {ground VSS}

create_supply_set SS_CORE3 \
    -function {power VDD_SW_CORE3} \
    -function {ground VSS}

create_supply_set SS_GPU \
    -function {power VDD_SW_GPU} \
    -function {ground VSS}

create_supply_set SS_NPU \
    -function {power VDD_SW_NPU} \
    -function {ground VSS}

create_supply_set SS_DDR \
    -function {power VDD} \
    -function {ground VSS}

create_supply_set SS_DDR_IO \
    -function {power VDDQ} \
    -function {ground VSS}

create_supply_set SS_PERI \
    -function {power VDD_SW_PERI} \
    -function {ground VSS}

# 常开域的供电集合（用于隔离和 Retention 单元供电）
create_supply_set SS_ALWAYS_ON \
    -function {power VDD} \
    -function {ground VSS}

# --- 为各域关联供电集合 ---
set_domain_supply_net PD_TOP \
    -primary_power_net VDD \
    -primary_ground_net VSS

set_domain_supply_net PD_CPU \
    -primary_power_net VDD \
    -primary_ground_net VSS

set_domain_supply_net PD_CORE0 \
    -primary_power_net VDD_SW_CORE0 \
    -primary_ground_net VSS

set_domain_supply_net PD_CORE1 \
    -primary_power_net VDD_SW_CORE1 \
    -primary_ground_net VSS

set_domain_supply_net PD_CORE2 \
    -primary_power_net VDD_SW_CORE2 \
    -primary_ground_net VSS

set_domain_supply_net PD_CORE3 \
    -primary_power_net VDD_SW_CORE3 \
    -primary_ground_net VSS

set_domain_supply_net PD_GPU \
    -primary_power_net VDD_SW_GPU \
    -primary_ground_net VSS

set_domain_supply_net PD_NPU \
    -primary_power_net VDD_SW_NPU \
    -primary_ground_net VSS

set_domain_supply_net PD_DDR \
    -primary_power_net VDD \
    -primary_ground_net VSS

set_domain_supply_net PD_PERI \
    -primary_power_net VDD_SW_PERI \
    -primary_ground_net VSS

# ================================================================
# Section 3: 电源开关
# ================================================================

# --- CPU 各核心的电源开关 ---
create_power_switch SW_CORE0 \
    -domain PD_CORE0 \
    -input_supply_port  {vin  VDD} \
    -output_supply_port {vout VDD_SW_CORE0} \
    -control_port       {ctrl pmu_core0_pwr_en} \
    -on_state           {on vin {ctrl}} \
    -ack_port           {ack pmu_core0_pwr_ack {on}}

create_power_switch SW_CORE1 \
    -domain PD_CORE1 \
    -input_supply_port  {vin  VDD} \
    -output_supply_port {vout VDD_SW_CORE1} \
    -control_port       {ctrl pmu_core1_pwr_en} \
    -on_state           {on vin {ctrl}} \
    -ack_port           {ack pmu_core1_pwr_ack {on}}

create_power_switch SW_CORE2 \
    -domain PD_CORE2 \
    -input_supply_port  {vin  VDD} \
    -output_supply_port {vout VDD_SW_CORE2} \
    -control_port       {ctrl pmu_core2_pwr_en} \
    -on_state           {on vin {ctrl}} \
    -ack_port           {ack pmu_core2_pwr_ack {on}}

create_power_switch SW_CORE3 \
    -domain PD_CORE3 \
    -input_supply_port  {vin  VDD} \
    -output_supply_port {vout VDD_SW_CORE3} \
    -control_port       {ctrl pmu_core3_pwr_en} \
    -on_state           {on vin {ctrl}} \
    -ack_port           {ack pmu_core3_pwr_ack {on}}

# --- GPU 电源开关 ---
create_power_switch SW_GPU \
    -domain PD_GPU \
    -input_supply_port  {vin  VDD} \
    -output_supply_port {vout VDD_SW_GPU} \
    -control_port       {ctrl pmu_gpu_pwr_en} \
    -on_state           {on vin {ctrl}} \
    -ack_port           {ack pmu_gpu_pwr_ack {on}}

# --- NPU 电源开关 ---
create_power_switch SW_NPU \
    -domain PD_NPU \
    -input_supply_port  {vin  VDD} \
    -output_supply_port {vout VDD_SW_NPU} \
    -control_port       {ctrl pmu_npu_pwr_en} \
    -on_state           {on vin {ctrl}} \
    -ack_port           {ack pmu_npu_pwr_ack {on}}

# --- 外设电源开关 ---
create_power_switch SW_PERI \
    -domain PD_PERI \
    -input_supply_port  {vin  VDD} \
    -output_supply_port {vout VDD_SW_PERI} \
    -control_port       {ctrl pmu_peri_pwr_en} \
    -on_state           {on vin {ctrl}} \
    -ack_port           {ack pmu_peri_pwr_ack {on}}

# ================================================================
# Section 4: 隔离策略
# ================================================================

# --- CPU 核心隔离 ---
set_isolation iso_core0 \
    -domain PD_CORE0 \
    -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 \
    -applies_to outputs

set_isolation iso_core1 \
    -domain PD_CORE1 \
    -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 \
    -applies_to outputs

set_isolation iso_core2 \
    -domain PD_CORE2 \
    -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 \
    -applies_to outputs

set_isolation iso_core3 \
    -domain PD_CORE3 \
    -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 \
    -applies_to outputs

# --- GPU 隔离 ---
set_isolation iso_gpu \
    -domain PD_GPU \
    -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 \
    -applies_to outputs

# --- NPU 隔离 ---
set_isolation iso_npu \
    -domain PD_NPU \
    -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 \
    -applies_to outputs

# --- 外设隔离 ---
set_isolation iso_peri \
    -domain PD_PERI \
    -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 \
    -applies_to outputs

# --- AXI 总线信号特殊处理（锁存最后值避免协议违规）---
set_isolation iso_core0_axi \
    -domain PD_CORE0 \
    -elements {u_cpu_subsys/u_core0/axi_*} \
    -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value latch \
    -applies_to outputs

# ================================================================
# Section 5: 电平转换
# ================================================================

# --- GPU 域 (0.8V) 与 CPU/TOP 域 (0.9V) 之间 ---
set_level_shifter ls_gpu_out \
    -domain PD_GPU \
    -applies_to outputs \
    -rule low_to_high

set_level_shifter ls_gpu_in \
    -domain PD_GPU \
    -applies_to inputs \
    -rule high_to_low

# ================================================================
# Section 6: 状态保持
# ================================================================

# --- CPU 核心寄存器保持 ---
set_retention ret_core0 \
    -domain PD_CORE0 \
    -retention_supply_set SS_ALWAYS_ON \
    -save_signal    {pmu_core0_save    high} \
    -restore_signal {pmu_core0_restore high}

set_retention ret_core1 \
    -domain PD_CORE1 \
    -retention_supply_set SS_ALWAYS_ON \
    -save_signal    {pmu_core1_save    high} \
    -restore_signal {pmu_core1_restore high}

set_retention ret_core2 \
    -domain PD_CORE2 \
    -retention_supply_set SS_ALWAYS_ON \
    -save_signal    {pmu_core2_save    high} \
    -restore_signal {pmu_core2_restore high}

set_retention ret_core3 \
    -domain PD_CORE3 \
    -retention_supply_set SS_ALWAYS_ON \
    -save_signal    {pmu_core3_save    high} \
    -restore_signal {pmu_core3_restore high}

# --- GPU 不做 Retention（关断后完全重新初始化）---
# GPU 的状态可以从显存重新加载，不需要 Retention

# --- NPU 不做 Retention（模型权重存在 DDR 中）---

# ================================================================
# Section 7: 电源状态定义
# ================================================================

# --- 各供电集合的电源状态 (基于 Supply Set) ---
add_power_state SS_TOP -state {ON -supply_expr {power == `{FULL_ON, 0.9}}}

add_power_state SS_CORE0 \
    -state {ON_HIGH -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {ON_LOW  -supply_expr {power == `{FULL_ON, 0.75}}} \
    -state {OFF     -supply_expr {power == `{OFF}}}

add_power_state SS_CORE1 \
    -state {ON_HIGH -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {ON_LOW  -supply_expr {power == `{FULL_ON, 0.75}}} \
    -state {OFF     -supply_expr {power == `{OFF}}}

add_power_state SS_CORE2 \
    -state {ON_HIGH -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {OFF     -supply_expr {power == `{OFF}}}

add_power_state SS_CORE3 \
    -state {ON_HIGH -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {OFF     -supply_expr {power == `{OFF}}}

add_power_state SS_GPU \
    -state {ON  -supply_expr {power == `{FULL_ON, 0.8}}} \
    -state {OFF -supply_expr {power == `{OFF}}}

add_power_state SS_NPU \
    -state {ON  -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {OFF -supply_expr {power == `{OFF}}}

add_power_state SS_PERI \
    -state {ON  -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {OFF -supply_expr {power == `{OFF}}}

# ================================================================
# Section 8: 仿真行为
# ================================================================

set_simstate_behavior CORRUPT -domain PD_CORE0
set_simstate_behavior CORRUPT -domain PD_CORE1
set_simstate_behavior CORRUPT -domain PD_CORE2
set_simstate_behavior CORRUPT -domain PD_CORE3
set_simstate_behavior CORRUPT -domain PD_GPU
set_simstate_behavior CORRUPT -domain PD_NPU
set_simstate_behavior CORRUPT -domain PD_PERI
set_simstate_behavior NORMAL  -domain PD_TOP
set_simstate_behavior NORMAL  -domain PD_DDR

# ================================================================
# End of UPF
# ================================================================
```

---

## 10.3 UPF 与芯片物理实现的对应

### 芯片 Floorplan 示意

```
┌──────────────────────────────────────────────────────────────────┐
│ Die: MobileStar SoC                                               │
│                                                                   │
│  VDD PAD ──┐  VSS PAD ──┐  VDDQ PAD ──┐                        │
│            │            │             │                          │
│  ══════════╪════════════╪═════════════╪════ Power Ring ══════    │
│            │            │             │                          │
│  ┌─────────┼────────────┤             │                          │
│  │         │            │             │                          │
│  │ PD_CORE0│  PD_CORE1  │    PD_GPU   │         PD_DDR          │
│  │ [SW0]   │  [SW1]     │    [SW_GPU] │                         │
│  │ A55     │  A55       │    Shader   │  DDR     DDR            │
│  │         │            │    Texture  │  Ctrl    PHY            │
│  ├─────────┼────────────┤             │                         │
│  │         │            │             │         ┌───────┐       │
│  │ PD_CORE2│  PD_CORE3  └─────────────┘         │PD_PERI│       │
│  │ [SW2]   │  [SW3]                              │[SW_P] │       │
│  │ A76     │  A76                                │UART   │       │
│  │         │            ┌─────────────┐         │SPI    │       │
│  ├─────────┴────────────┤             │         │I2C    │       │
│  │                      │  PD_NPU     │         └───────┘       │
│  │    L2 Cache          │  [SW_NPU]   │                         │
│  │    (PD_CPU 域)        │  Neural Proc│                         │
│  │                      └─────────────┘                         │
│  └──────────────────────────────────────────────────────────────│
│                                                                   │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │ PD_TOP (Always-On Domain)                                     ││
│  │ PMU | GIC | Timer | RTC | WakeUp | Debug | Bus Interconnect  ││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                   │
│  ══════════════════════════════════════════ Power Ring ══════    │
└──────────────────────────────────────────────────────────────────┘
```

### 电源网格拓扑

```
从 PAD 到标准单元的完整供电路径：

VDD PAD ──→ Power Ring (M9) ──→ Power Strap (M7/M5)
                                      │
                    ┌─────────────────┼───────────────┐
                    │                 │               │
                    ▼                 ▼               ▼
              PD_TOP 域          SW_CORE0         SW_GPU
              (直接供电)       (Power Switch)    (Power Switch)
                    │                 │               │
                    ▼                 ▼               ▼
              PMU/GIC/Bus        VDD_SW_CORE0    VDD_SW_GPU
              标准单元VDD Rail    Core0 VDD Rail   GPU VDD Rail
```

---

## 10.4 验证 Checklist

### UPF 编写完成后的验证项目

```
□ 1. UPF 语法检查
     工具：verify_upf (Synopsys) / check_lp_constraints (Cadence)
     确认：无语法错误，所有引用的网络和域存在

□ 2. 电源域覆盖检查
     确认：所有 RTL 模块都被分配到某个电源域
     确认：没有遗漏的逻辑

□ 3. 隔离完整性检查
     确认：所有跨域输出信号都有隔离策略
     确认：clamp_value 选择正确（不会导致功能问题）

□ 4. 电平转换完整性检查
     确认：所有跨电压域信号都有 Level Shifter
     确认：LS 方向正确 (HL/LH)

□ 5. Retention 检查
     确认：关键寄存器都有 Retention 策略
     确认：Save/Restore 时序正确

□ 6. 电源状态表检查
     确认：所有功耗模式都在 PST 中定义
     确认：没有非法的状态组合

□ 7. Power-Aware 仿真
     工具：VCS + UPF / Xcelium + UPF
     确认：所有功耗模式切换功能正确
     确认：Retention 数据正确保存和恢复
     确认：隔离值在关断时正确

□ 8. Formal Verification
     工具：VC LP (Synopsys) / Conformal LP (Cadence)
     确认：UPF 与 RTL 之间的一致性
     确认：低功耗策略逻辑正确
```

---

## 10.5 常见问题与调试

### 问题 1：仿真中出现 X 传播

```
症状：关断域的输出信号出现 X，且传播到整个系统
原因：隔离使能信号时序不正确
修复：
  1. 检查 iso_enable 是否在断电前置位
  2. 确认 iso_enable 由常开域逻辑驱动
  3. 确认 isolation_power_net 是常开电源
```

### 问题 2：Retention 恢复后数据错误

```
症状：上电后寄存器值与关断前不同
原因：save/restore 信号时序错误
修复：
  1. 确认 save 在断电前触发且有足够保持时间
  2. 确认 restore 在电源稳定后触发
  3. 确认 retention_power_net 在关断期间保持供电
```

### 问题 3：综合后面积超预算

```
症状：Power-Aware 综合后面积比预期大很多
原因：过多的 Isolation/Level Shifter/Retention 单元
修复：
  1. 优化域划分，减少跨域信号数量
  2. 使用 -no_isolation 免除不需要隔离的信号
  3. 使用 -no_retention 免除不关键的寄存器
  4. 考虑使用 Combo Cell 减少面积
```

### 问题 4：IR Drop 过大

```
症状：域内时序违规(Timing Violation)
原因：Power Switch 驱动能力不足
修复：
  1. 增加 Switch Cell 数量或使用更大驱动强度的库单元
  2. 优化 Power Grid 密度
  3. 在 map_power_switch 中指定更大的库单元
```

---

## 10.6 DDR 低功耗模式

### DDR 控制器的电源管理

DDR 子系统在 SoC 低功耗设计中有特殊地位：它通常**不完全关断**，但支持多种低功耗模式。

```
DDR 低功耗模式层次：

  ┌─────────────────────────────────────────────────┐
  │ 模式               │ 功耗  │ 恢复时间 │ 数据保持 │
  ├────────────────────┼───────┼──────────┼─────────┤
  │ Active             │ 100%  │ 0        │ ✅      │
  │ Idle (CKE low)     │ ~40%  │ ~ns 级   │ ✅      │
  │ Power-Down         │ ~15%  │ ~μs 级   │ ✅      │
  │ Self-Refresh       │ ~3%   │ ~μs 级   │ ✅      │
  │ Deep Power-Down    │ ~0.5% │ ~ms 级   │ ❌      │
  └─────────────────────────────────────────────────┘
```

```tcl
# UPF 中 DDR 域的电源状态描述
add_power_state SS_DDR \
    -state {ACTIVE        -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {SELF_REFRESH  -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {OFF           -supply_expr {power == `{OFF}}}
# 注意：Self-Refresh 时电源不关断，但控制器进入低功耗状态

add_power_state SS_DDR_IO \
    -state {ACTIVE    -supply_expr {power == `{FULL_ON, 1.1}}} \
    -state {LOW_POWER -supply_expr {power == `{FULL_ON, 1.1}}} \
    -state {OFF       -supply_expr {power == `{OFF}}}
```

---

## 10.7 完整的验证环境搭建

### 10.7.1 Power-Aware 仿真 Testbench 结构

```
┌──────────────────────────────────────────────┐
│                Testbench                      │
│                                              │
│  ┌────────────────────┐  ┌───────────────┐   │
│  │ PMU Stimulus       │  │ Traffic Gen   │   │
│  │ (电源模式控制)      │  │ (功能激励)     │   │
│  └────────┬───────────┘  └───────┬───────┘   │
│           │                      │            │
│           ▼                      ▼            │
│  ┌────────────────────────────────────────┐  │
│  │            DUT (SoC)                    │  │
│  │   ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐ │  │
│  │   │ CPU │  │ GPU │  │ NPU │  │ DDR │ │  │
│  │   └─────┘  └─────┘  └─────┘  └─────┘ │  │
│  │                                        │  │
│  │   UPF: mobile_star_top.upf             │  │
│  └────────────────────────────────────────┘  │
│           │                                   │
│           ▼                                   │
│  ┌────────────────────┐  ┌───────────────┐   │
│  │ Power-Aware        │  │ Functional    │   │
│  │ Checker            │  │ Checker       │   │
│  │ (电源状态检查)      │  │ (功能正确性)   │   │
│  └────────────────────┘  └───────────────┘   │
│                                              │
└──────────────────────────────────────────────┘
```

### 10.7.2 关键验证场景

```
必须覆盖的低功耗验证场景：

场景 1: 基本电源关断与恢复
  1. 正常运行 → 2. 停时钟 → 3. 保存状态 → 
  4. 隔离 → 5. 断电 → 6. 通电 → 
  7. 恢复状态 → 8. 解除隔离 → 9. 恢复时钟 → 
  10. 验证功能正确

场景 2: 多域交叉关断
  1. CPU Core0 关断 → Core1 仍运行
  2. Core1 访问共享 L2 → 验证 L2 正常
  3. Core0 唤醒 → 验证 Core0 恢复正确

场景 3: DVFS 切换
  1. CPU 在 0.9V 运行 → 降压到 0.75V
  2. 验证时钟频率同步降低
  3. 验证降压期间数据完整性

场景 4: 快速唤醒
  1. 从 SLEEP 模式 → 中断触发
  2. 验证唤醒延迟 < 规格要求
  3. 验证唤醒后功能立即可用

场景 5: 异常场景
  1. 关断过程中收到中断 → 验证隔离正确
  2. 上电过程中电源不稳定 → 验证 ack 时序
  3. 多域同时切换 → 验证无竞争条件
```

### 10.7.3 Coverage 收集

```tcl
# 仿真中收集低功耗相关的覆盖率

# 1. 电源状态覆盖率
#    确保每个域的每个电源状态都被覆盖
#    确保每种合法的状态转换都被覆盖

# 2. 隔离覆盖率
#    确保每个隔离单元都被激活过
#    确保隔离值在关断时被正确钳位

# 3. Retention 覆盖率
#    确保 save/restore 在各种数据模式下都被验证
#    确保 all-0、all-1、随机数据都能正确保持

# 4. 跨域信号覆盖率
#    确保跨域信号在源域关断时被正确处理
#    确保电平转换在各种电压组合下正确工作
```

---

## 10.8 本章小结

本案例展示了一个完整的移动 SoC 的 UPF 编写流程：

1. **架构规划** → 确定电源域划分和功耗模式
2. **域定义** → `create_power_domain` 划分电压岛
3. **供电网络** → `create_supply_port/net`、`connect_supply_net`、`create_supply_set` 建立电源拓扑
4. **电源开关** → `create_power_switch` 实现 Power Gating
5. **隔离策略** → `set_isolation` 处理域边界信号
6. **电平转换** → `set_level_shifter` 处理跨电压域信号
7. **状态保持** → `set_retention` 保存关键寄存器状态
8. **电源状态** → `add_power_state` 定义合法的电源模式（基于 Supply Set）
9. **仿真控制** → `set_simstate_behavior` 设置仿真行为
10. **验证** → Power-Aware 仿真和 Formal Verification

> **每条 UPF 命令都不是抽象的文字描述，而是最终会映射到芯片上的物理结构。理解这种映射关系，是真正掌握 UPF 的关键。**
