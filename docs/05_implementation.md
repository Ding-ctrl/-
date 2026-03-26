# 第五阶段：低功耗实现——综合与后端（详细版）

> 本文档是[芯片低功耗设计完整学习指南](../low_power_design_learning_guide.md)第五阶段的深入展开，覆盖低功耗综合的完整脚本、后端 Power Planning 细节、IR Drop 分析以及功耗签核流程。

---

## 目录

- [1. 低功耗综合完整流程](#1-低功耗综合完整流程)
- [2. 后端低功耗实现](#2-后端低功耗实现)
- [3. IR Drop 分析详解](#3-ir-drop-分析详解)
- [4. 功耗分析与签核](#4-功耗分析与签核)
- [5. 低功耗物理验证](#5-低功耗物理验证)

---

## 1. 低功耗综合完整流程

### 1.1 Design Compiler (DC) 低功耗综合完整脚本

```tcl
# ══════════════════════════════════════════════════════
# Design Compiler 低功耗综合完整脚本
# ══════════════════════════════════════════════════════

# ──── 1. 设置搜索路径和库 ────
set search_path [list . ../lib ../rtl]

set target_library  "ss_0p81v_125c.db"     ;# 最慢角
set link_library    "* $target_library"

# Multi-Vt 库
set_attribute [get_libs ss_0p81v_125c] default_threshold_voltage_group SVT
set_attribute [get_libs ss_0p81v_125c_hvt] default_threshold_voltage_group HVT
set_attribute [get_libs ss_0p81v_125c_lvt] default_threshold_voltage_group LVT

# ──── 2. 读入设计 ────
read_file -format sverilog [glob ../rtl/*.sv]
current_design top

# ──── 3. 读入 UPF ────
load_upf ../upf/top.upf
# 或
# read_upf ../upf/top.upf

# ──── 4. 读入约束 ────
source ../constraints/top.sdc

# ──── 5. Clock Gating 设置 ────
# 自动 Clock Gating 插入策略
set_clock_gating_style \
    -sequential_cell latch \
    -positive_edge_logic {integrated:CKLNQD1BWP} \
    -negative_edge_logic {integrated:CKLNQD1BWP} \
    -minimum_bitwidth 3 \
    -max_fanout 64 \
    -num_stages 1 \
    -control_point before \
    -control_signal scan_enable

# ──── 6. 低功耗优化设置 ────
# 漏电优化
set_leakage_optimization true
set_max_leakage_power 0

# Multi-Vt 约束: 限制 LVT 使用比例（LVT 漏电高）
set_multi_vth_constraint -type ratio \
    -lvth_groups {LVT} -ratio 0.15  ;# LVT 不超过 15%

# 动态功耗优化
set_dynamic_optimization true
set_max_dynamic_power 0

# 操作数隔离
set_operand_isolation_style -logic and

# ──── 7. 编译 ────
compile_ultra \
    -gate_clock \
    -scan \
    -retime \
    -timing_high_effort_script

# 或分步编译:
# compile_ultra -gate_clock -no_autoungroup  ;# 第一遍
# optimize_netlist -area                      ;# 优化面积
# compile_ultra -incremental                   ;# 增量编译

# ──── 8. 优化迭代 ────
# 检查时序
report_timing -max_paths 10 -significant_digits 3

# 检查功耗
report_power -analysis_effort high -verbose

# 如果漏电过高，增加 HVT 使用
set_multi_vth_constraint -type ratio \
    -lvth_groups {LVT} -ratio 0.10  ;# 减少到 10%
compile_ultra -incremental

# ──── 9. 报告 ────
# Clock Gating 报告
report_clock_gating -detail > rpt/clock_gating.rpt

# 功耗报告
report_power -hierarchy -levels 3 > rpt/power.rpt
report_power -cell_power -sort_by total_power > rpt/power_cells.rpt

# Multi-Vt 报告
report_threshold_voltage_group > rpt/vth_groups.rpt

# 面积报告
report_area -hierarchy > rpt/area.rpt

# ──── 10. 输出 ────
# 网表
write -hierarchy -format verilog -output results/top_synth.v

# UPF (综合后更新)
save_upf results/top_synth.upf

# SDC (综合后约束)
write_sdc -nosplit results/top_synth.sdc

# SAIF (如果有仿真数据)
# saif_map -start
# 运行仿真产生 SAIF...
# read_saif sim.saif
```

### 1.2 Clock Gating 插入策略详解

```
minimum_bitwidth 参数的影响:

bitwidth=1: 每个有使能的寄存器都插入 ICG
  + 最高 Clock Gating 覆盖率
  - ICG 面积开销大（每个 ICG 约等于 3-4 个 DFF）
  - 可能增加时钟树负载

bitwidth=4: 至少 4-bit 寄存器才共享 ICG
  + 面积效率好
  + Clock Gating 覆盖率仍然较高
  - 小于4位的寄存器不被门控

bitwidth=8: 至少 8-bit 寄存器共享 ICG
  + 面积开销最小
  - Clock Gating 覆盖率可能不足

推荐: 从 bitwidth=3 或 4 开始，根据覆盖率和面积结果调整

max_fanout 参数:
  每个 ICG 最多驱动的寄存器位数
  太大: ICG 负载重，时钟偏斜大
  太小: ICG 数量多，面积增加
  推荐: 32~64
```

### 1.3 Multi-Vt 优化策略

```
Multi-Vt 优化流程:

Phase 1: 初始综合（全部使用 SVT）
  compile_ultra -gate_clock

Phase 2: 时序检查
  report_timing → 确认时序收敛

Phase 3: 漏电优化（替换为 HVT）
  set_multi_vth_constraint -type ratio -lvth_groups {LVT} -ratio 0.0
  optimize_netlist -area  ;# 非关键路径换为 HVT

Phase 4: 时序修复（关键路径用 LVT）
  report_timing → 找到时序违规路径
  size_cell [get_cells -of [get_timing_paths -slack_lesser_than 0]] \
      -lib_cell [get_lib_cells */LVT/*]

Phase 5: 迭代平衡
  重复 Phase 3-4 直到 timing 和 leakage 都满足

理想的 Vt 分布:
  HVT: 60%~70% (非关键路径，低漏电)
  SVT: 20%~30% (中等路径)
  LVT: 5%~15%  (关键路径，高速但高漏电)
  ULVT: <3%    (极少数最关键路径)
```

### 1.4 Genus (Cadence) 低功耗综合

```tcl
# ══════════════════════════════════════════════════════
# Genus 低功耗综合完整脚本
# ══════════════════════════════════════════════════════

# 读入设计
read_hdl -sv [glob ../rtl/*.sv]

# 读入 UPF
read_power_intent -1801 ../upf/top.upf

# 约束
read_sdc ../constraints/top.sdc

# Elaborate
elaborate top

# 检查 Power Intent
check_power_intent -verbose

# 设置优化目标
set_db / .design_process_node 7
set_db / .leakage_power_effort high
set_db / .dynamic_power_effort high

# Clock Gating 设置
set_db / .lp_insert_clock_gating true
set_db / .lp_clock_gating_min_flops 3
set_db / .lp_clock_gating_max_flops 64

# Multi-Vt
set_db / .use_multibit_cells true
set_db / .leakage_power_effort high

# 综合
synthesize -to_mapped -effort high

# 报告
report_power > rpt/power.rpt
report_gates -power > rpt/gates_power.rpt
report_clock_gating > rpt/cg.rpt

# 输出
write_hdl > results/top_synth.v
write_power_intent -1801 -output results/top_synth.upf
write_sdc > results/top_synth.sdc
```

---

## 2. 后端低功耗实现

### 2.1 Power Planning 详解

```
Power Planning 是后端低功耗实现的基础:

┌──────────────────────────────────────────────────────────────────┐
│                     Power Grid 层次结构                            │
│                                                                   │
│  M1/M2: 标准单元内部供电                                           │
│  ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐                               │
│  │VD││VS││VD││VS││VD││VS││VD││VS│  ← 标准单元行的 Power Rail      │
│  └──┘└──┘└──┘└──┘└──┘└──┘└──┘└──┘                               │
│                                                                   │
│  M3/M4: 局部供电网格 (Followpin)                                   │
│  ═══VDD═══════════════════════════                                │
│  ═══VSS═══════════════════════════                                │
│                                                                   │
│  M5/M6: Power Stripe (垂直/水平)                                   │
│  ║VDD║        ║VDD║        ║VDD║                                  │
│  ║   ║        ║   ║        ║   ║                                  │
│  ════════VDD════════════VDD════════  水平                          │
│  ║   ║        ║   ║        ║   ║                                  │
│  ║VSS║        ║VSS║        ║VSS║                                  │
│                                                                   │
│  M7/M8 (顶层): Power Ring (电源环)                                 │
│  ╔═══════════════════════════════════╗                             │
│  ║  VDD Ring                        ║                             │
│  ║  ╔═══════════════════════════╗   ║                             │
│  ║  ║  VSS Ring                 ║   ║                             │
│  ║  ║     (芯片/域 内容)        ║   ║                             │
│  ║  ╚═══════════════════════════╝   ║                             │
│  ╚═══════════════════════════════════╝                             │
│                                                                   │
│  Via Array: 各层金属间的连接                                        │
│  ╫──── M7到M6 的 Via 阵列                                          │
│  ╫──── M6到M5 的 Via 阵列                                          │
│  ...                                                              │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 Power Switch 物理实现

```
Power Switch (Header/Footer) 的物理放置:

方式1: 域边界放置 (Ring of Switches)
╔═══════════════════════════════════════╗
║ SW SW SW SW SW SW SW SW SW SW SW SW   ║
║ SW ┌─────────────────────────────┐ SW ║
║ SW │      Power Domain           │ SW ║
║ SW │      (标准单元区域)          │ SW ║
║ SW │                             │ SW ║
║ SW └─────────────────────────────┘ SW ║
║ SW SW SW SW SW SW SW SW SW SW SW SW   ║
╚═══════════════════════════════════════╝

方式2: 均匀分布 (Distributed Switches)
╔═══════════════════════════════════════╗
║  SW    SW    SW    SW    SW    SW     ║
║     标准单元   标准单元   标准单元     ║
║  SW    SW    SW    SW    SW    SW     ║
║     标准单元   标准单元   标准单元     ║
║  SW    SW    SW    SW    SW    SW     ║
║     标准单元   标准单元   标准单元     ║
╚═══════════════════════════════════════╝

方式2更优: 均匀分布确保每个标准单元到最近Switch的距离短
          IR Drop 更均匀

Daisy Chain 连接:
SW1.ack → SW2.en → SW2.ack → SW3.en → ... → SWn.ack (输出)
```

### 2.3 ICC2/Fusion Compiler 低功耗后端脚本

```tcl
# ══════════════════════════════════════════════════════
# ICC2 低功耗后端实现关键步骤 (简化)
# ══════════════════════════════════════════════════════

# 1. 读入设计
read_verilog ../synth/top_synth.v
read_upf ../synth/top_synth.upf
read_sdc ../synth/top_synth.sdc

# 2. Floorplan
initialize_floorplan \
    -core_utilization 0.7 \
    -core_offset {10 10 10 10}

# 3. 创建 Power Domain 物理区域
create_voltage_area VA_CPU \
    -power_domain PD_CPU \
    -coordinate {{100 100} {500 500}} \
    -guard_band_x 5 \
    -guard_band_y 5

create_voltage_area VA_GPU \
    -power_domain PD_GPU \
    -coordinate {{550 100} {900 500}}

# 4. Power Planning - 电源环
create_pg_ring_pattern ring_top \
    -horizontal_layer M8 \
    -vertical_layer M7 \
    -horizontal_width 5 \
    -vertical_width 5

set_pg_strategy ring_strat \
    -pattern {{name: ring_top} {nets: {VDD VSS}}} \
    -core

compile_pg

# 5. Power Stripe
create_pg_stripe_pattern stripe_pattern \
    -direction vertical \
    -layer M6 \
    -width 2 \
    -spacing 2 \
    -pitch 40

set_pg_strategy stripe_strat \
    -pattern {{name: stripe_pattern} {nets: {VDD VSS}}}

compile_pg

# 6. 放置 Power Switch
create_power_switch_array \
    -power_switch sw_cpu \
    -direction horizontal \
    -pitch 20

# 7. 放置 Isolation Cell 和 Level Shifter
# (通常自动放置在域边界)
place_opt -power

# 8. 时钟树综合 (CTS)
# 考虑多电压域时钟
clock_opt -power

# 9. 布线
route_opt -power

# 10. 功耗分析
report_power > rpt/power_postroute.rpt

# 11. IR Drop 分析
analyze_power_plan -power_budget 1.0
```

---

## 3. IR Drop 分析详解

### 3.1 IR Drop 概念

```
IR Drop = 电流(I) × 电阻(R)

当电流流过电源网络的金属线时，由于金属线有电阻，
会产生压降，导致实际到达标准单元的电压低于理想值。

理想:   VDD = 0.9V ──────→ 标准单元看到 0.9V
实际:   VDD = 0.9V ──R──→ 标准单元看到 0.9V - IR = 0.87V
                    ↑
               IR Drop = 30mV (3.3%)

影响:
1. 时序: 电压降低 → 延迟增加 → 可能导致时序违规
2. 功能: 极端情况下可能导致逻辑错误
3. 可靠性: 局部过热、电迁移(EM)

允许的 IR Drop 通常 < 5% × VDD (严格设计 < 3%)
```

### 3.2 静态 IR Drop vs 动态 IR Drop

```
静态 IR Drop (Static):
- 稳态电流导致的持续电压降
- 分析方法: 平均电流 × 电阻网络
- 优化: 增加金属宽度/密度

动态 IR Drop (Dynamic):
- 大量单元同时翻转导致的瞬态电流尖峰
- 通常远大于静态 IR Drop (可达 2~5 倍)
- 最坏情况: 时钟沿到达时所有寄存器同时翻转
- 优化: 分散时钟到达时间、增加去耦电容

分析工具:
- Synopsys RedHawk / ANSYS RedHawk-SC
- Cadence Voltus
- Synopsys PrimeTime + PTPX + RedHawk 联合分析
```

### 3.3 IR Drop 对 Power Gating 的特殊影响

```
Power Gating 恢复时的 Rush Current:

电源恢复瞬间，所有标准单元的内部电容需要充电
→ 产生巨大的浪涌电流 (Rush Current)
→ 导致严重的动态 IR Drop

Rush Current 估算:
I_rush ≈ C_total_domain × V_DD / t_ramp
假设: C_total = 1nF, VDD = 0.9V, t_ramp = 1ns
I_rush ≈ 1×10⁻⁹ × 0.9 / 1×10⁻⁹ = 0.9A !!

解决方案:
1. Daisy Chain Power Switch: 分批开启，控制充电速率
2. Ramp-up 控制: 逐步增加 Switch 导通程度
3. 时钟延迟恢复: 电源稳定后再恢复时钟
4. 去耦电容: 提供局部电荷储备
```

---

## 4. 功耗分析与签核

### 4.1 PrimeTime PX (PTPX) 完整功耗分析流程

```tcl
# ══════════════════════════════════════════════════════
# PTPX 功耗分析完整脚本
# ══════════════════════════════════════════════════════

# 1. 设置库和设计
set search_path [list . ../lib]
set link_library "* tt_0p9v_25c.db"
set target_library "tt_0p9v_25c.db"

# 读入网表
read_verilog ../pnr/top_postroute.v
current_design top
link

# 读入约束
read_sdc ../pnr/top_postroute.sdc

# 读入寄生参数 (从后端提取)
read_parasitics ../pnr/top_postroute.spef

# 2. 设置功耗分析模式
set_power_analysis_options \
    -waveform_format fsdb \
    -include_all_analysis_nets true

# 3. 读入翻转率信息
# 方式A: 使用 SAIF (统计型)
read_saif ../sim/top.saif -strip_path tb/u_dut

# 方式B: 使用 VCD (详细型, 用于峰值分析)
# read_vcd ../sim/top.vcd -strip_path tb/u_dut

# 方式C: 设置默认翻转率 (无仿真数据时)
# set_switching_activity -static_probability 0.5 \
#     -toggle_rate 0.1 -type inputs

# 4. 功耗分析
update_power

# 5. 生成报告
# 层次化功耗报告
report_power -hierarchy -levels 5 > rpt/power_hierarchy.rpt

# 按单元类型报告
report_power -cell_power -sort_by total > rpt/power_by_cell.rpt

# 按模块报告
report_power -groups {clock_network register combinational} > rpt/power_groups.rpt

# 详细的 net 级功耗
report_power -net -sort_by total_power > rpt/power_nets.rpt

# 漏电功耗详细报告
report_power -leakage > rpt/leakage.rpt

# Vth 分组功耗
report_threshold_voltage_group > rpt/vth_power.rpt
```

### 4.2 典型功耗报告解读

```
PrimeTime PX 功耗报告示例:

═══════════════════════════════════════════════════
          Power Summary Report
═══════════════════════════════════════════════════

Design:           top
Library:          tt_0p9v_25c
Operating Conditions: tt_0p9v_25c
Wire Load Model:  PostRoute (SPEF)
Activity Source:  SAIF (sim.saif)

Global Operating Voltage = 0.900V
Power-specific unit information:
  Voltage Units = 1V
  Capacitance Units = 1pF
  Time Units = 1ns
  Dynamic Power Units = 1mW
  Leakage Power Units = 1nW

                 Internal  Switching  Leakage    Total
                 Power     Power      Power      Power     %
─────────────────────────────────────────────────────────────
u_cpu            120.5     85.3       15200      221.0    44%  ← 关注最大模块
u_gpu             80.2     55.8        8500      144.5    29%
u_memory          30.1     22.5        5000       57.6    12%
u_bus             15.3     10.2        2000       27.5     5%
u_peripheral       8.5      5.1        1500       15.1     3%
u_pmu              2.1      1.3         500        3.9     1%
clock_network      0.0     25.0          50       25.1     5%  ← 时钟树功耗
other              3.0      1.5         200        4.7     1%
─────────────────────────────────────────────────────────────
Total            259.7    206.7       32950      499.4   100%

Internal Power:   259.7 mW  (52.0%)  ← 内部翻转
Switching Power:  206.7 mW  (41.4%)  ← 输出翻转
Leakage Power:     33.0 mW  ( 6.6%)  ← 漏电
─────────────────────────────────────
Total Power:      499.4 mW  (100%)

Clock Network:     25.1 mW  ( 5.0%)  ← 时钟树占比
```

### 4.3 功耗优化建议（基于报告）

```
分析功耗报告后的优化方向:

1. 如果时钟网络功耗高 (>30%):
   → 增加 Clock Gating 覆盖率
   → 减少不必要的时钟缓冲
   → 考虑系统级时钟门控

2. 如果某个模块功耗异常高:
   → 检查翻转率是否合理
   → 检查是否缺少 Clock Gating
   → 检查操作数隔离是否到位

3. 如果漏电功耗高:
   → 增加 HVT 使用比例
   → 考虑 Power Gating
   → 检查 Multi-Vt 分布

4. 如果 Switching Power 高:
   → 检查总线翻转率
   → 考虑数据编码优化
   → 检查毛刺传播
```

---

## 5. 低功耗物理验证

### 5.1 低功耗 DRC (Design Rule Check)

```
低功耗相关的物理验证规则:

1. Power Domain 边界规则:
   □ 不同 Power Domain 间有物理隔离
   □ Isolation Cell 在正确位置
   □ Level Shifter 在正确位置

2. Power Switch 规则:
   □ Switch 分布均匀
   □ Daisy Chain 连接正确
   □ Switch 到标准单元的距离在允许范围内

3. 电源网络规则:
   □ Power Ring/Stripe 宽度满足电流要求
   □ Via 阵列密度满足要求
   □ 没有断开的供电网络

4. Retention Register 规则:
   □ Always-On supply rail 连接正确
   □ 双供电轨布线无冲突

5. 电迁移 (EM) 规则:
   □ 电流密度不超过金属线承载能力
   □ 特别检查 Power Switch 附近的高电流区域
```

### 5.2 低功耗 LVS (Layout vs Schematic)

```
低功耗 LVS 检查要点:

1. 供电网络连通性:
   - 每个 Power Domain 的 VDD/VSS 连接正确
   - Power Switch 的输入/输出/控制端连接正确
   - Always-On 供电网络连续性

2. 特殊单元检查:
   - Isolation Cell 供电正确
   - Level Shifter 双供电正确
   - Retention Register 双供电正确

3. 等价性检查 (与综合后网表):
   - Conformal Low Power (Cadence)
   - Formality (Synopsys)
   - 需要 UPF 支持的低功耗等价性检查
```

---

> 返回 [主学习指南](../low_power_design_learning_guide.md) | 上一章 ← [UPF验证详解](04_upf_verification.md) | 下一章 → [EDA工具实战详解](06_eda_tools.md)
