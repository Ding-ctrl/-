# 第10章 Synopsys/Cadence 低功耗 EDA 工具流程

## 10.1 引言

掌握了 UPF 编写后，下一步是将低功耗设计意图**付诸实践**——通过 EDA 工具链完成从综合到功耗签核的全流程。本章详细介绍 Synopsys 和 Cadence 两大主流 EDA 工具在低功耗设计各环节的具体操作流程、关键命令和调试方法。

## 10.2 低功耗 EDA 工具链全景

### 10.2.1 设计流程与工具对应

```
低功耗EDA工具链:

设计阶段              Synopsys 工具           Cadence 工具
──────────────────────────────────────────────────────────
RTL仿真验证     │  VCS + MVSIM             │  Xcelium + PA
                │  (Power-Aware Sim)        │  (Power-Aware Sim)
──────────────────────────────────────────────────────────
形式化验证      │  VC LP                    │  Conformal LP
                │  (Low Power Verify)       │  (Low Power Check)
──────────────────────────────────────────────────────────
逻辑综合        │  Design Compiler (DC)     │  Genus
                │  compile_ultra + MV       │  with UPF support
──────────────────────────────────────────────────────────
物理实现        │  IC Compiler II (ICC2)    │  Innovus
                │  with Power Domain        │  with CPG/PG
──────────────────────────────────────────────────────────
时序签核        │  PrimeTime (PT)           │  Tempus
                │  Multi-Voltage STA        │  Multi-Voltage STA
──────────────────────────────────────────────────────────
功耗签核        │  PrimeTime PX (PTPX)     │  Voltus
                │  Power Analysis           │  Power Analysis
──────────────────────────────────────────────────────────
IR-Drop分析     │  RedHawk                  │  Voltus-Fi
                │  (Apache)                 │  (IR-Drop)
──────────────────────────────────────────────────────────
```

## 10.3 Design Compiler 低功耗综合

### 10.3.1 综合环境设置

```tcl
###############################################
# DC 低功耗综合脚本
###############################################

# 1. 加载多Vt库
set target_library "
    hvt_ss_0p72v_125c.db \
    svt_ss_0p72v_125c.db \
    lvt_ss_0p72v_125c.db \
    std_0p9v_tt.db
"

set link_library "* $target_library"

# 2. 读入设计
read_verilog {top.v cpu.v gpu.v pmu.v}
current_design top

# 3. 加载UPF
load_upf top.upf
# 或
read_upf top.upf

# 4. 检查UPF一致性
check_mv_design -verbose
```

### 10.3.2 低功耗综合关键命令

```tcl
###############################################
# 低功耗综合核心流程
###############################################

# ============================================
# 时钟门控插入
# ============================================

# 全局使能时钟门控插入
set_clock_gating_style \
    -sequential_cell latch \
    -positive_edge_logic {integrated} \
    -negative_edge_logic {integrated} \
    -minimum_bitwidth 4 \
    -max_fanout 32 \
    -control_point before \
    -control_signal test_mode

# 对特定模块设置不同的CG策略
set_clock_gating_style \
    -sequential_cell latch \
    -minimum_bitwidth 2 \
    -design u_cpu_core

# ============================================
# 操作数隔离 (Operand Isolation)
# ============================================

set_operand_isolation_style -logic or
set_operand_isolation_cell OI_AND2

# ============================================
# 多阈值电压优化
# ============================================

# 设置功耗优化目标
set_max_leakage_power 0          ;# 最小化漏电
set_max_dynamic_power 0          ;# 最小化动态功耗

# 设定Multi-Vt使用约束
set_multi_vt_constraint \
    -lvt_percentage 10 \
    -type hard           ;# 严格限制LVT使用比例

# ============================================
# 执行综合
# ============================================

compile_ultra -gate_clock -scan \
    -no_autoungroup

# ============================================
# 低功耗优化（综合后）
# ============================================

# 功耗优化
optimize_power -area

# 时钟门控优化
optimize_clock_gating

# Multi-Vt 交换（用HVT替换非关键路径上的单元）
set_attribute [get_cells -hierarchical] \
    dont_touch false
power_opt -leakage
```

### 10.3.3 低功耗单元插入

