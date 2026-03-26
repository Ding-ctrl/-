# 第六阶段：EDA 工具实战（详细版）

> 本文档是[芯片低功耗设计完整学习指南](../low_power_design_learning_guide.md)第六阶段的深入展开，覆盖完整的 EDA 工具命令参考、调试技巧和常见问题解决方案。

---

## 目录

- [1. Synopsys 工具链详解](#1-synopsys-工具链详解)
- [2. Cadence 工具链详解](#2-cadence-工具链详解)
- [3. Siemens (Mentor) 工具链](#3-siemens-mentor-工具链)
- [4. 工具间数据流与协同](#4-工具间数据流与协同)
- [5. 常见问题与调试技巧](#5-常见问题与调试技巧)
- [6. 低功耗设计完整 Makefile](#6-低功耗设计完整-makefile)

---

## 1. Synopsys 工具链详解

### 1.1 VCS 低功耗仿真完整指南

#### 编译和运行命令

```bash
# ══════════════════════════════════════════════════════
# VCS UPF-aware 仿真完整流程
# ══════════════════════════════════════════════════════

# 步骤1: 编译
vcs -full64 -sverilog \
    -f rtl_filelist.f \
    -f tb_filelist.f \
    -upf top.upf \
    -power_top_module top \
    -power=smdb+coverage+verbose \
    -timescale=1ns/1ps \
    +define+UPF_SIM \
    -debug_access+all \
    -o simv \
    -l compile.log \
    2>&1 | tee vcs_compile.log

# 步骤2: 运行仿真
./simv \
    +fsdbfile+dump.fsdb \
    +UVM_TESTNAME=power_gating_test \
    -l sim.log \
    2>&1 | tee vcs_sim.log

# 步骤3: 生成 SAIF (用于功耗分析)
./simv \
    +vcs+saif_file=top.saif \
    +UVM_TESTNAME=typical_workload_test \
    -l saif_sim.log
```

#### VCS 低功耗仿真选项详解

```bash
# -power 选项详解:

# 基础选项
-power=smdb           # 生成 Supply Monitor Database (查看电源状态)
-power=coverage       # 生成低功耗覆盖率
-power=verbose        # 详细的低功耗日志输出

# X 传播控制
-power=xprop_config=xprop.cfg  # 使用配置文件控制 X 传播
# xprop.cfg 内容示例:
# xprop_mode = d    # default: 正常X传播
# xprop_mode = v    # vmerge: 更精确的X传播
# xprop_mode = c    # custom: 自定义

# 高级选项
-power=ring_check     # 检查供电环路
-power=iso_check      # 检查隔离策略完整性
-power=ret_check      # 检查Retention配置
-power=domain_check   # 检查域定义完整性

# SAIF 生成
+vcs+saif_file=name.saif        # 指定 SAIF 输出文件
+vcs+saif_start+<time>          # 开始采集时间
+vcs+saif_stop+<time>           # 停止采集时间
```

#### VCS 仿真中的低功耗调试

```bash
# 使用 DVE/Verdi 查看低功耗状态

# 在 Verdi 中:
# 1. 打开波形窗口
# 2. Signal → Add Power Aware Signals
#    → 显示各 Supply Net 的状态 (ON/OFF)
#    → 显示 Isolation/Retention 控制信号
# 3. 观察 X 值的出现和传播
# 4. 检查 Supply Monitor 视图

# 在仿真代码中检查电源状态:
# $supply_state("VDD_CPU_sw")  → 返回 "FULL_ON" 或 "OFF"
# $is_supply_on("VDD_CPU_sw")  → 返回 1 或 0
```

### 1.2 Design Compiler 低功耗综合进阶

#### DC 低功耗报告命令全集

```tcl
# ══════════════════════════════════════════════════════
# DC 低功耗报告命令详解
# ══════════════════════════════════════════════════════

# 1. 功耗报告
report_power                            ;# 总功耗摘要
report_power -hierarchy -levels 5       ;# 层次化功耗
report_power -cell_power               ;# 单元级功耗
report_power -net                       ;# 网络级功耗
report_power -groups {clock_network register combinational memory io}  ;# 分组
report_power -verbose                   ;# 详细报告
report_power -analysis_effort high      ;# 高精度分析

# 2. Clock Gating 报告
report_clock_gating                    ;# CG 摘要
report_clock_gating -detail            ;# CG 详情
report_clock_gating -ungated           ;# 未门控寄存器

# 3. Multi-Vt 报告
report_threshold_voltage_group         ;# Vt 分组统计
report_cell -threshold_voltage_group LVT  ;# LVT 单元列表

# 4. 操作数隔离报告
report_operand_isolation               ;# 操作数隔离摘要

# 5. Power Domain 报告
report_power_domain -all               ;# 所有域信息
report_power_domain PD_CPU             ;# 特定域

# 6. UPF 策略报告
report_upf_objects                     ;# 所有 UPF 对象
report_isolation_cell                  ;# 隔离单元
report_level_shifter_cell              ;# 电平转换器
report_retention_cell                  ;# 保持寄存器
report_power_switch                    ;# 电源开关
```

### 1.3 PrimeTime PX 进阶

#### 多场景功耗分析

```tcl
# ══════════════════════════════════════════════════════
# PTPX 多场景功耗分析
# ══════════════════════════════════════════════════════

# 场景1: 典型工作负载 (Average Power)
read_saif typical_workload.saif -strip_path tb/u_dut
update_power
report_power > rpt/power_typical.rpt

# 场景2: 峰值功耗 (Peak Power)
read_vcd peak_activity.vcd -strip_path tb/u_dut
set_power_analysis_options -waveform_interval 10ns
update_power
report_power > rpt/power_peak.rpt

# 场景3: 待机功耗 (Standby Power)
read_saif standby.saif -strip_path tb/u_dut
update_power
report_power > rpt/power_standby.rpt

# 场景4: 无仿真数据（默认翻转率估算）
reset_switching_activity
set_switching_activity -static_probability 0.5 \
    -toggle_rate 0.1 -type inputs
update_power
report_power > rpt/power_estimated.rpt
```

### 1.4 VC LP (Verification Compiler Low Power)

```bash
# ══════════════════════════════════════════════════════
# VC LP: Synopsys 的低功耗规则检查工具
# ══════════════════════════════════════════════════════

# 运行 VC LP
vc_lp \
    -f rtl_filelist.f \
    -upf top.upf \
    -top top \
    -rule_file lp_rules.tcl \
    -l vc_lp.log

# 检查规则包括:
# - 每个可关断域的输出都有 Isolation
# - 跨域信号都有 Level Shifter
# - Retention 覆盖了需要保持的寄存器
# - Power Switch 控制信号在 Always-On 域
# - PST 涵盖所有合法状态组合
# - Save/Restore 时序在正确的顺序
```

---

## 2. Cadence 工具链详解

### 2.1 Xcelium 低功耗仿真完整指南

```bash
# ══════════════════════════════════════════════════════
# Xcelium UPF-aware 仿真
# ══════════════════════════════════════════════════════

# 编译+运行
xrun -sv \
    -f rtl_filelist.f \
    -f tb_filelist.f \
    -upf top.upf \
    -uvmhome $UVM_HOME \
    -lowpower \
    -lps_verbose \
    -lps_iso_check \
    -lps_ret_check \
    -lps_supply_check \
    -access +rwc \
    -timescale 1ns/1ps \
    +UVM_TESTNAME=power_gating_test \
    -l xrun.log

# Xcelium 低功耗选项详解:
# -lowpower            : 启用低功耗仿真模式
# -lps_verbose         : 详细低功耗日志
# -lps_iso_check       : 检查隔离策略
# -lps_ret_check       : 检查Retention策略
# -lps_supply_check    : 检查供电网络
# -lps_1801            : 强制使用 IEEE 1801 语义
# -lps_iso_x_on_corrupt : 隔离不正确时输出X
# -lps_ret_x_on_corrupt : Retention不正确时输出X

# 生成 SAIF
xrun ... -write_saif top.saif -saif_scope top
```

### 2.2 Cadence Voltus 功耗分析

```tcl
# ══════════════════════════════════════════════════════
# Voltus 功耗分析完整脚本
# ══════════════════════════════════════════════════════

# 读入设计
read_design -netlist ../pnr/top.v \
            -def ../pnr/top.def

# 读入工艺文件
read_liberty ../lib/tt_0p9v_25c.lib

# 读入寄生
read_spef ../pnr/top.spef

# 读入约束
read_sdc ../pnr/top.sdc

# 读入翻转率
read_activity_file -format SAIF ../sim/top.saif \
    -scope top

# 设置功耗分析模式
set_power_analysis_mode -method static \
    -corner_based true \
    -analysis_view default_view

# 运行分析
report_power -out_dir rpt/voltus_power \
    -report_prefix top

# 分层次报告
report_power -hierarchy all \
    -out_file rpt/power_hierarchy.rpt

# IR Drop 分析
set_rail_analysis_mode -method dynamic
set_rail_analysis_domain -name PD_CPU \
    -power_net VDD_CPU \
    -ground_net VSS

analyze_rail -results_dir rpt/ir_drop

# 生成 IR Drop 地图
report_rail -type vcd_based \
    -format png \
    -output rpt/ir_drop_map
```

### 2.3 Conformal Low Power (CLP)

```tcl
# ══════════════════════════════════════════════════════
# Conformal Low Power: 低功耗等价性验证
# ══════════════════════════════════════════════════════

# 读入 Golden (RTL)
read_hdl -golden -sv ../rtl/*.sv
read_power_intent -golden -1801 ../upf/top.upf
elaborate -golden top

# 读入 Revised (综合后网表)
read_hdl -revised ../synth/top_synth.v
read_power_intent -revised -1801 ../synth/top_synth.upf
elaborate -revised top

# 映射
map_key_points

# 低功耗检查
check_low_power -all

# 等价性检查
verify

# 报告
report_verify
report_low_power
```

---

## 3. Siemens (Mentor) 工具链

### 3.1 Questa Power Aware (QPA)

```bash
# ══════════════════════════════════════════════════════
# Questa Power Aware 仿真
# ══════════════════════════════════════════════════════

# 编译
vlog -sv +acc ../rtl/*.sv ../tb/*.sv

# 仿真 (带 UPF)
vsim -t 1ns -L work \
    -pa_upf top.upf \
    -pa_top /tb/u_dut \
    -pa_genrpt \
    -pa_checks all \
    +UVM_TESTNAME=power_gating_test \
    work.tb_top

# QPA 选项:
# -pa_upf <file>     : 指定 UPF 文件
# -pa_top <path>     : 指定 power aware top module
# -pa_genrpt         : 生成低功耗报告
# -pa_checks all     : 启用所有低功耗检查
# -pa_checks iso     : 只检查隔离
# -pa_checks ret     : 只检查 Retention
# -pa_checks ls      : 只检查 Level Shifter

# QPA 报告
# qpa_report.html - 包含:
# - Power Domain 定义
# - Isolation/Retention/Level Shifter 策略
# - 违规检查结果
# - 覆盖率统计
```

---

## 4. 工具间数据流与协同

### 4.1 完整低功耗设计数据流

```
┌─────────────────────────────────────────────────────────────────────┐
│                    低功耗设计完整数据流                                │
│                                                                      │
│  RTL + UPF (v1.0)                                                   │
│      │                                                               │
│      ├──→ VCS/Xcelium/Questa ──→ 功能验证 + SAIF/VCD               │
│      │    (UPF-aware 仿真)                                          │
│      │                                                               │
│      ├──→ VC LP / SpyGlass LP ──→ UPF lint 报告                    │
│      │    (低功耗规则检查)                                           │
│      │                                                               │
│      ├──→ PowerArtist / Joules ──→ RTL 功耗预估报告                 │
│      │    (RTL 功耗预估)                                            │
│      │                                                               │
│      ▼                                                               │
│  DC / Genus ──→ Netlist + UPF (v2.0) + SDC                         │
│  (综合)                                                              │
│      │                                                               │
│      ├──→ Formality / Conformal LP ──→ 等价性验证                   │
│      │    (低功耗形式验证)                                           │
│      │                                                               │
│      ├──→ VCS/Xcelium ──→ 门级仿真 + SAIF                          │
│      │    (门级 UPF 仿真)                                           │
│      │                                                               │
│      ▼                                                               │
│  ICC2 / Innovus ──→ DEF + SPEF + Netlist + UPF (v3.0)              │
│  (布局布线)                                                          │
│      │                                                               │
│      ├──→ PrimeTime ──→ 多电压域时序签核                             │
│      │    (STA)                                                      │
│      │                                                               │
│      ├──→ PTPX / Voltus ──→ 功耗签核报告                            │
│      │    (功耗分析)      ← SAIF/VCD                                 │
│      │                                                               │
│      ├──→ RedHawk / Voltus ──→ IR Drop 报告                         │
│      │    (电源完整性)                                               │
│      │                                                               │
│      ├──→ Calibre / PVS ──→ DRC/LVS 签核                           │
│      │    (物理验证)                                                 │
│      │                                                               │
│      ▼                                                               │
│  GDSII → Tapeout                                                    │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 UPF 在各工具间的演进

```
UPF 文件在设计流程中的演进:

UPF v1.0 (RTL 阶段):
  - Power Domain 定义
  - Supply Network 定义
  - Isolation/Retention/Level Shifter 策略
  - Power State Table
  - Power Switch 定义
  → 纯"意图"描述，不包含具体实现

UPF v2.0 (综合后):
  在 v1.0 基础上增加:
  - 具体 Isolation Cell 映射 (map_isolation_cell)
  - 具体 Level Shifter 映射 (map_level_shifter_cell)
  - 具体 Retention Cell 映射 (map_retention_cell)
  - 具体 Power Switch 映射 (map_power_switch)
  → 策略 + 具体单元映射

UPF v3.0 (布局布线后):
  在 v2.0 基础上增加:
  - 物理位置信息
  - Power Switch 连接细节
  - Supply Net 物理布线
  → 完整的物理实现信息
```

---

## 5. 常见问题与调试技巧

### 5.1 常见编译/仿真错误

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `UPF Error: Undefined supply net` | Supply Net 未定义或名称拼写错误 | 检查 `create_supply_net` |
| `UPF Error: No isolation for output` | 可关断域输出缺少隔离 | 添加 `set_isolation` |
| `UPF Error: Domain element not found` | `-elements` 中的实例名不存在 | 检查 RTL 中的实例名 |
| `Warning: X propagation detected` | 关断域 X 泄露到开启域 | 检查 Isolation 策略 |
| `Error: Retention cell not mapped` | Retention 策略没有映射到具体单元 | 检查综合后 UPF |
| `Error: Supply set mismatch` | Supply Set 定义不一致 | 检查层次化 UPF 中的连接 |
| `Warning: Level shifter missing` | 跨域信号缺少 Level Shifter | 添加 `set_level_shifter` |

### 5.2 功耗分析结果不准确的常见原因

```
功耗报告不准确的排查清单:

1. 翻转率信息问题:
   □ SAIF 采集时间是否足够长？(覆盖代表性场景)
   □ SAIF 的 strip_path 是否正确？
   □ 是否有信号没有翻转率信息？(使用默认值)
   □ VCD/SAIF 与网表是否匹配？

2. 时序/寄生信息问题:
   □ SPEF 是否来自最终布线结果？
   □ 工艺角是否匹配？(功耗分析通常用 TT 角)
   □ 温度设置是否正确？

3. 设计信息问题:
   □ Memory macro 是否有准确的功耗模型？
   □ IO pad 功耗是否包含？
   □ PLL/Analog 模块功耗是否手动添加？

4. 工具设置问题:
   □ analysis_effort 设置是否足够？
   □ 是否启用了正确的分析模式？
```

### 5.3 工具特定的调试命令

```tcl
# ══════════════════════════════════════════
# VCS 调试命令
# ══════════════════════════════════════════
# 在仿真中打印电源域状态
$display("CPU supply state: %s", $supply_state("VDD_CPU_sw"));

# 在 UPF 中添加调试回调
# (在 UPF 文件中添加)
# set_design_attributes -power_on_callback power_on_debug
# proc power_on_debug {domain} {
#     puts "Domain $domain powered on at time [info frame]"
# }


# ══════════════════════════════════════════
# DC 调试命令
# ══════════════════════════════════════════
# 检查为什么某个寄存器没有被 Clock Gating
report_clock_gating -ungated -detail

# 检查某个信号的 UPF 策略
get_attribute [get_ports sig_name] upf_*

# 检查 Power Domain 成员
report_power_domain PD_CPU -elements


# ══════════════════════════════════════════
# ICC2 调试命令
# ══════════════════════════════════════════
# 高亮显示 Power Domain
gui_highlight -color red [get_cells -of_objects [get_power_domains PD_CPU]]

# 检查 Isolation Cell 放置
report_placement_status -isolation

# 检查 Power Switch
report_power_switch sw_cpu -verbose
```

---

## 6. 低功耗设计完整 Makefile

```makefile
# ══════════════════════════════════════════════════════
# 低功耗设计流程 Makefile
# ══════════════════════════════════════════════════════

# 目录
RTL_DIR    = rtl
UPF_DIR    = upf
TB_DIR     = tb
SYNTH_DIR  = synth
PNR_DIR    = pnr
SIM_DIR    = sim
RPT_DIR    = rpt

# UPF 文件
UPF_FILE   = $(UPF_DIR)/top.upf

# 默认目标
.PHONY: all clean sim synth pnr power_analysis

all: sim synth power_analysis

# ──── UPF Lint 检查 ────
upf_lint:
	@echo "=== Running UPF Lint ==="
	vc_lp -f $(RTL_DIR)/filelist.f \
	    -upf $(UPF_FILE) \
	    -top top \
	    -l $(RPT_DIR)/upf_lint.log

# ──── RTL 仿真 (UPF-aware) ────
sim: upf_lint
	@echo "=== Running UPF-aware Simulation ==="
	cd $(SIM_DIR) && vcs -full64 -sverilog \
	    -f ../$(RTL_DIR)/filelist.f \
	    -f ../$(TB_DIR)/filelist.f \
	    -upf ../$(UPF_FILE) \
	    -power_top_module top \
	    -power=smdb+coverage \
	    +vcs+saif_file=top.saif \
	    -o simv && \
	./simv +UVM_TESTNAME=power_gating_test -l sim.log

# ──── 综合 ────
synth:
	@echo "=== Running Low-Power Synthesis ==="
	cd $(SYNTH_DIR) && dc_shell -f scripts/synth.tcl -l synth.log

# ──── 门级仿真 ────
gate_sim: synth
	@echo "=== Running Gate-Level Simulation ==="
	cd $(SIM_DIR) && vcs -full64 -sverilog \
	    ../$(SYNTH_DIR)/results/top_synth.v \
	    -f ../$(TB_DIR)/filelist.f \
	    -upf ../$(SYNTH_DIR)/results/top_synth.upf \
	    -power_top_module top \
	    +vcs+saif_file=top_gate.saif \
	    -o simv_gate && \
	./simv_gate +UVM_TESTNAME=typical_workload_test -l gate_sim.log

# ──── 功耗分析 ────
power_analysis: gate_sim
	@echo "=== Running Power Analysis ==="
	cd $(RPT_DIR) && pt_shell -f ../scripts/ptpx.tcl -l ptpx.log

# ──── 清理 ────
clean:
	rm -rf $(SIM_DIR)/simv* $(SIM_DIR)/csrc
	rm -rf $(SYNTH_DIR)/results
	rm -rf $(RPT_DIR)/*.rpt
```

---

> 返回 [主学习指南](../low_power_design_learning_guide.md) | 上一章 ← [低功耗实现详解](05_implementation.md) | 下一章 → [进阶与前沿方向详解](07_advanced.md)
