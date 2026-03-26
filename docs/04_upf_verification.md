# 第四阶段：低功耗验证 UPF（详细版）

> 本文档是[芯片低功耗设计完整学习指南](../low_power_design_learning_guide.md)第四阶段的深入展开，覆盖 UPF 的完整语法、层次化 UPF、验证方法学和完整 Testbench 框架。

---

## 目录

- [1. UPF 语言基础](#1-upf-语言基础)
- [2. UPF 命令完整参考](#2-upf-命令完整参考)
- [3. 层次化 UPF (Hierarchical UPF)](#3-层次化-upf-hierarchical-upf)
- [4. UPF 与 CPF 对比](#4-upf-与-cpf-对比)
- [5. UPF-aware 仿真详解](#5-upf-aware-仿真详解)
- [6. 低功耗验证 Testbench 完整框架](#6-低功耗验证-testbench-完整框架)
- [7. 低功耗断言库](#7-低功耗断言库)
- [8. 低功耗覆盖率模型](#8-低功耗覆盖率模型)
- [9. 常见 UPF 错误与调试](#9-常见-upf-错误与调试)
- [10. 完整 UPF 示例项目](#10-完整-upf-示例项目)

---

## 1. UPF 语言基础

### 1.1 UPF 版本演进

| 版本 | 标准 | 年份 | 主要新增特性 |
|------|------|------|------------|
| UPF 1.0 | IEEE 1801-2009 | 2009 | 基础 power intent 描述 |
| UPF 2.0 | IEEE 1801-2013 | 2013 | Supply Set, Repeater, 改进的 State Table |
| UPF 2.1 | IEEE 1801-2015 | 2015 | Supply Set Handle, 改进的 Liberty 映射 |
| UPF 3.0 | IEEE 1801-2018 | 2018 | 层次化 UPF, Supply Set Pattern |
| UPF 3.1 | IEEE 1801-2023 | 2023 | 增强的 Retention, 改进的验证支持 |

### 1.2 UPF 基本概念关系图

```
┌─────────────────────────────────────────────────────────────────────┐
│                      UPF 概念层次关系                                │
│                                                                      │
│  Supply Port ←──── connect ────→ Supply Net ←── part of ── Supply Set│
│      │                              │                                 │
│      │                              │                                 │
│  (芯片引脚)                    (电源网络)                              │
│                                     │                                 │
│                          ┌──────────┼──────────┐                     │
│                          ▼          ▼          ▼                     │
│                   Power Domain  Power Domain  Power Domain           │
│                   (PD_CPU)      (PD_GPU)      (PD_AON)              │
│                       │             │             │                   │
│                       │             │             │                   │
│                  ┌────┴────┐   ┌───┴────┐   ┌───┴────┐              │
│                  │ Supplies│   │Supplies│   │Supplies│              │
│                  │ primary │   │primary │   │primary │              │
│                  │ (VDD,VSS)│  │(VDD,VSS)│  │(VDD,VSS)│             │
│                  └─────────┘   └────────┘   └────────┘              │
│                       │             │                                 │
│                       ▼             ▼                                 │
│              Power State Table (PST)                                  │
│              ┌─────────────────────────────────────┐                 │
│              │ State    │ VDD_CPU │ VDD_GPU │ VDD_AON│                │
│              │ ALL_ON   │ FULL_ON │ FULL_ON │ FULL_ON│                │
│              │ GPU_OFF  │ FULL_ON │ OFF     │ FULL_ON│                │
│              └─────────────────────────────────────┘                 │
│                                                                      │
│  跨域信号处理:                                                        │
│  ├── Level Shifter:   电压不同时                                     │
│  ├── Isolation Cell:  源域可关断时                                    │
│  └── Retention Reg:   域内需保持状态时                                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. UPF 命令完整参考

### 2.1 Power Domain 命令

```tcl
# ══════════════════════════════════════════════════════
# create_power_domain - 创建电源域
# ══════════════════════════════════════════════════════

# 基本用法：将特定实例划入某个域
create_power_domain PD_CPU -elements {u_cpu}

# 包含当前作用域的所有逻辑（顶层域常用）
create_power_domain PD_TOP -include_scope

# 指定 Supply Set
create_power_domain PD_CPU \
    -elements {u_cpu} \
    -supply {primary} \
    -supply {default_retention}

# UPF 3.0: 带 Supply Set Pattern
create_power_domain PD_CPU \
    -elements {u_cpu} \
    -supply {primary -power VDD_CPU_net -ground VSS_net}


# ══════════════════════════════════════════════════════
# set_scope - 设置 UPF 作用域
# ══════════════════════════════════════════════════════
# 层次化 UPF 中，设置当前 UPF 文件的作用范围
set_scope /top/u_cpu


# ══════════════════════════════════════════════════════
# set_domain_supply_net - 设置域的供电网络
# ══════════════════════════════════════════════════════
set_domain_supply_net PD_CPU \
    -primary_power_net VDD_CPU_net \
    -primary_ground_net VSS_net
```

### 2.2 Supply Network 命令

```tcl
# ══════════════════════════════════════════════════════
# create_supply_port - 创建供电端口
# ══════════════════════════════════════════════════════

# 电源端口
create_supply_port VDD     -direction in
create_supply_port VDD_CPU -direction in
create_supply_port VSS     -direction in

# 指定电压范围（用于验证）
create_supply_port VDD_CPU -direction in \
    -voltage_range {0.65 0.95}   ;# 最低0.65V, 最高0.95V


# ══════════════════════════════════════════════════════
# create_supply_net - 创建供电网络
# ══════════════════════════════════════════════════════

# 基本用法
create_supply_net VDD_CPU_net -domain PD_CPU

# 指定可以被关断（switched supply）
create_supply_net VDD_CPU_sw -domain PD_CPU -resolve pg_type

# 全局网络（跨域共享）
create_supply_net VSS_net


# ══════════════════════════════════════════════════════
# connect_supply_net - 连接供电端口和网络
# ══════════════════════════════════════════════════════
connect_supply_net VDD_CPU_net -ports {VDD_CPU}
connect_supply_net VSS_net     -ports {VSS}


# ══════════════════════════════════════════════════════
# Supply Set (UPF 2.0+)
# ══════════════════════════════════════════════════════
# Supply Set 是一组相关的供电网络（power + ground + 可选的其他）
# 简化了多电源的管理

create_supply_set SS_CPU \
    -function {power VDD_CPU_net} \
    -function {ground VSS_net}

# 将 Supply Set 关联到域
associate_supply_set SS_CPU -handle PD_CPU.primary
```

### 2.3 Power Switch 命令详解

```tcl
# ══════════════════════════════════════════════════════
# create_power_switch - 创建电源开关
# ══════════════════════════════════════════════════════

# 基本 Header Switch
create_power_switch sw_cpu \
    -domain PD_CPU \
    -input_supply_port  {vin  VDD_AON_net} \
    -output_supply_port {vout VDD_CPU_net} \
    -control_port       {ctrl u_pmu/cpu_pwr_en} \
    -on_state           {on_s vin {ctrl}} \
    -off_state          {off_s {!ctrl}}

# 带 ACK 信号的 Power Switch（可检测上电完成）
create_power_switch sw_cpu \
    -domain PD_CPU \
    -input_supply_port  {vin  VDD_AON_net} \
    -output_supply_port {vout VDD_CPU_net} \
    -control_port       {ctrl u_pmu/cpu_pwr_en} \
    -ack_port           {ack  u_pmu/cpu_pwr_ack {ctrl}} \
    -on_state           {on_s vin {ctrl}} \
    -off_state          {off_s {!ctrl}}

# 多控制端口（多路 Daisy Chain 控制）
create_power_switch sw_cpu \
    -domain PD_CPU \
    -input_supply_port  {vin  VDD_AON_net} \
    -output_supply_port {vout VDD_CPU_net} \
    -control_port       {sleep_n u_pmu/cpu_sleep_n} \
    -control_port       {ext_pwr_ok u_pmu/ext_pwr_ok} \
    -on_state           {on_s vin {sleep_n ext_pwr_ok}} \
    -off_state          {off_s {!sleep_n}}
```

### 2.4 Isolation 命令详解

```tcl
# ══════════════════════════════════════════════════════
# set_isolation - 设置隔离策略
# ══════════════════════════════════════════════════════

# Clamp-to-0，应用于输出
set_isolation iso_cpu_out \
    -domain PD_CPU \
    -isolation_power_net VDD_AON_net \
    -isolation_ground_net VSS_net \
    -clamp_value 0 \
    -applies_to outputs

# Clamp-to-1，应用于特定信号
set_isolation iso_cpu_rstn \
    -domain PD_CPU \
    -isolation_power_net VDD_AON_net \
    -isolation_ground_net VSS_net \
    -clamp_value 1 \
    -elements {u_cpu/rst_n_out}   ;# 只对特定信号

# Latch 类型隔离
set_isolation iso_cpu_latch \
    -domain PD_CPU \
    -isolation_power_net VDD_AON_net \
    -isolation_ground_net VSS_net \
    -clamp_value latchh \
    -applies_to outputs

# 对输入的隔离（较少使用）
set_isolation iso_cpu_in \
    -domain PD_CPU \
    -clamp_value 0 \
    -applies_to inputs

# 排除某些信号不需要隔离
set_isolation iso_cpu_out \
    -domain PD_CPU \
    -clamp_value 0 \
    -applies_to outputs \
    -exclude_elements {u_cpu/debug_out u_cpu/test_out}


# ══════════════════════════════════════════════════════
# set_isolation_control - 设置隔离控制信号
# ══════════════════════════════════════════════════════
set_isolation_control iso_cpu_out \
    -domain PD_CPU \
    -isolation_signal u_pmu/cpu_iso_en \
    -isolation_sense high \
    -location parent     ;# parent=在域外放置, self=在域内放置

# isolation_sense:
#   high: isolation_signal=1 时隔离生效
#   low:  isolation_signal=0 时隔离生效
```

### 2.5 Retention 命令详解

```tcl
# ══════════════════════════════════════════════════════
# set_retention - 设置保持策略
# ══════════════════════════════════════════════════════

# 基本 retention
set_retention ret_cpu \
    -domain PD_CPU \
    -retention_power_net VDD_AON_net \
    -retention_ground_net VSS_net

# 只对特定寄存器做 retention
set_retention ret_cpu_cfg \
    -domain PD_CPU \
    -elements {u_cpu/u_cfg_regs/*} \
    -retention_power_net VDD_AON_net \
    -retention_ground_net VSS_net

# 排除不需要 retention 的寄存器
set_retention ret_cpu \
    -domain PD_CPU \
    -retention_power_net VDD_AON_net \
    -retention_ground_net VSS_net \
    -exclude_elements {u_cpu/u_datapath/*}


# ══════════════════════════════════════════════════════
# set_retention_control - 设置保持控制信号
# ══════════════════════════════════════════════════════
set_retention_control ret_cpu \
    -domain PD_CPU \
    -save_signal    {u_pmu/cpu_save    posedge} \
    -restore_signal {u_pmu/cpu_restore posedge}

# save_signal/restore_signal 的沿类型:
#   posedge: 上升沿触发
#   negedge: 下降沿触发
#   high:    高电平有效
#   low:     低电平有效
```

### 2.6 Level Shifter 命令详解

```tcl
# ══════════════════════════════════════════════════════
# set_level_shifter - 设置电平转换器
# ══════════════════════════════════════════════════════

# 基本 L2H level shifter (输出方向)
set_level_shifter ls_cpu_out \
    -domain PD_CPU \
    -applies_to outputs \
    -rule low_to_high \
    -location parent

# H2L level shifter (输入方向)
set_level_shifter ls_cpu_in \
    -domain PD_CPU \
    -applies_to inputs \
    -rule high_to_low \
    -location self

# 双向 level shifter
set_level_shifter ls_cpu_both \
    -domain PD_CPU \
    -applies_to both \
    -rule both

# 排除不需要 LS 的信号（同电压域信号）
set_level_shifter ls_cpu_out \
    -domain PD_CPU \
    -applies_to outputs \
    -rule low_to_high \
    -exclude_elements {u_cpu/same_voltage_sig}

# 指定 LS 单元类型
set_level_shifter ls_cpu_out \
    -domain PD_CPU \
    -applies_to outputs \
    -rule low_to_high \
    -location parent \
    -name_prefix LS_CPU_ \
    -threshold auto       ;# 自动确定是否需要 LS
```

---

## 3. 层次化 UPF (Hierarchical UPF)

### 3.1 为什么需要层次化 UPF

```
问题: 大型 SoC 的 UPF 文件可能有数千行
      所有低功耗意图写在一个文件中 → 维护困难

解决: 层次化 UPF (Hierarchical UPF, H-UPF)
      每个子系统有自己的 UPF 文件
      顶层 UPF 负责整合

文件结构:
project/
├── upf/
│   ├── top.upf          ← 顶层 UPF (集成)
│   ├── cpu.upf          ← CPU 子系统 UPF
│   ├── gpu.upf          ← GPU 子系统 UPF
│   ├── memory.upf       ← Memory 子系统 UPF
│   └── peripheral.upf   ← 外设子系统 UPF
└── rtl/
    ├── top.sv
    ├── cpu/
    ├── gpu/
    └── ...
```

### 3.2 层次化 UPF 示例

```tcl
# ══════════════════════════════════════════════════════
# top.upf - 顶层 UPF
# ══════════════════════════════════════════════════════

# 顶层作用域
set_scope /top

# 顶层域
create_power_domain PD_TOP -include_scope

# 顶层 Supply
create_supply_port VDD     -direction in
create_supply_port VDD_CPU -direction in
create_supply_port VDD_GPU -direction in
create_supply_port VSS     -direction in

create_supply_net VDD_net
create_supply_net VDD_CPU_net
create_supply_net VDD_GPU_net
create_supply_net VSS_net

connect_supply_net VDD_net     -ports {VDD}
connect_supply_net VDD_CPU_net -ports {VDD_CPU}
connect_supply_net VDD_GPU_net -ports {VDD_GPU}
connect_supply_net VSS_net     -ports {VSS}

# 加载子系统 UPF
load_upf cpu.upf -scope u_cpu
load_upf gpu.upf -scope u_gpu

# 顶层连接子系统的供电
connect_supply_net VDD_CPU_net -ports {u_cpu/VDD}
connect_supply_net VSS_net     -ports {u_cpu/VSS}
connect_supply_net VDD_GPU_net -ports {u_gpu/VDD}
connect_supply_net VSS_net     -ports {u_gpu/VSS}

# 顶层的 PST (包含所有子系统)
create_pst top_pst -supplies {VDD_CPU_net VDD_GPU_net VDD_net}
add_pst_state ALL_ON   -pst top_pst -state {FULL_ON FULL_ON FULL_ON}
add_pst_state CPU_OFF  -pst top_pst -state {OFF     FULL_ON FULL_ON}
add_pst_state GPU_OFF  -pst top_pst -state {FULL_ON OFF     FULL_ON}
add_pst_state STANDBY  -pst top_pst -state {OFF     OFF     FULL_ON}


# ══════════════════════════════════════════════════════
# cpu.upf - CPU 子系统 UPF
# ══════════════════════════════════════════════════════

# 设置作用域
set_scope /top/u_cpu

# CPU 子域
create_power_domain PD_CPU -include_scope

# 子系统级 Supply
create_supply_port VDD -direction in
create_supply_port VSS -direction in

create_supply_net VDD_cpu_local
create_supply_net VSS_cpu_local

connect_supply_net VDD_cpu_local -ports {VDD}
connect_supply_net VSS_cpu_local -ports {VSS}

# CPU 域的 primary supply
set_domain_supply_net PD_CPU \
    -primary_power_net VDD_cpu_local \
    -primary_ground_net VSS_cpu_local

# CPU 域的 Isolation
set_isolation iso_cpu \
    -domain PD_CPU \
    -clamp_value 0 \
    -applies_to outputs

set_isolation_control iso_cpu \
    -domain PD_CPU \
    -isolation_signal /top/u_pmu/cpu_iso_en \
    -isolation_sense high \
    -location parent

# CPU 域的 Retention
set_retention ret_cpu \
    -domain PD_CPU \
    -retention_power_net /top/VDD_net \
    -retention_ground_net VSS_cpu_local

set_retention_control ret_cpu \
    -domain PD_CPU \
    -save_signal    {/top/u_pmu/cpu_save    posedge} \
    -restore_signal {/top/u_pmu/cpu_restore posedge}
```

---

## 4. UPF 与 CPF 对比

```
┌────────────────┬───────────────────────┬────────────────────────┐
│ 特性            │ UPF (IEEE 1801)       │ CPF (Cadence)          │
├────────────────┼───────────────────────┼────────────────────────┤
│ 标准化          │ IEEE 标准 ✓            │ 私有格式 ✗             │
│ 主要支持者      │ Synopsys, Mentor, 等  │ Cadence                │
│ 基础语言        │ Tcl                   │ Tcl (类似)              │
│ 版本            │ 1.0 → 3.1            │ 1.0 → 2.1             │
│ 层次化支持      │ UPF 3.0+ 原生支持     │ 有限支持                │
│ 工具支持        │ 几乎所有EDA工具        │ 主要 Cadence 工具       │
│ 行业趋势        │ 主流选择 ★            │ 逐步被 UPF 替代         │
│ 学习建议        │ 重点学习 ★★★★★        │ 了解即可 ★★             │
└────────────────┴───────────────────────┴────────────────────────┘

结论: 新项目应使用 UPF，CPF 作为了解即可
```

---

## 5. UPF-aware 仿真详解

### 5.1 电源状态对信号的影响

```
仿真器在 UPF-aware 模式下的行为:

┌──────────────────────────────────────────────────────────────┐
│ 电源状态     │ 域内寄存器    │ 域内组合逻辑  │ 域输出(有ISO) │
├──────────────┼──────────────┼──────────────┼──────────────┤
│ FULL_ON      │ 正常工作      │ 正常工作     │ 正常值        │
│ OFF          │ 值变为 X      │ 输出为 X     │ 钳位值        │
│ OFF→ON (无RET)│ 保持 X       │ 由输入决定   │ 取消隔离后    │
│ OFF→ON (有RET)│ Restore后恢复│ 由输入决定   │ 取消隔离后    │
│ PARTIAL_ON   │ 部分正常      │ 部分正常     │ 混合          │
└──────────────┴──────────────┴──────────────┴──────────────┘

X 值的传播规则:
- X & 0 = 0  (AND gate: 一个输入为0，输出确定为0)
- X & 1 = X  (AND gate: 不确定)
- X | 1 = 1  (OR gate: 一个输入为1，输出确定为1)
- X | 0 = X  (OR gate: 不确定)

X 传播的意义:
- 帮助发现缺失的 Isolation / Level Shifter
- 帮助验证 Retention Save/Restore 的正确性
- 帮助发现软件初始化遗漏
```

### 5.2 仿真中的关键检查点

```
低功耗仿真中需要检查的关键时刻:

1. 关断瞬间 (Power Off Moment):
   □ Isolation 输出是否正确钳位？
   □ Retention 数据是否已保存？
   □ 时钟是否已停止？
   □ Always-On 域功能是否正常？

2. 关断期间 (While Off):
   □ 关断域输出是否稳定在钳位值？
   □ X 没有泄露到开启域？
   □ 唤醒检测逻辑是否正常？

3. 恢复瞬间 (Power On Moment):
   □ 电源稳定后，Retention 数据是否正确恢复？
   □ 非 Retention 寄存器是否为 X？
   □ 隔离是否在 Restore 后才取消？

4. 恢复完成后 (After Recovery):
   □ 功能是否与关断前一致？
   □ 没有遗留的 X 值？
   □ 软件是否正确初始化了非 Retention 状态？
```

---

## 6. 低功耗验证 Testbench 完整框架

### 6.1 UVM 低功耗验证架构

```systemverilog
// ═══════════════════════════════════════════
// 低功耗验证 UVM Testbench 完整框架
// ═══════════════════════════════════════════

// ─── 1. Power Aware Sequence ───
class power_gating_sequence extends uvm_sequence #(power_txn);
    `uvm_object_utils(power_gating_sequence)

    task body();
        power_txn txn;

        // Phase 1: 正常工作，建立初始状态
        `uvm_info("PG_SEQ", "Phase 1: Establishing initial state", UVM_MEDIUM)
        txn = power_txn::type_id::create("init_txn");
        txn.op_type = WRITE_CONFIG;
        txn.addr = 32'h0000_0100;
        txn.data = 32'hDEAD_BEEF;  // 写入可辨识的数据
        start_item(txn);
        finish_item(txn);

        // 写入更多测试数据
        for (int i = 0; i < 16; i++) begin
            txn = power_txn::type_id::create($sformatf("data_txn_%0d", i));
            txn.op_type = WRITE_DATA;
            txn.addr = 32'h0000_1000 + i * 4;
            txn.data = 32'hA5A5_0000 + i;
            start_item(txn);
            finish_item(txn);
        end

        // Phase 2: 触发 Power Gating
        `uvm_info("PG_SEQ", "Phase 2: Requesting power down", UVM_MEDIUM)
        txn = power_txn::type_id::create("pg_down_txn");
        txn.op_type = POWER_DOWN_REQUEST;
        txn.domain_id = PD_CPU;
        start_item(txn);
        finish_item(txn);

        // Phase 3: 等待关断完成
        `uvm_info("PG_SEQ", "Phase 3: Waiting for power off", UVM_MEDIUM)
        txn = power_txn::type_id::create("wait_off_txn");
        txn.op_type = WAIT_POWER_STATE;
        txn.expected_state = POWER_OFF;
        txn.timeout_cycles = 1000;
        start_item(txn);
        finish_item(txn);

        // Phase 4: 空闲等待（模拟低功耗期间）
        `uvm_info("PG_SEQ", "Phase 4: Idle period (low power)", UVM_MEDIUM)
        #(100 * CLK_PERIOD);  // 等待一段时间

        // Phase 5: 触发唤醒
        `uvm_info("PG_SEQ", "Phase 5: Requesting wakeup", UVM_MEDIUM)
        txn = power_txn::type_id::create("wakeup_txn");
        txn.op_type = POWER_UP_REQUEST;
        txn.domain_id = PD_CPU;
        start_item(txn);
        finish_item(txn);

        // Phase 6: 等待恢复完成
        `uvm_info("PG_SEQ", "Phase 6: Waiting for power on", UVM_MEDIUM)
        txn = power_txn::type_id::create("wait_on_txn");
        txn.op_type = WAIT_POWER_STATE;
        txn.expected_state = POWER_ON;
        txn.timeout_cycles = 5000;
        start_item(txn);
        finish_item(txn);

        // Phase 7: 验证 Retention 数据
        `uvm_info("PG_SEQ", "Phase 7: Checking retained data", UVM_MEDIUM)
        txn = power_txn::type_id::create("check_ret_txn");
        txn.op_type = READ_AND_CHECK;
        txn.addr = 32'h0000_0100;
        txn.expected_data = 32'hDEAD_BEEF;  // 应该与写入的相同
        start_item(txn);
        finish_item(txn);

        // Phase 8: 功能验证
        `uvm_info("PG_SEQ", "Phase 8: Functional check after recovery", UVM_MEDIUM)
        // ... 执行功能测试 ...
    endtask

endclass


// ─── 2. Power State Monitor ───
class power_state_monitor extends uvm_monitor;
    `uvm_component_utils(power_state_monitor)

    // 监控接口
    virtual power_if vif;

    // 分析端口
    uvm_analysis_port #(power_state_txn) state_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        state_ap = new("state_ap", this);
    endfunction

    task run_phase(uvm_phase phase);
        power_state_txn txn;
        forever begin
            @(vif.power_state_change);

            txn = power_state_txn::type_id::create("ps_txn");
            txn.domain_name  = vif.changed_domain;
            txn.old_state    = vif.old_power_state;
            txn.new_state    = vif.new_power_state;
            txn.timestamp    = $time;

            // 检查状态转换顺序
            check_transition_order(txn);

            state_ap.write(txn);
        end
    endtask

    function void check_transition_order(power_state_txn txn);
        // 验证关断顺序: CLK_OFF → ISOLATE → POWER_OFF
        // 验证恢复顺序: POWER_ON → RESTORE → DE_ISOLATE → CLK_ON
        case (txn.new_state)
            POWER_OFF: begin
                if (!isolation_active[txn.domain_name])
                    `uvm_error("PG_CHECK",
                        $sformatf("Domain %s powered off without isolation!",
                                  txn.domain_name))
            end
            // ... 更多检查 ...
        endcase
    endfunction

endclass


// ─── 3. Retention Data Scoreboard ───
class retention_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(retention_scoreboard)

    // 保存 power down 前的寄存器值
    bit [31:0] saved_reg_values[string];

    // 从 monitor 接收数据
    uvm_analysis_imp #(reg_txn, retention_scoreboard) reg_ap;

    function void write(reg_txn txn);
        if (txn.phase == BEFORE_POWER_DOWN) begin
            // 保存关断前的值
            saved_reg_values[txn.reg_name] = txn.value;
            `uvm_info("RET_SB",
                $sformatf("Saved %s = 0x%08h before power down",
                          txn.reg_name, txn.value), UVM_HIGH)
        end
        else if (txn.phase == AFTER_RESTORE) begin
            // 检查恢复后的值
            if (txn.is_retention_reg) begin
                if (saved_reg_values.exists(txn.reg_name)) begin
                    if (txn.value !== saved_reg_values[txn.reg_name]) begin
                        `uvm_error("RET_SB",
                            $sformatf("Retention FAILED for %s: expected=0x%08h, actual=0x%08h",
                                      txn.reg_name,
                                      saved_reg_values[txn.reg_name],
                                      txn.value))
                    end else begin
                        `uvm_info("RET_SB",
                            $sformatf("Retention PASSED for %s = 0x%08h",
                                      txn.reg_name, txn.value), UVM_MEDIUM)
                    end
                end
            end
        end
    endfunction

endclass
```

---

## 7. 低功耗断言库

```systemverilog
// ═══════════════════════════════════════════
// 低功耗 SVA 断言库
// ═══════════════════════════════════════════

module low_power_assertions (
    input wire clk,
    input wire rst_n,

    // PMU 控制信号
    input wire power_switch_en,
    input wire iso_enable,
    input wire ret_save,
    input wire ret_restore,
    input wire clk_enable,

    // 电源状态
    input wire domain_powered
);

    // ─── 1. 关断顺序检查 ───
    // 关断前必须先隔离
    property iso_before_power_off;
        @(posedge clk) disable iff (!rst_n)
        $fell(power_switch_en) |-> iso_enable;
    endproperty
    assert property (iso_before_power_off)
        else `uvm_error("LP_ASSERT", "Power off without isolation!");

    // 关断前必须先停止时钟
    property clk_off_before_power_off;
        @(posedge clk) disable iff (!rst_n)
        $fell(power_switch_en) |-> !clk_enable;
    endproperty
    assert property (clk_off_before_power_off)
        else `uvm_error("LP_ASSERT", "Power off without clock gating!");

    // Save 在关断前完成
    property save_before_power_off;
        @(posedge clk) disable iff (!rst_n)
        $fell(power_switch_en) |-> $past(ret_save, 1) || $past(ret_save, 2);
    endproperty
    assert property (save_before_power_off)
        else `uvm_error("LP_ASSERT", "Power off without retention save!");

    // ─── 2. 恢复顺序检查 ───
    // 恢复后先 Restore 再取消隔离
    property restore_before_deiso;
        @(posedge clk) disable iff (!rst_n)
        $fell(iso_enable) |-> $past(ret_restore) || $past(ret_restore, 2);
    endproperty
    assert property (restore_before_deiso)
        else `uvm_error("LP_ASSERT", "De-isolation without restore!");

    // ─── 3. 互斥检查 ───
    // Save 和 Restore 不能同时有效
    property no_save_restore_overlap;
        @(posedge clk) disable iff (!rst_n)
        !(ret_save && ret_restore);
    endproperty
    assert property (no_save_restore_overlap)
        else `uvm_error("LP_ASSERT", "Save and Restore simultaneously active!");

    // ─── 4. 关断域不应有时钟活动 ───
    property no_clk_when_off;
        @(posedge clk) disable iff (!rst_n)
        !domain_powered |-> !clk_enable;
    endproperty
    assert property (no_clk_when_off)
        else `uvm_error("LP_ASSERT", "Clock active while domain is off!");

endmodule
```

---

## 8. 低功耗覆盖率模型

```systemverilog
// ═══════════════════════════════════════════
// 低功耗功能覆盖率
// ═══════════════════════════════════════════

class low_power_coverage extends uvm_subscriber #(power_state_txn);
    `uvm_component_utils(low_power_coverage)

    // 当前各域状态
    power_state_e cpu_state;
    power_state_e gpu_state;

    // 覆盖率组: Power State 覆盖
    covergroup cg_power_states;
        cp_cpu_state: coverpoint cpu_state {
            bins on      = {POWER_ON};
            bins off     = {POWER_OFF};
            bins ret     = {RETENTION};
            bins clk_gated = {CLK_GATED};
        }

        cp_gpu_state: coverpoint gpu_state {
            bins on  = {POWER_ON};
            bins off = {POWER_OFF};
        }

        // 交叉覆盖: 所有 CPU×GPU 状态组合
        cx_cpu_gpu: cross cp_cpu_state, cp_gpu_state;
    endgroup

    // 覆盖率组: Power State 转换覆盖
    covergroup cg_power_transitions;
        cp_cpu_transition: coverpoint cpu_state {
            bins on_to_off      = (POWER_ON   => POWER_OFF);
            bins off_to_on      = (POWER_OFF  => POWER_ON);
            bins on_to_ret      = (POWER_ON   => RETENTION);
            bins ret_to_on      = (RETENTION  => POWER_ON);
            bins on_to_cg       = (POWER_ON   => CLK_GATED);
            bins cg_to_on       = (CLK_GATED  => POWER_ON);
            // 非法转换 (不应该发生)
            illegal_bins off_to_ret = (POWER_OFF => RETENTION);
        }
    endgroup

    // 覆盖率组: 唤醒源覆盖
    covergroup cg_wakeup_sources;
        cp_wakeup_src: coverpoint wakeup_source {
            bins gpio_wakeup  = {WAKEUP_GPIO};
            bins timer_wakeup = {WAKEUP_TIMER};
            bins irq_wakeup   = {WAKEUP_IRQ};
            bins rtc_wakeup   = {WAKEUP_RTC};
        }

        // 不同功耗状态下的唤醒
        cx_state_wakeup: cross cp_cpu_state, cp_wakeup_src;
    endgroup

    // 覆盖率组: 快速切换场景
    covergroup cg_rapid_switching;
        cp_rapid: coverpoint switch_interval {
            bins very_fast   = {[1:10]};     // 1-10 周期内切换
            bins fast        = {[11:100]};   // 11-100 周期
            bins normal      = {[101:1000]}; // 101-1000 周期
            bins slow        = {[1001:$]};   // 1000+ 周期
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_power_states = new();
        cg_power_transitions = new();
        cg_wakeup_sources = new();
        cg_rapid_switching = new();
    endfunction

    function void write(power_state_txn txn);
        // 更新状态
        case (txn.domain_name)
            "PD_CPU": cpu_state = txn.new_state;
            "PD_GPU": gpu_state = txn.new_state;
        endcase

        // 采样覆盖率
        cg_power_states.sample();
        cg_power_transitions.sample();
    endfunction

endclass
```

---

## 9. 常见 UPF 错误与调试

### 9.1 常见 UPF 编写错误

| 错误类型 | 症状 | 修复方法 |
|---------|------|---------|
| 缺少 Isolation | 关断域输出 X 泄露到开启域 | 添加 `set_isolation` |
| 缺少 Level Shifter | 跨域信号电平不匹配 | 添加 `set_level_shifter` |
| Isolation 供电错误 | ISO cell 自身也被关断 | 确保 ISO 由 Always-On 供电 |
| Save/Restore 时序错误 | Retention 数据丢失 | 检查 Save 在关断前、Restore 在恢复后 |
| PST 状态不完整 | 仿真中出现未定义状态 | 添加所有合法状态组合 |
| Domain 元素遗漏 | 某些逻辑不受电源控制 | 检查 `-elements` 覆盖所有实例 |
| 控制信号路径错误 | 控制信号在关断域中 | 确保控制信号在 Always-On 域 |

### 9.2 UPF 调试技巧

```tcl
# VCS 中的低功耗调试
# 1. 检查 Supply 状态
# 在仿真波形中观察 supply net 的值:
# FULL_ON (1.0), OFF (0.0), PARTIAL_ON (0.x)

# 2. 检查 X 传播
# 使用 -power=xprop_config 配置精确的 X 传播模式

# 3. 使用 UPF query 命令检查策略
# 在仿真中使用 $upf_query 系统函数

# 4. 常用调试开关
# vcs ... -power=verbose        # 详细输出
# vcs ... -power=ring_check     # 检查 supply ring
# vcs ... -power=iso_check      # 检查隔离策略

# Xcelium 中的低功耗调试
# xrun ... -lps_verbose         # 详细低功耗日志
# xrun ... -lps_iso_check       # 隔离检查
# xrun ... -lps_ret_check       # Retention 检查
```

---

## 10. 完整 UPF 示例项目

### 10.1 简单 SoC 的完整 UPF

```tcl
# ══════════════════════════════════════════════════════
# 完整 UPF 示例: 简单 SoC
# 包含: CPU (可关断+retention), GPU (可关断), AON (常开)
# ══════════════════════════════════════════════════════

# ──── 1. Power Domains ────
create_power_domain PD_TOP -include_scope
create_power_domain PD_CPU -elements {u_cpu}
create_power_domain PD_GPU -elements {u_gpu}

# ──── 2. Supply Network ────
# Supply Ports
create_supply_port VDD     -direction in
create_supply_port VDD_CPU -direction in
create_supply_port VDD_GPU -direction in
create_supply_port VSS     -direction in

# Supply Nets
create_supply_net VDD_net     -domain PD_TOP
create_supply_net VDD_CPU_sw  -domain PD_CPU    ;# switched (可关断)
create_supply_net VDD_GPU_sw  -domain PD_GPU    ;# switched
create_supply_net VDD_CPU_src -domain PD_CPU    ;# source (Always-On)
create_supply_net VDD_GPU_src -domain PD_GPU
create_supply_net VSS_net

# Connections
connect_supply_net VDD_net     -ports {VDD}
connect_supply_net VDD_CPU_src -ports {VDD_CPU}
connect_supply_net VDD_GPU_src -ports {VDD_GPU}
connect_supply_net VSS_net     -ports {VSS}

# Set primary supplies
set_domain_supply_net PD_TOP -primary_power_net VDD_net     -primary_ground_net VSS_net
set_domain_supply_net PD_CPU -primary_power_net VDD_CPU_sw  -primary_ground_net VSS_net
set_domain_supply_net PD_GPU -primary_power_net VDD_GPU_sw  -primary_ground_net VSS_net

# ──── 3. Power Switches ────
create_power_switch sw_cpu \
    -domain PD_CPU \
    -input_supply_port  {vin  VDD_CPU_src} \
    -output_supply_port {vout VDD_CPU_sw} \
    -control_port       {ctrl u_pmu/cpu_pwr_en} \
    -ack_port           {ack  u_pmu/cpu_pwr_ack {ctrl}} \
    -on_state           {on_s vin {ctrl}} \
    -off_state          {off_s {!ctrl}}

create_power_switch sw_gpu \
    -domain PD_GPU \
    -input_supply_port  {vin  VDD_GPU_src} \
    -output_supply_port {vout VDD_GPU_sw} \
    -control_port       {ctrl u_pmu/gpu_pwr_en} \
    -ack_port           {ack  u_pmu/gpu_pwr_ack {ctrl}} \
    -on_state           {on_s vin {ctrl}} \
    -off_state          {off_s {!ctrl}}

# ──── 4. Isolation ────
# CPU 输出隔离 (clamp to 0)
set_isolation iso_cpu \
    -domain PD_CPU \
    -isolation_power_net VDD_net \
    -isolation_ground_net VSS_net \
    -clamp_value 0 \
    -applies_to outputs

set_isolation_control iso_cpu \
    -domain PD_CPU \
    -isolation_signal u_pmu/cpu_iso_en \
    -isolation_sense high \
    -location parent

# GPU 输出隔离
set_isolation iso_gpu \
    -domain PD_GPU \
    -isolation_power_net VDD_net \
    -isolation_ground_net VSS_net \
    -clamp_value 0 \
    -applies_to outputs

set_isolation_control iso_gpu \
    -domain PD_GPU \
    -isolation_signal u_pmu/gpu_iso_en \
    -isolation_sense high \
    -location parent

# ──── 5. Retention (仅 CPU) ────
set_retention ret_cpu \
    -domain PD_CPU \
    -retention_power_net VDD_net \
    -retention_ground_net VSS_net

set_retention_control ret_cpu \
    -domain PD_CPU \
    -save_signal    {u_pmu/cpu_ret_save    posedge} \
    -restore_signal {u_pmu/cpu_ret_restore posedge}

# ──── 6. Level Shifters ────
set_level_shifter ls_cpu_to_top \
    -domain PD_CPU \
    -applies_to outputs \
    -rule low_to_high \
    -location parent

set_level_shifter ls_gpu_to_top \
    -domain PD_GPU \
    -applies_to outputs \
    -rule low_to_high \
    -location parent

set_level_shifter ls_top_to_cpu \
    -domain PD_CPU \
    -applies_to inputs \
    -rule high_to_low \
    -location self

set_level_shifter ls_top_to_gpu \
    -domain PD_GPU \
    -applies_to inputs \
    -rule high_to_low \
    -location self

# ──── 7. Power State Table ────
create_pst soc_pst -supplies {VDD_CPU_sw VDD_GPU_sw VDD_net}

add_pst_state ALL_ON    -pst soc_pst -state {FULL_ON FULL_ON FULL_ON}
add_pst_state GPU_OFF   -pst soc_pst -state {FULL_ON OFF     FULL_ON}
add_pst_state CPU_OFF   -pst soc_pst -state {OFF     FULL_ON FULL_ON}
add_pst_state BOTH_OFF  -pst soc_pst -state {OFF     OFF     FULL_ON}

# ──── 完成 ────
```

---

> 返回 [主学习指南](../low_power_design_learning_guide.md) | 上一章 ← [低功耗RTL设计详解](03_rtl_design.md) | 下一章 → [低功耗实现详解](05_implementation.md)
