# 第18章 低功耗时序约束与静态时序分析

## 18.1 引言

多电压域设计中的时序约束和静态时序分析 (STA) 比单一电压域复杂得多。跨域路径需要考虑电平转换延迟、隔离单元延迟、不同电压下的时序库选择等因素。本章系统介绍多电压域时序约束的完整方法论，以及跨域路径分析的实战技巧。

## 18.2 多电压域时序约束基础

### 18.2.1 多电压域时序挑战

```
多电压域时序挑战:

单电压域: 所有路径使用同一时序库
  ├── 一个PVT角即可
  └── 约束相对简单

多电压域:
  ├── 不同域使用不同电压的时序库
  ├── 跨域路径需要混合分析
  ├── 电平转换器引入额外延迟
  ├── 隔离单元引入额外延迟
  ├── DVFS导致动态电压变化
  └── 需要MCMM (多角多模) 分析

┌──────────────────────────────────────────────┐
│ PD_CPU (0.7V)          │ PD_AON (0.9V)      │
│                        │                     │
│  ┌──┐    ┌──┐    ┌────┤    ┌──┐    ┌──┐    │
│  │FF├───►│CL├───►│ LS ├───►│FF├───►│CL│    │
│  └──┘    └──┘    └────┤    └──┘    └──┘    │
│                        │                     │
│  0.7V库延迟     LS延迟 │  0.9V库延迟        │
│  (慢)           (额外) │  (快)               │
└──────────────────────────────────────────────┘
```

### 18.2.2 多模多角 (MCMM) 策略

```
MCMM (Multi-Corner Multi-Mode) 设置:

模式 (Mode) = 功能场景 + 电压配置
角 (Corner) = PVT (Process, Voltage, Temperature) 条件

典型MCMM矩阵:

Mode 1: Active_High_Perf
  CPU: 1.1V, 1.2GHz
  GPU: 1.0V, 800MHz
  AON: 0.9V
  → Corner: SS/-40°C, SS/125°C, FF/-40°C

Mode 2: Active_Low_Power
  CPU: 0.7V, 400MHz
  GPU: OFF
  AON: 0.9V
  → Corner: SS/-40°C, SS/125°C

Mode 3: Standby
  CPU: OFF (retention)
  GPU: OFF
  AON: 0.9V
  → Corner: SS/125°C (主要检查漏电相关时序)

Mode 4: DVFS_Transition
  CPU: 正在从1.1V→0.7V切换
  → 特殊约束: 切换期间时钟暂停

总场景数: 4 modes × 2-3 corners = 8-12 个分析场景
```

## 18.3 SDC 约束编写

### 18.3.1 基础时钟约束

```tcl
###############################################
# 多电压域 SDC 约束
###############################################

# ============================================
# 1. 时钟定义
# ============================================

# 主时钟
create_clock -name CLK_MAIN -period 2.0 \
    [get_ports clk_main]  ;# 500MHz

# CPU PLL 时钟
create_clock -name CLK_CPU -period 0.833 \
    [get_pins u_pll_cpu/clkout]  ;# 1.2GHz

# GPU PLL 时钟
create_clock -name CLK_GPU -period 1.25 \
    [get_pins u_pll_gpu/clkout]  ;# 800MHz

# 低速外设时钟
create_clock -name CLK_PERIPH -period 10.0 \
    [get_pins u_clk_div/clkout]  ;# 100MHz

# Always-On域时钟 (低频)
create_clock -name CLK_AON -period 31.25 \
    [get_pins u_osc_32k/clkout]  ;# 32kHz

# ============================================
# 2. 生成时钟
# ============================================

# CPU分频时钟
create_generated_clock -name CLK_CPU_DIV2 \
    -source [get_pins u_pll_cpu/clkout] \
    -divide_by 2 \
    [get_pins u_cpu_clk_div/clkout]

# ============================================
# 3. 时钟组关系
# ============================================

# 异步时钟组
set_clock_groups -asynchronous \
    -group {CLK_CPU CLK_CPU_DIV2} \
    -group {CLK_GPU} \
    -group {CLK_PERIPH} \
    -group {CLK_AON}

# 注意: 同源时钟之间是同步关系，需要正确建模
```

### 18.3.2 跨域路径约束