```tcl
###############################################
# 隔离/电平转换/保持单元插入
###############################################

# DC 自动根据UPF插入低功耗单元
# compile_ultra 后检查插入情况

# 查看隔离单元
report_isolation_cell -all

# 查看电平转换单元
report_level_shifter_cell -all

# 查看保持寄存器
report_retention_cell -all

# 查看电源开关
report_power_switch -all

# ============================================
# 手动约束单元选择（如有需要）
# ============================================

# 指定使用特定的隔离单元库
set_isolation iso_cpu \
    -domain PD_CPU \
    -lib_cells {ISOLO_X1 ISOLO_X2 ISOLO_X4}

# 指定保持寄存器类型
set_retention ret_cpu \
    -domain PD_CPU \
    -lib_cells {RDFFS_X1 RDFFS_X2}
```

### 10.3.4 综合报告分析

```tcl
###############################################
# 低功耗相关报告
###############################################

# 功耗报告
report_power -verbose \
    -analysis_effort high \
    > rpt/power_synthesis.rpt

# 各电源域功耗
report_power -power_domain PD_CPU -verbose
report_power -power_domain PD_GPU -verbose

# 时钟门控报告
report_clock_gating -verbose \
    > rpt/clock_gating.rpt

# 时钟门控覆盖率
report_clock_gating -ungated \
    > rpt/ungated_regs.rpt

# Multi-Vt 分布报告
report_threshold_voltage_group \
    > rpt/multi_vt.rpt

# 多电压域设计检查
check_mv_design -verbose \
    > rpt/mv_check.rpt
```

**典型时钟门控报告解读：**

```
Clock Gating Report:
─────────────────────────────────────────
Module              Gated    Ungated    Coverage
u_cpu_core          2456     123        95.2%
u_gpu_core          5678     89         98.5%
u_dma               345      12         96.6%
u_periph            890      234        79.2%  ← 需要优化
─────────────────────────────────────────
Total               9369     458        95.3%
```

## 10.4 Genus 低功耗综合 (Cadence)

### 10.4.1 Genus 低功耗综合流程

```tcl
###############################################
# Cadence Genus 低功耗综合脚本
###############################################

# 1. 设置库
set_db library {
    hvt_ss_0p72v_125c.lib
    svt_ss_0p72v_125c.lib
    lvt_ss_0p72v_125c.lib
}

# 2. 读入设计
read_hdl {top.v cpu.v gpu.v}
elaborate top

# 3. 读入UPF
read_power_intent -1801 top.upf

# 4. 应用电源意图
commit_power_intent

# 5. 检查
check_power_intent

# 6. 时钟门控设置
set_db lp_clock_gating_style integrated
set_db lp_clock_gating_min_flops 4

# 7. 综合
syn_generic
syn_map
syn_opt

# 8. 低功耗单元插入报告
report_power_intent
report_clock_gating
report_power
```

## 10.5 ICC2 电源域物理实现

### 10.5.1 电源域 Floorplan

```tcl
###############################################
# ICC2 电源域物理实现
###############################################

# 1. 读入综合网表和UPF
read_verilog top_synth.v
link_design top
load_upf top.upf
commit_upf

# 2. 初始化Floorplan
initialize_floorplan \
    -die_area {0 0 5000 5000} \
    -core_area {50 50 4950 4950} \
    -core_utilization 0.7

# ============================================
# 电源域区域规划
# ============================================

# 创建电压区域 (Voltage Area)
create_voltage_area \
    -power_domain PD_CPU \
    -coordinate {100 100 2400 2400} \
    -guard_band_x 10 \
    -guard_band_y 10

create_voltage_area \
    -power_domain PD_GPU \
    -coordinate {2500 100 4900 2400} \
    -guard_band_x 10 \
    -guard_band_y 10

create_voltage_area \
    -power_domain PD_MODEM \
    -coordinate {100 2500 2400 4900} \
    -guard_band_x 10 \
    -guard_band_y 10
```

### 10.5.2 电源网络设计