```tcl
###############################################
# 跨域路径约束
###############################################

# ============================================
# 异步跨域路径 (需要同步器)
# ============================================

# 方式1: 使用 set_false_path (不分析此路径)
set_false_path -from [get_clocks CLK_CPU] \
               -to   [get_clocks CLK_AON]
set_false_path -from [get_clocks CLK_AON] \
               -to   [get_clocks CLK_CPU]

# 方式2: 使用 set_max_delay (约束同步器延迟)
# 适用于需要限制同步延迟的场景
set_max_delay 3.0 \
    -from [get_clocks CLK_CPU] \
    -to   [get_clocks CLK_PERIPH] \
    -datapath_only  ;# 忽略时钟偏斜

# ============================================
# 电平转换器路径约束
# ============================================

# 电平转换器延迟约束
# LS单元有额外延迟，需要在时序分析中考虑

# 方式1: 库中已建模LS延迟 (推荐)
# → 无需额外约束, STA自动考虑

# 方式2: 手动设置LS延迟 (如库中不含)
set_data_check -rise -from [get_pins LS_*/A] \
    -to [get_pins LS_*/Y] -setup 0.15
set_data_check -fall -from [get_pins LS_*/A] \
    -to [get_pins LS_*/Y] -setup 0.12

# ============================================
# 隔离单元路径约束
# ============================================

# 隔离使能信号约束 (来自AON域)
# 隔离信号必须在数据路径之前稳定
set_multicycle_path 2 -setup \
    -from [get_pins u_pmu/iso_cpu_en_reg/Q]

# 隔离数据路径 (关断模式下不分析)
# 使用case analysis模拟关断模式
# set_case_analysis 1 [get_pins u_pmu/iso_cpu_en]
```

### 18.3.3 DVFS 切换时序约束

```tcl
###############################################
# DVFS 切换相关时序约束
###############################################

# DVFS切换期间的时钟约束

# 方式1: 切换期间时钟暂停
# 假设DVFS切换时CPU时钟停止
set_false_path -from [get_clocks CLK_CPU] \
    -to [get_clocks CLK_CPU] \
    -comment "DVFS transition, clock stopped"
# 注意: 这只在DVFS_Transition mode下设置

# 方式2: 切换期间频率降低
# 使用最低频率约束
create_clock -name CLK_CPU_DVFS -period 5.0 \
    [get_pins u_pll_cpu/clkout] \
    -add  ;# DVFS切换期间的保守约束

# ============================================
# 每个OPP的独立约束 (在MCMM中)
# ============================================

# OPP_HIGH: 1.2GHz @ 1.1V
# (使用1.1V库)
create_scenario -name opp_high
set_operating_conditions ss_1p1v_125c
create_clock -name CLK_CPU -period 0.833 \
    [get_pins u_pll_cpu/clkout]

# OPP_LOW: 400MHz @ 0.7V
# (使用0.7V库)
create_scenario -name opp_low
set_operating_conditions ss_0p7v_125c
create_clock -name CLK_CPU -period 2.5 \
    [get_pins u_pll_cpu/clkout]
```

## 18.4 跨域路径时序分析

### 18.4.1 跨域路径类型

```
跨域路径分类:

类型1: 同步跨域 (同源不同频)
  ├── 例: CPU时钟(1.2GHz) → CPU/2(600MHz)
  ├── 分析: 需要正确的multicycle path约束
  └── 工具可以自动处理(如果时钟关系正确)

类型2: 异步跨域 (不同源)
  ├── 例: CPU域 → 外设域 (不同PLL)
  ├── 分析: 需要同步器, set_false_path
  └── 同步器本身需要meta-stability分析

类型3: 跨电压域 (不同电压)
  ├── 例: CPU(0.7V) → AON(0.9V)
  ├── 分析: 需要电平转换器, 混合库分析
  └── 发送端和接收端使用不同PVT角

类型4: 跨域+跨电压 (最复杂)
  ├── 例: CPU(0.7V, 400MHz) → GPU(0.8V, 600MHz)
  ├── 分析: 需要LS + 同步器 + 混合库
  └── 需要仔细的MCMM设置
```

### 18.4.2 跨域路径分析实例