```tcl
###############################################
# 电源网络 (Power Grid) 设计
###############################################

# ============================================
# 全局电源环 (Power Ring)
# ============================================

# 顶层电源环
create_pg_ring_pattern ring_top \
    -horizontal_layer M9 \
    -horizontal_width 3.0 \
    -horizontal_spacing 1.0 \
    -vertical_layer M10 \
    -vertical_width 3.0 \
    -vertical_spacing 1.0

set_pg_strategy ring_strategy_top \
    -core \
    -pattern {{name: ring_top} {nets: {VDD_AON VSS}}}

compile_pg -strategies ring_strategy_top

# ============================================
# 域内电源条 (Power Stripe)
# ============================================

# CPU域电源条
create_pg_stripe_pattern stripe_cpu \
    -direction vertical \
    -layer M8 \
    -width 1.5 \
    -spacing 0.5 \
    -pitch 40

set_pg_strategy stripe_strategy_cpu \
    -voltage_areas PD_CPU \
    -pattern {{name: stripe_cpu} {nets: {VDD_CPU_SW VSS}}}

compile_pg -strategies stripe_strategy_cpu

# ============================================
# 标准单元行电源轨 (Followpin)
# ============================================

create_pg_std_cell_conn_pattern \
    std_cell_rail \
    -layers {M1}

set_pg_strategy std_cell_strategy \
    -core \
    -pattern {{name: std_cell_rail} \
              {nets: {VDD_AON VSS}} \
              {parameters: {M1: {width: 0.1}}}}

compile_pg -strategies std_cell_strategy
```

### 10.5.3 电源开关布局

```tcl
###############################################
# 电源开关 (Power Switch) 布局
###############################################

# 方式1：链式布局 (Daisy Chain)
create_power_switch_array \
    -power_switch SW_CPU \
    -orientation {R0} \
    -direction horizontal \
    -target_voltage_area PD_CPU

# 方式2：网格式布局 (Grid)
# 通常在大面积域中使用
set_power_switch_strategy \
    -power_switch SW_GPU \
    -style grid \
    -pitch {50 50} \
    -offset {25 25}

# 电源开关连接
connect_power_switch \
    -power_switch SW_CPU \
    -source_power_net VDD_CPU \
    -target_power_net VDD_CPU_SW

# 检查电源开关网络
check_pg_connectivity
check_pg_drc
```

### 10.5.4 隔离与电平转换单元放置

```tcl
###############################################
# 低功耗单元放置约束
###############################################

# 隔离单元放置在域边界
# ICC2 会自动根据 UPF 的 -location 参数放置

# 电平转换单元通常放在靠近目标域的位置
set_cell_location \
    -coordinates {boundary} \
    [get_cells -filter "ref_name =~ LS_*"]

# 保持寄存器替换
# 综合时已插入，物理实现时确认位置合理
report_retention_cell -physical

# 域间距检查
check_mv_design -physical
```

## 10.6 Innovus 电源域物理实现 (Cadence)

### 10.6.1 Innovus 低功耗物理实现

```tcl
###############################################
# Cadence Innovus 低功耗物理实现
###############################################

# 1. 读入设计
read_verilog top_synth.v
read_power_intent -1801 top.upf

# 2. Floorplan
floorPlan -d 5000 5000 50 50 50 50

# 3. 创建电源域区域
createPowerDomain -name PD_CPU \
    -area {100 100 2400 2400}
createPowerDomain -name PD_GPU \
    -area {2500 100 4900 2400}

# 4. 电源网络
# 全局电源环
addRing -type core_rings \
    -nets {VDD_AON VSS} \
    -layer {top M9 bottom M9 left M10 right M10} \
    -width 3.0 -spacing 1.0

# 电源条
addStripe -nets {VDD_CPU_SW VSS} \
    -layer M8 \
    -width 1.5 -spacing 0.5 -set_to_set_distance 40 \
    -area {100 100 2400 2400}

# 5. 电源开关
addPowerSwitch \
    -column -powerDomain PD_CPU \
    -leftOffset 5 -horizontalPitch 50

# 6. 连接
sroute -connect { corePin }

# 7. 检查
verifyPowerDomain
verifyConnectivity -type special
```

## 10.7 PrimeTime 多电压时序分析

### 10.7.1 多模多角 (MCMM) 设置

```tcl
###############################################
# PrimeTime 多电压域STA
###############################################

# 1. 读入设计
read_verilog top_final.v
read_upf top.upf
link_design top

# 2. 多角设置
# Corner: CPU高压 + GPU高压（性能模式）
create_scenario -name func_perf
set_operating_conditions \
    -max ss_0p99v_125c \
    -min ff_1p21v_m40c
set_voltage 1.1 -object_list {VDD_CPU}
set_voltage 1.0 -object_list {VDD_GPU}
set_voltage 0.9 -object_list {VDD_AON}

# Corner: CPU低压 + GPU关断（省电模式）
create_scenario -name func_lowpower
set_operating_conditions \
    -max ss_0p63v_125c
set_voltage 0.7 -object_list {VDD_CPU}
set_voltage 0.0 -object_list {VDD_GPU}  ;# GPU关断
set_voltage 0.9 -object_list {VDD_AON}

# 3. 时序约束
read_sdc top_constraints.sdc

# 4. 跨域路径约束
# 电平转换延迟建模
set_level_shifter_delay -rise 0.15 -fall 0.12 \
    [get_cells -filter "ref_name =~ LS_*"]

# 隔离单元延迟（关断模式下不分析）
set_case_analysis 1 [get_ports iso_cpu_en] \
    -scenario func_lowpower

# 5. 时序分析
update_timing
report_timing -scenarios {func_perf func_lowpower} \
    -max_paths 100
```

### 10.7.2 跨域路径分析

```tcl
# 分析跨电压域路径
report_timing \
    -from [get_pins -of [get_cells -hierarchical -filter \
           "power_domain == PD_CPU"]] \
    -to   [get_pins -of [get_cells -hierarchical -filter \
           "power_domain == PD_AON"]] \
    -max_paths 20 \
    -path_type full

# 检查电平转换路径
report_timing -through [get_cells -filter "ref_name =~ LS_*"] \
    -max_paths 50

# 检查隔离路径延迟
report_timing -through [get_cells -filter "ref_name =~ ISO_*"] \
    -max_paths 50
```

## 10.8 PrimeTime PX 功耗签核

### 10.8.1 功耗分析流程

```tcl
###############################################
# PTPX 功耗签核分析
###############################################

# 1. 读入设计
read_verilog top_final.v
link_design top
read_upf top.upf

# 2. 读入寄生参数
read_parasitics top.spef

# 3. 读入时序约束
read_sdc top.sdc

# 4. 设置开关活动性
# 方式A：从仿真波形读取
read_saif top_sim.saif -strip_path testbench/dut

# 方式B：手动设置默认翻转率
set_switching_activity -static_probability 0.5 \
    -toggle_rate 0.1 \
    -type inputs

# 方式C：从VCD读取
read_vcd top_sim.vcd -strip_path testbench/dut

# 5. 执行功耗分析
update_power

# 6. 报告
report_power -verbose \
    -hierarchy \
    > rpt/power_signoff.rpt

# 各电源域功耗
report_power -power_domain {PD_CPU PD_GPU PD_MODEM PD_AON} \
    > rpt/power_by_domain.rpt

# 逐模块功耗
report_power -hierarchy -levels 3 \
    > rpt/power_hierarchy.rpt
```

### 10.8.2 功耗报告解读

```
Power Report (典型输出):
══════════════════════════════════════════════════════
Power Domain: PD_CPU
──────────────────────────────────────────────────────
  Internal Power    =  145.23 mW  (42.3%)
  Switching Power   =  132.56 mW  (38.6%)
  Leakage Power     =   65.78 mW  (19.1%)
  ──────────────────────────────────
  Total Power       =  343.57 mW  (100%)

  Clock Network     =   89.34 mW  (26.0%)  ← 时钟网络功耗占比大
  Register          =   78.45 mW  (22.8%)
  Combinational     =  110.23 mW  (32.1%)
  Memory            =   65.55 mW  (19.1%)
══════════════════════════════════════════════════════

Multi-Vt Distribution:
──────────────────────────────────────────────────────
  HVT Cells    =  15234  (78.5%)  ← 目标 > 80%
  SVT Cells    =   3456  (17.8%)
  LVT Cells    =    723  ( 3.7%)
──────────────────────────────────────────────────────
```

### 10.8.3 功耗优化迭代