```tcl
# 分析从CPU域到AON域的跨域路径

# 路径: CPU_FF → 组合逻辑 → LS → ISO → AON_FF

# 1. 发送端时序 (CPU域, 0.7V)
# 使用0.7V SS库
# Tclk-q (CPU_FF) = 0.35ns (0.7V下较慢)
# Tlogic (组合) = 0.50ns

# 2. 电平转换延迟
# TLS = 0.15ns (low-to-high)

# 3. 隔离单元延迟 (使用AON供电)
# TISO = 0.10ns

# 4. 接收端时序 (AON域, 0.9V)
# 使用0.9V SS库
# Tsetup (AON_FF) = 0.08ns (0.9V下较快)

# 总路径延迟:
# 0.35 + 0.50 + 0.15 + 0.10 = 1.10ns
# 需满足: 1.10ns + Tsetup(0.08) < Tclk_aon

# PrimeTime报告:
report_timing \
    -from [get_cells u_cpu/data_out_reg] \
    -to   [get_cells u_aon/data_in_reg] \
    -path_type full_clock_expanded

# 典型报告输出:
# Startpoint: u_cpu/data_out_reg (CLK_CPU)
# Endpoint:   u_aon/data_in_reg (CLK_AON)
#
# Path Group: CLK_AON
# Path Type: max (setup)
#
# Point                          Delay    Cum
# ─────────────────────────────────────────
# clock CLK_CPU (rise edge)      0.000    0.000
# u_cpu/data_out_reg/Q (0.7V)   0.350    0.350
# u_cpu/logic_gate/Y (0.7V)     0.500    0.850
# u_ls_cpu_aon/Y (LS, crossing)  0.150    1.000
# u_iso_cpu/Y (ISO, 0.9V)       0.100    1.100
# u_aon/data_in_reg/D (0.9V)    0.000    1.100
# data arrival time                       1.100
#
# clock CLK_AON (rise edge)     31.250
# u_aon/data_in_reg/CK          0.100   31.350
# library setup time            -0.080   31.270
# data required time                     31.270
#
# slack (MET)                             30.170
```

## 18.5 时钟门控时序

### 18.5.1 ICG 单元时序

```
集成时钟门控 (ICG) 单元时序:

          CLK  ──────┐
                     │
          EN  ──►┌───▼───┐
                 │  Latch │──►┌─────┐
                 │  (neg) │   │ AND │──► GCLK
                 └────────┘──►└─────┘
                                 ▲
                                 │
                              CLK ──┘

时序要求:
  1. EN 的 setup time: EN必须在CLK下降沿前稳定
     Tsetup_EN = 需要在CLK↓前 Ts_latch 时间稳定
     
  2. EN 的 hold time: EN在CLK下降沿后保持
     Thold_EN = CLK↓后至少 Th_latch

  3. 毛刺避免: Latch在CLK高电平期间透明
     EN在CLK=1时变化不会产生GCLK毛刺

SDC约束:
  # ICG的EN输入约束
  set_clock_gating_check -setup 0.1 -hold 0.05 \
      [get_cells -hierarchical *ICG*]
```

### 18.5.2 多级时钟门控时序

```
多级时钟门控链:

CLK_ROOT ──► ICG_L1 ──► ICG_L2 ──► ICG_L3 ──► FF
              │ EN1       │ EN2       │ EN3
              
每级ICG引入:
  - 插入延迟: ~0.05-0.1ns
  - 时钟偏斜: 可能增加
  
约束:
  # 限制时钟门控级数
  set_max_clock_gating_levels 3
  
  # 确保CG链的时钟偏斜在限制内
  set_clock_uncertainty 0.050 -setup [get_clocks CLK_CPU]
  set_clock_uncertainty 0.030 -hold  [get_clocks CLK_CPU]
```

## 18.6 保持寄存器时序

### 18.6.1 Retention 寄存器时序要求

```
保持寄存器时序:

保存(Save)时序:
  ┌────────────────────────────────────────────┐
  │                                            │
  │  CLK ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─                   │
  │       └─┘ └─┘ └─┘ └─┘                     │
  │                                            │
  │  SAVE ─────────┐     ┌────────────         │
  │                └─────┘                     │
  │                ◄─Tw──►                     │
  │                                            │
  │  VDD  ═══════════════════╗                 │
  │                          ╚═════════        │
  │                          ◄─Tpd──►          │
  │                                            │
  │  要求: SAVE脉冲宽度 Tw > Tw_min            │
  │        SAVE在VDD关断前 Tpd > Thold_save    │
  └────────────────────────────────────────────┘

恢复(Restore)时序:
  ┌────────────────────────────────────────────┐
  │                                            │
  │  VDD  ═══════╔═════════════════════        │
  │              ║                             │
  │              ◄Tstable►                     │
  │                                            │
  │  RESTORE ──────────────┐     ┌─────        │
  │                        └─────┘             │
  │              ◄─Tsetup─►                    │
  │                                            │
  │  要求: VDD稳定后 Tsetup 才能触发RESTORE    │
  │        RESTORE脉冲宽度 > Tw_min             │
  └────────────────────────────────────────────┘

SDC约束:
  # Retention控制信号时序
  set_max_delay 10.0 \
      -from [get_pins u_pmu/ret_save_reg/Q] \
      -to   [get_pins -hierarchical RET_FF_*/SAVE]
```

## 18.7 电源开关时序

### 18.7.1 电源开关时序约束

```
电源开关时序:

Daisy-chain电源开关使能时序:

  PWR_EN ────┐
             │    ┌────┐  ┌────┐  ┌────┐  ┌────┐
             └───►│SW0 ├─►│SW1 ├─►│SW2 ├─►│SW3 │
                  └──┬─┘  └──┬─┘  └──┬─┘  └──┬─┘
                     │       │       │       │
              ACK0───┘ ACK1──┘ ACK2──┘ ACK3──┘

时序考虑:
  1. 开关链延迟: T_chain = N × T_sw_delay
     N=100 switches, T_sw=1ns → T_chain = 100ns
     
  2. 浪涌电流 (Inrush Current):
     所有开关同时打开 → 巨大浪涌 → IR-Drop
     解决: 串行打开 (daisy-chain) 分散浪涌
     
  3. ACK信号:
     最后一个开关的ACK → 表示供电完全建立
     PMU等待ACK后才继续后续操作

SDC约束:
  # 电源开关使能链延迟
  set_max_delay 200 \
      -from [get_pins u_pmu/pwr_en_reg/Q] \
      -to   [get_pins u_power_switch/ack]
```

## 18.8 STA 实战技巧

### 18.8.1 多电压域 STA Checklist

```
多电压域STA检查清单:

□ 每个电压域使用正确PVT角的库
□ 跨域路径正确识别并约束
□ 电平转换器延迟正确建模
□ 隔离单元延迟正确建模  
□ 异步跨域路径设置false_path或max_delay
□ 时钟门控时序检查通过
□ DVFS各OPP点单独分析
□ 保持寄存器控制时序满足
□ 电源开关使能链时序满足
□ 所有corner的setup/hold都满足
□ 时钟偏斜在允许范围内
□ OCV (On-Chip Variation) derating正确设置
```

### 18.8.2 OCV 设置

```tcl
# 多电压域 OCV (On-Chip Variation) 设置

# 标称电压域 OCV
set_timing_derate -early 0.93 \
    -cell_delay -net_delay \
    [get_cells -hierarchical -filter "power_domain == PD_AON"]

set_timing_derate -late  1.07 \
    -cell_delay -net_delay \
    [get_cells -hierarchical -filter "power_domain == PD_AON"]

# 低电压域 OCV (变异更大)
set_timing_derate -early 0.88 \
    -cell_delay -net_delay \
    [get_cells -hierarchical -filter "power_domain == PD_CPU"]

set_timing_derate -late  1.12 \
    -cell_delay -net_delay \
    [get_cells -hierarchical -filter "power_domain == PD_CPU"]

# 注意: 低电压域的OCV derating更大
# 因为低电压下工艺变异对延迟的影响更显著
```

## 18.9 本章小结

| 主题 | 关键要点 |
|------|----------|
| MCMM | 多模式(功能场景) × 多角(PVT) 的完整分析矩阵 |
| 跨域约束 | false_path/max_delay/multicycle 的正确使用 |
| LS时序 | 电平转换器引入额外延迟，需要在库中正确建模 |
| CG时序 | ICG的enable setup/hold约束，多级CG偏斜控制 |
| Retention时序 | save/restore脉冲宽度和相对于电源开关的时序关系 |
| OCV | 低电压域需要更大的derating因子 |

**下一章**将介绍电源完整性分析方法。