```tcl
# 基于PTPX分析结果的优化迭代

# 1. 时钟功耗过高 → 增加时钟门控
# 回到DC/ICC2增加CG

# 2. 漏电功耗过高 → 增加HVT比例
# DC中: set_multi_vt_constraint -lvt_percentage 5

# 3. 特定模块功耗过高 → 定向优化
report_power -hierarchy -levels 5 \
    -filter "total_power > 10mW"

# 4. 信号翻转率异常 → 检查设计
report_switching_activity \
    -toggle_rate_sort descending \
    -max_objects 100
```

## 10.9 Voltus 功耗分析 (Cadence)

### 10.9.1 Voltus 功耗分析流程

```tcl
###############################################
# Cadence Voltus 功耗分析
###############################################

# 1. 读入设计
read_design top_final.v
read_power_intent -1801 top.upf

# 2. 寄生参数
read_spef top.spef

# 3. 活动性
read_activity_file top.saif -format SAIF

# 4. 功耗分析
set_power_analysis_mode \
    -method static \
    -corner max

report_power -out_dir rpt/power \
    -hierarchy all

# 5. IR-Drop 分析 (Voltus-Fi)
set_pg_analysis_mode \
    -accuracy high \
    -enable_static_ir true \
    -enable_dynamic_ir true

# 静态IR-Drop
analyze_power_rail -type static \
    -net VDD_CPU \
    -output_dir rpt/ir_drop_static

# 动态IR-Drop
analyze_power_rail -type dynamic \
    -net VDD_CPU \
    -vcd top.vcd \
    -output_dir rpt/ir_drop_dynamic
```

## 10.10 RedHawk/Voltus-Fi IR-Drop 分析

### 10.10.1 IR-Drop 分析流程

```
IR-Drop分析流程:

     ┌──────────────────────┐
     │  输入数据准备         │
     │  ├── 网表 + DEF      │
     │  ├── 寄生参数 (SPEF) │
     │  ├── 功耗数据 (SAIF)  │
     │  └── 电源网络 (PG)    │
     └──────────┬───────────┘
                │
     ┌──────────▼───────────┐
     │  静态 IR-Drop 分析    │
     │  ├── 平均电流分布     │
     │  ├── 电压降分布图     │
     │  └── 违反点标记       │
     └──────────┬───────────┘
                │
     ┌──────────▼───────────┐
     │  动态 IR-Drop 分析    │
     │  ├── 瞬态电流波形     │
     │  ├── 最差情况场景     │
     │  └── 热点识别         │
     └──────────┬───────────┘
                │
     ┌──────────▼───────────┐
     │  EM (电迁移) 分析     │
     │  ├── 电流密度检查     │
     │  └── 寿命评估         │
     └──────────┬───────────┘
                │
     ┌──────────▼───────────┐
     │  优化与修复           │
     │  ├── 加宽电源条       │
     │  ├── 增加VIA          │
     │  ├── 添加去耦电容     │
     │  └── 调整单元放置     │
     └──────────────────────┘
```

### 10.10.2 IR-Drop 标准与修复

```
IR-Drop 目标（典型值）:

┌──────────────────┬──────────────────┬──────────────────┐
│ 分析类型         │ 目标             │ 限制             │
├──────────────────┼──────────────────┼──────────────────┤
│ 静态 IR-Drop     │ < 3% VDD        │ < 5% VDD        │
│ 动态 IR-Drop     │ < 8% VDD        │ < 10% VDD       │
│ 电迁移 (EM)      │ < 80% Jmax      │ < 100% Jmax     │
│ 去耦电容覆盖     │ > 15% 面积      │ > 10% 面积      │
└──────────────────┴──────────────────┴──────────────────┘
```

## 10.11 完整低功耗设计流程脚本

### 10.11.1 Makefile 驱动的完整流程

```makefile
# Low-Power Design Flow Makefile

# 变量定义
DESIGN     = mobile_soc
UPF_FILE   = upf/top.upf
SDC_FILE   = constraints/top.sdc
RTL_FILES  = $(wildcard rtl/*.v)

# 目标定义
.PHONY: all synth pnr sta power clean

all: synth pnr sta power

# 1. 低功耗综合
synth: $(RTL_FILES) $(UPF_FILE)
	@echo "=== Running Low-Power Synthesis ==="
	dc_shell -f scripts/dc_lp_synth.tcl \
	    -x "set DESIGN $(DESIGN); set UPF $(UPF_FILE)"

# 2. 物理实现
pnr: synth
	@echo "=== Running Physical Implementation ==="
	icc2_shell -f scripts/icc2_lp_pnr.tcl \
	    -x "set DESIGN $(DESIGN)"

# 3. 时序签核
sta: pnr
	@echo "=== Running Multi-Voltage STA ==="
	pt_shell -f scripts/pt_mv_sta.tcl

# 4. 功耗签核
power: pnr
	@echo "=== Running Power Sign-off ==="
	ptpx -f scripts/ptpx_power.tcl

# 5. IR-Drop
irdrop: power
	@echo "=== Running IR-Drop Analysis ==="
	redhawk -f scripts/redhawk_ir.tcl

clean:
	rm -rf work/ rpt/ logs/
```

## 10.12 工具间数据传递

### 10.12.1 关键文件格式

| 文件类型 | 格式 | 源工具 | 目标工具 | 内容 |
|----------|------|--------|----------|------|
| 网表 | Verilog | DC/Genus | ICC2/Innovus | 门级网表 |
| 约束 | SDC | 手写/DC | 全流程 | 时序约束 |
| 电源意图 | UPF | 手写 | 全流程 | 低功耗策略 |
| 物理数据 | DEF | ICC2/Innovus | PT/PTPX | 布局布线 |
| 寄生参数 | SPEF | StarRC/QRC | PT/PTPX | RC参数 |
| 活动性 | SAIF/VCD | VCS/Xcelium | PTPX/Voltus | 信号翻转 |
| 功耗数据 | 内部格式 | PTPX/Voltus | RedHawk | 功耗分布 |

### 10.12.2 UPF 在各阶段的演进

```
UPF文件在设计流程中的演进:

Golden UPF (手写)
    │
    ├──► DC/Genus 读入
    │    └── 自动插入低功耗单元
    │         └── 输出: 更新后的网表 + supplemental UPF
    │
    ├──► ICC2/Innovus 读入
    │    └── 物理实现
    │         ├── 电源开关布局
    │         ├── 电源网络连接
    │         └── 输出: 物理信息补充到UPF
    │
    └──► PT/PTPX 读入
         └── 签核分析
              ├── 多电压时序验证
              └── 功耗准确度验证
```

## 10.13 常见问题与解决方案

### 10.13.1 综合阶段

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| UPF 读入失败 | 语法错误或版本不兼容 | 检查 UPF 版本，使用 `check_mv_design` |
| 隔离单元未插入 | 缺少库单元映射 | 确认库中有对应的隔离单元 |
| 时钟门控率低 | `minimum_bitwidth` 设置过大 | 降低阈值，检查编码风格 |
| LVT 比例过高 | 时序压力大 | 放松约束或增加流水级 |

### 10.13.2 物理实现阶段

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 电源域DRC违反 | Guard band不足 | 增加域间间距 |
| IR-Drop超标 | 电源网格密度不够 | 增加电源条宽度/密度 |
| 电源开关面积大 | 开关尺寸过大 | 优化开关链设计 |
| 跨域时序违反 | 电平转换延迟大 | 优化LS放置位置 |

### 10.13.3 签核阶段

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 功耗超预算 | 翻转率估计不准 | 用实际仿真 SAIF/VCD |
| 动态IR-Drop | 大量同时翻转 | 分散时钟边沿，加去耦电容 |
| EM违反 | 电流密度过高 | 加宽金属线/增加VIA |

## 10.14 本章小结

| 工具环节 | Synopsys | Cadence | 关键掌握 |
|----------|----------|---------|----------|
| 逻辑综合 | Design Compiler | Genus | UPF 读入、CG 插入、Multi-Vt 优化 |
| 物理实现 | ICC2 | Innovus | 电源域 Floorplan、PG 设计、开关布局 |
| 时序签核 | PrimeTime | Tempus | 多电压 STA、跨域路径分析 |
| 功耗签核 | PTPX | Voltus | SAIF/VCD 驱动功耗分析 |
| IR-Drop | RedHawk | Voltus-Fi | 静态/动态 IR-Drop、EM 检查 |

**下一章**将介绍低功耗仿真与验证的实际操作方法，包括 Power-Aware 仿真和形式化验证。
