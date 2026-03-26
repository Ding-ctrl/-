# 第二阶段：低功耗架构设计（详细版）

> 本文档是[芯片低功耗设计完整学习指南](../low_power_design_learning_guide.md)第二阶段的深入展开，覆盖电压域划分、DVFS、Power Gating、Clock Gating 的完整设计细节。

---

## 目录

- [1. 电压域划分深入](#1-电压域划分深入)
- [2. DVFS 详细设计](#2-dvfs-详细设计)
- [3. Power Gating 详细设计](#3-power-gating-详细设计)
- [4. Clock Gating 详细设计](#4-clock-gating-详细设计)
- [5. Level Shifter 详细设计](#5-level-shifter-详细设计)
- [6. Isolation Cell 详细设计](#6-isolation-cell-详细设计)
- [7. Retention Register 详细设计](#7-retention-register-详细设计)
- [8. 总线低功耗设计详解](#8-总线低功耗设计详解)
- [9. 电源管理单元(PMU)架构](#9-电源管理单元pmu架构)
- [10. 实际 SoC 低功耗架构案例分析](#10-实际-soc-低功耗架构案例分析)

---

## 1. 电压域划分深入

### 1.1 Power Domain 划分原则

在 SoC 中划分 Power Domain 需要综合考虑以下因素：

```
划分决策矩阵：
┌──────────────┬───────────────┬────────────────────────────────┐
│ 考虑因素      │ 权重          │ 说明                           │
├──────────────┼───────────────┼────────────────────────────────┤
│ 功能独立性    │ ★★★★★        │ 功能耦合紧密的模块应在同一域    │
│ 使用频率      │ ★★★★         │ 不常用模块可独立关断            │
│ 性能需求差异  │ ★★★★         │ 性能需求差异大的模块可用不同电压  │
│ 面积开销      │ ★★★          │ 每增加一个域有额外面积成本       │
│ 时序约束      │ ★★★          │ 关键时序路径尽量不跨域          │
│ 验证复杂度    │ ★★            │ 域越多，验证场景越复杂           │
│ 外部供电能力  │ ★★            │ 受 PMIC 通道数限制              │
└──────────────┴───────────────┴────────────────────────────────┘
```

### 1.2 Power Domain 类型详解

| 类型 | 特征 | 电压控制 | 电源控制 | 典型应用 |
|------|------|---------|---------|---------|
| Always-On Domain | 始终上电，不可关断 | 可 DVFS | 否 | PMU、唤醒逻辑、RTC |
| Switchable Domain | 可完全关断 | 可 DVFS | 是 | GPU、DSP、Codec |
| Retention Domain | 可关断但保持状态 | 可 DVFS | 是 | CPU Core（保持 Cache） |
| Voltage-Scalable Domain | 只调电压，不关断 | DVFS | 否 | 高性能 CPU |

### 1.3 Power Domain 边界信号处理

每对有信号交互的 Power Domain 之间，都需要处理边界信号：

```
                    Domain A                   Domain B
               (VDD_A = 0.8V)             (VDD_B = 1.0V)
              ┌────────────────┐          ┌────────────────┐
              │                │          │                │
              │    Logic A     │──┐   ┌───│    Logic B     │
              │                │  │   │   │                │
              └────────────────┘  │   │   └────────────────┘
                                  │   │
                        ┌─────────▼───▼─────────┐
                        │   边界处理单元          │
                        │ ┌───────┐ ┌──────────┐ │
                        │ │Level  │ │Isolation │ │
                        │ │Shifter│ │Cell      │ │
                        │ └───────┘ └──────────┘ │
                        └───────────────────────┘

规则总结：
┌──────────────────────────────────────────────────────────────┐
│ A→B 方向：                                                    │
│   1. VDD_A ≠ VDD_B → 需要 Level Shifter                     │
│   2. Domain A 可关断 → 需要 Isolation Cell                    │
│   3. 条件1和2可同时满足 → 使用带隔离功能的 Level Shifter      │
│                                                               │
│ B→A 方向：                                                    │
│   1. VDD_B ≠ VDD_A → 需要 Level Shifter                     │
│   2. Domain B 可关断 → 需要 Isolation Cell                    │
│                                                               │
│ 双向信号：两端都需要处理                                       │
└──────────────────────────────────────────────────────────────┘
```

### 1.4 Domain 划分对面积的影响

```
每增加一个可关断的 Power Domain，增加的面积：
├── Power Switch 面积：约占该域面积的 5%~10%
├── Isolation Cell 面积：每个跨域输出信号一个，每个约 2~4 个标准单元大小
├── Level Shifter 面积：每个跨域信号一个，每个约 4~8 个标准单元大小
├── Retention Register 面积：比普通寄存器大 30%~50%（如需保持状态）
├── 电源网络额外布线面积：Power Ring, Power Stripe
└── 控制逻辑面积：PMU 中针对该域的控制逻辑

典型示例（一个中等复杂度的可关断域）：
原始面积：100K 门
Power Switch:   +5K~10K 门 (5%~10%)
Isolation:      +1K 门 (100个跨域信号 × 10门/个)
Level Shifter:  +1K 门
Retention Reg:  +5K 门 (假设30%的寄存器需要保持)
总额外面积:     +12K~17K 门 (12%~17% 面积开销)
```

---

## 2. DVFS 详细设计

### 2.1 DVFS 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                      DVFS 系统架构                               │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────────────┐  │
│  │  软件层       │    │  硬件控制层   │    │  电源/时钟层       │  │
│  │              │    │              │    │                    │  │
│  │ OS Governor  │───→│ DVFS         │───→│  PMIC/LDO         │  │
│  │ (Linux CPUfreq│   │ Controller   │    │  (电压调节)        │  │
│  │  framework)  │    │ (硬件状态机)  │    │                    │  │
│  │              │    │              │───→│  PLL/Clock Divider │  │
│  │ 工作负载监测  │    │ OPP 查找表   │    │  (频率调节)        │  │
│  │              │    │ 时序控制      │    │                    │  │
│  │ 温度监测     │    │ 完成中断      │    │  Power Domain      │  │
│  └──────────────┘    └──────────────┘    └───────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 OPP（Operating Performance Points）表

```
典型 ARM Cortex-A 系列 OPP 表：

┌─────────────────────────────────────────────────────────────┐
│  OPP Level  │  频率(MHz)  │  电压(V)  │  功耗(mW)  │  性能  │
├─────────────┼────────────┼──────────┼───────────┼────────┤
│  OPP_TURBO  │    2000    │   1.05   │    2500   │  100%  │
│  OPP_HIGH   │    1500    │   0.95   │    1400   │   75%  │
│  OPP_NOM    │    1000    │   0.85   │     700   │   50%  │
│  OPP_LOW    │     500    │   0.75   │     250   │   25%  │
│  OPP_MIN    │     200    │   0.65   │      60   │   10%  │
│  OPP_RET    │       0    │   0.50   │       5   │    0%  │
└─────────────┴────────────┴──────────┴───────────┴────────┘

注意：
- 电压和频率的关系不是线性的
- 每个 OPP 都经过 STA 签核验证
- 最低电压受 SRAM 最低工作电压限制
- OPP_RET 是 retention 模式，仅保持状态
```

### 2.3 DVFS 切换时序详解

#### 升频升压（Performance Up）

```
时间 ──→

电压:   V_low ─────────────┐
                            ╲  电压上升（t_voltage_ramp）
                             ╲─────── V_high ──────────
                            │←─────→│
                            t_ramp (通常 5~50 μs)

频率:   f_low ──────────────────────────┐
                                         │ 频率切换（需先等电压稳定）
        f_high ─────────────────────────────────────────
                                        │← t_lock →│
                                      PLL 锁定时间

步骤：
1. 软件请求升频升压
2. 硬件先命令 PMIC/LDO 升压
3. 等待电压稳定（需要等 t_ramp + t_settle）
4. 电压稳定后，切换 PLL 到高频
5. 等待 PLL 锁定
6. 发出完成中断
```

**关键**：必须**先升压后升频**，否则在低电压下运行高频率会导致时序违规甚至功能错误。

#### 降频降压（Performance Down）

```
时间 ──→

频率:   f_high ─────────┐
                         │ 先降频！
        f_low  ─────────────────────────────────────
                        │← t_switch →│

电压:   V_high ──────────────────────┐
                                      ╲  电压下降
                                       ╲───── V_low ──
                                      │←─────→│
                                      t_ramp

步骤：
1. 软件请求降频降压
2. 硬件先切换到低频时钟（或分频）
3. 频率切换完成后，命令降压
4. 等待电压稳定
5. 发出完成中断
```

**关键**：必须**先降频后降压**，道理同上。

### 2.4 DVFS Controller RTL 框架

```verilog
module dvfs_controller (
    input  wire        clk,
    input  wire        rst_n,

    // 软件接口
    input  wire [2:0]  target_opp,      // 目标 OPP level
    input  wire        dvfs_req,        // DVFS 请求
    output reg         dvfs_done,       // DVFS 完成
    output reg         dvfs_busy,       // DVFS 进行中

    // PMIC 接口
    output reg  [7:0]  pmic_voltage,    // 目标电压编码
    output reg         pmic_req,        // 电压调节请求
    input  wire        pmic_ack,        // 电压调节完成

    // PLL/Clock 接口
    output reg  [3:0]  pll_div,         // PLL 分频比
    output reg         pll_bypass,      // PLL bypass（切换时使用）
    output reg         clk_switch_req,  // 时钟切换请求
    input  wire        pll_locked,      // PLL 锁定状态

    // 中断
    output reg         dvfs_irq         // 完成中断
);

    // OPP 查找表
    reg [7:0]  opp_voltage_table [0:7];
    reg [3:0]  opp_freq_div_table [0:7];

    // 状态机
    localparam IDLE          = 4'd0;
    localparam COMPARE_OPP   = 4'd1;
    localparam VOLTAGE_UP    = 4'd2;  // 升压
    localparam WAIT_VOLT_UP  = 4'd3;  // 等待电压稳定
    localparam FREQ_UP       = 4'd4;  // 升频
    localparam WAIT_PLL_LOCK = 4'd5;  // 等待PLL锁定
    localparam FREQ_DOWN     = 4'd6;  // 降频
    localparam VOLTAGE_DOWN  = 4'd7;  // 降压
    localparam WAIT_VOLT_DN  = 4'd8;  // 等待电压稳定
    localparam DONE          = 4'd9;

    reg [3:0] state, next_state;
    reg [2:0] current_opp;
    reg       need_voltage_up;

    // 判断是升频还是降频
    always @(*) begin
        need_voltage_up = (opp_voltage_table[target_opp] > opp_voltage_table[current_opp]);
    end

    // 状态机主体
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:
                if (dvfs_req && target_opp != current_opp)
                    next_state = COMPARE_OPP;

            COMPARE_OPP:
                if (need_voltage_up)
                    next_state = VOLTAGE_UP;    // 升频场景：先升压
                else
                    next_state = FREQ_DOWN;     // 降频场景：先降频

            VOLTAGE_UP:
                next_state = WAIT_VOLT_UP;

            WAIT_VOLT_UP:
                if (pmic_ack)
                    next_state = FREQ_UP;

            FREQ_UP:
                next_state = WAIT_PLL_LOCK;

            WAIT_PLL_LOCK:
                if (pll_locked)
                    next_state = DONE;

            FREQ_DOWN:
                next_state = VOLTAGE_DOWN;      // 降频后立即降压

            VOLTAGE_DOWN:
                next_state = WAIT_VOLT_DN;

            WAIT_VOLT_DN:
                if (pmic_ack)
                    next_state = DONE;

            DONE:
                next_state = IDLE;
        endcase
    end

    // 输出逻辑（简化）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dvfs_busy    <= 1'b0;
            dvfs_done    <= 1'b0;
            current_opp  <= 3'd0;
        end else begin
            dvfs_done <= (state == DONE);
            dvfs_busy <= (state != IDLE);
            if (state == DONE)
                current_opp <= target_opp;
        end
    end

endmodule
```

### 2.5 电压调节器选择

| 类型 | 效率 | 纹波 | 面积 | 响应速度 | 适用场景 |
|------|------|------|------|---------|---------|
| 外部 DCDC | 85%~95% | 中 | 片外 | 慢(μs级) | 主电源 |
| 外部 LDO | 70%~85% | 低 | 片外 | 中(μs级) | 低噪声场景 |
| 片内 DCDC | 80%~90% | 中 | 大 | 快(ns~μs) | 快速DVFS |
| 片内 LDO | 60%~80% | 低 | 中 | 快(ns级) | per-core DVFS |
| Digital LDO | 50%~75% | 较高 | 小 | 快(ns级) | 细粒度调压 |

---

## 3. Power Gating 详细设计

### 3.1 Power Switch 设计

#### Header Switch vs Footer Switch

```
Header Switch (PMOS):           Footer Switch (NMOS):

   V_DD (全局)                     V_DD
     │                              │
   ┌─┤ PMOS Switch                  │
   │ │ (Sleep控制)              ┌───────┐
   │ V_DD_local                 │ Logic │
   │   │                        │       │
 ┌───────┐                     └───┬───┘
 │ Logic │                         │
 │       │                    V_SS_local
 └───┬───┘                      ┌─┤ NMOS Switch
     │                          │ │ (Sleep控制)
    GND                        GND (全局)

Header 优点: PMOS 漏电更低（同尺寸下），噪声更低
Header 缺点: PMOS 尺寸需更大（约2倍，因空穴迁移率低）
Footer 优点: NMOS 尺寸更小，面积节省
Footer 缺点: 地弹噪声(Ground Bounce)问题

业界趋势: Header Switch 更常用（噪声优势）
```

#### Power Switch 尺寸设计

```
设计步骤：
1. 估算域内峰值电流 I_peak
2. 确定允许的 IR Drop（通常 < 5% V_DD）
3. 计算所需 Switch 总导通电阻
   R_on_total = V_drop / I_peak = (5% × V_DD) / I_peak
4. 计算所需 Switch 数量
   N = R_on_single / R_on_total
5. 添加 20%~30% 余量

示例：
- 域内峰值电流: I_peak = 200mA
- V_DD = 0.9V, 允许 5% IR Drop = 45mV
- R_on_total = 45mV / 200mA = 0.225Ω
- 单个 Switch R_on = 5Ω
- 需要 N = 5 / 0.225 ≈ 23 个 Switch
- 加 30% 余量 → 30 个 Switch
```

#### Power Switch 菊花链控制（Daisy Chain）

```
为什么需要 Daisy Chain？
→ 如果所有 Switch 同时开启，会产生巨大的 Rush Current（浪涌电流）
→ Rush Current 会导致电源网络大幅波动，影响其他工作域
→ 解决方案：Switch 分组，逐组开启

控制信号传播：
      enable_in → [SW1] → [SW2] → [SW3] → ... → [SWn] → ack_out
                    ↓        ↓        ↓                ↓
                 VDD_local VDD_local VDD_local      VDD_local

开启时序：
        enable_in  ─────┐
                        │
        SW1 开启   ──────┐──
                         │ t_delay
        SW2 开启   ───────┐──
                          │ t_delay
        SW3 开启   ────────┐──
                           │
        ...                │
        SWn 开启   ─────────┐──
                            │
        ack_out    ──────────┐──  所有 Switch 开启完毕

Rush Current 控制：
无 Daisy Chain: I_rush = N × I_per_switch (可能数安培)
有 Daisy Chain: I_rush = 1 × I_per_switch (可控)
代价: 上电时间增加 (N-1) × t_delay
```

### 3.2 完整 Power Gating 时序（详细版）

```
信号时序图 (关断过程):

clk         ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─────
              └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘

pg_request  ───────┐                    (1. PMU发出关断请求)
                   └──────────────────────────────

clk_enable  ───────────┐                (2. 先关闭时钟，停止翻转)
                       └──────────────────────────

save_en     ──────────────┐    ┌──      (3. 触发 Retention Save)
                          └────┘        (一个脉冲)

iso_enable  ─────────────────────┐      (4. 使能输出隔离)
                                └───────────────

pg_enable   ────────────────────────┐   (5. 最后关断电源)
                                    └───────────────

VDD_local   ═══════════════════════════╲
                                        ╲_______ 0V

域内信号    ──valid─────────────────────X  XXXXXXX
                                        │← 变为 X →│

隔离输出    ──valid────────────────0000000000000000000
                                  │← 被钳位到 0 →│


信号时序图 (恢复过程):

pg_enable   ──────────┐                 (1. 首先恢复电源)
                      └──────────────────────────

VDD_local              ╱═══════════════════════════
             0V ──────╱
                      │← t_ramp →│ (电源稳定时间)

                      │← t_stable →│   (2. 等待电源稳定)

restore_en  ──────────────────────┐  ┌  (3. 触发 Retention Restore)
                                  └──┘

iso_enable  ─────────────────────────────┐  (4. 取消隔离)
                                         └─────────

clk_enable  ───────────────────────────────────┐  (5. 恢复时钟)
                                               └───────

pg_ack      ─────────────────────────────────────────┐  (6. 完成)
                                                     └──
```

### 3.3 Power Gating 的唤醒延迟分析

| 阶段 | 典型耗时 | 影响因素 |
|------|---------|---------|
| 电源恢复 (Power Ramp) | 0.5~10 μs | Switch 数量、Daisy Chain 级数、电容 |
| 电源稳定等待 | 0.1~1 μs | 电源网络RC、稳定标准 |
| Retention Restore | 1~2 时钟周期 | Restore 信号宽度 |
| 取消隔离 | 1 时钟周期 | 逻辑延迟 |
| 时钟恢复 | 0~几个周期 | PLL 是否需要重新锁定 |
| **总唤醒延迟** | **1~15 μs** | 取决于具体设计 |

**设计权衡**：
- 唤醒延迟 vs 功耗节省 → 需要 Break-Even Time 分析
- Break-Even Time = 进入/退出低功耗消耗的额外能量 / 每秒节省的功耗
- 只有空闲时间 > Break-Even Time 时，Power Gating 才有收益

---

## 4. Clock Gating 详细设计

### 4.1 Clock Gating 的层级

```
系统级 Clock Gating (最大收益)
├── PLL 关断 (无时钟输出)
│   └── 节省: PLL 本身功耗 + 所有下游功耗
├── 时钟树根部门控
│   └── 节省: 时钟树翻转功耗 + 所有下游逻辑功耗
│
模块级 Clock Gating (中等收益)
├── 子模块时钟门控
│   └── 节省: 子模块时钟树 + 内部逻辑功耗
│
寄存器级 Clock Gating (基础收益)
└── 单个/一组寄存器门控
    └── 节省: 寄存器翻转功耗
```

### 4.2 ICG（Integrated Clock Gating）单元详解

#### 为什么需要锁存器型 ICG

```
直接 AND 门控 (有毛刺风险):

clk     ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─
          └─┘ └─┘ └─┘ └─┘

enable  ────────┐
                └───────────

gated_clk ─┐ ┌─┐ ┌──────────   ← 正常
            └─┘ └─┘

如果 enable 在 clk=1 时变化:

clk     ─┐ ┌─┐ ┌─┐ ┌─
          └─┘ └─┘ └─┘

enable  ───────┐
               └────────────

gated_clk ─┐ ┌─┐ ┌┐ ┌──────   ← 产生毛刺脉冲！
            └─┘ └─┘└─┘
                   ↑
               glitch! 可能导致寄存器错误采样


锁存器型 ICG (无毛刺):

clk       ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─
            └─┘ └─┘ └─┘ └─┘

enable    ───────┐             (可以在任意时刻变化)
                 └────────────

latch_out ─────────────┐       (仅在 clk=0 时透明，采样 enable)
                       └──────

gated_clk ─┐ ┌─┐ ┌─────────   (安全，无毛刺)
            └─┘ └─┘
```

#### ICG 的标准单元实现

```verilog
// 工艺库中典型的 ICG 单元 (示意)
// 实际由 Foundry 提供优化过的标准单元

module CKLNQD1 (  // 示例名称: Clock Latch AND
    input  wire CP,   // Clock (正沿)
    input  wire E,    // Enable
    input  wire TE,   // Test Enable (DFT bypass)
    output wire Q     // Gated Clock Output
);
    reg latch_q;

    // 负电平锁存器
    always @(CP or E or TE) begin
        if (!CP)
            latch_q <= E | TE;
    end

    // AND 门
    assign Q = CP & latch_q;

endmodule
```

### 4.3 Clock Gating 效率评估

```
Clock Gating 效率 = (被门控的寄存器位数) / (总寄存器位数) × 100%

目标: > 90% (良好), > 95% (优秀)

报告示例 (Design Compiler report_clock_gating):
┌───────────────────────────────────────────────────────┐
│ Clock Gating Summary                                   │
├───────────────────────────────────────────────────────┤
│ Total registers:              50000                    │
│ Gated registers:              47500                    │
│ Ungated registers:             2500                    │
│ Clock gating efficiency:      95.0%                    │
│                                                        │
│ Number of ICG cells:           3200                    │
│ Average bitwidth per ICG:      14.8                    │
│                                                        │
│ Ungated register breakdown:                            │
│   Cannot be gated (no enable):  1500                   │
│   Below minimum bitwidth:        800                   │
│   Excluded by user:              200                   │
└───────────────────────────────────────────────────────┘

对于未门控的寄存器，应该检查:
1. 是否可以添加使能条件
2. 是否可以降低 minimum_bitwidth 阈值
3. 是否可以合并小组寄存器共享 ICG
```

### 4.4 时钟树功耗占比

```
在典型数字设计中，时钟树功耗占总功耗的比例：

┌──────────────────────────────────┐
│ 功耗分布 (典型 SoC)              │
│                                  │
│ 时钟树:       30%~50% ████████  │
│ 组合逻辑:     20%~30% █████     │
│ 寄存器(数据):  10%~20% ███      │
│ Memory:       10%~20% ███      │
│ IO:            5%~10% ██       │
└──────────────────────────────────┘

时钟树为什么功耗这么高？
- α = 1.0（每个周期翻转）
- 驱动大量负载（所有寄存器的时钟输入）
- Buffer 链级数多
- 连线长、电容大

→ 所以 Clock Gating 是最有效的低功耗手段之一
```

---

## 5. Level Shifter 详细设计

### 5.1 Level Shifter 类型详解

#### 低到高（Low-to-High, L2H）

```
输入: VDD_L (低电压域)  →  输出: VDD_H (高电压域)

电路原理 (交叉耦合型):
              VDD_H
             ┌──┤──┐
             │  │  │
           ┌─┤P1│  ├─┤P2├─┐
           │ └──┘  └──┘  │
    in ────┤              ├──── out
    (VDD_L)│ ┌──┐  ┌──┐  │    (VDD_H)
           └─┤N1│  ├─┤N2├─┘
             └──┘  └──┘
              │    │
             GND  GND

工作原理：
- in=VDD_L → N1导通，拉低左节点
              → P2导通，右节点(out)被拉到VDD_H
- in=0     → N2导通(通过反相)，拉低右节点
              → P1导通，左节点被拉到VDD_H
```

#### 高到低（High-to-Low, H2L）

```
输入: VDD_H (高电压域)  →  输出: VDD_L (低电压域)

方法1: 简单缓冲器 (当 VDD_H < VDD_L 的可靠性阈值时)
in (VDD_H) ──→ [Buffer powered by VDD_L] ──→ out (VDD_L)
注意: 需要确保输入高电平不超过 VDD_L 的氧化层耐压

方法2: 分压 + 缓冲 (当 VDD_H >> VDD_L 时)
in (VDD_H) ──→ [电阻分压] ──→ [Buffer] ──→ out (VDD_L)
```

#### 带使能的 Level Shifter（Enable Level Shifter, ELS）

```
用于 Power Gating 场景：
当源域关断时，输入可能为 X 或浮空
ELS 在源域关断时将输出钳位为固定值

功能表：
┌────────┬─────────────┬───────────┐
│ Enable │ Input (源域) │ Output    │
├────────┼─────────────┼───────────┤
│   1    │    valid    │  shifted  │ 正常工作
│   0    │   X/float   │  clamp   │ 钳位（0或1）
└────────┴─────────────┴───────────┘

这种 Level Shifter 同时具有 Isolation 功能，
可以减少独立 Isolation Cell 的使用
```

### 5.2 Level Shifter 放置策略

```
位置选项:
1. Source Domain（源域）放置
   - 优点: 短输出连线（高电压域信号质量好）
   - 缺点: 源域关断时 LS 也关断，需要特殊处理
   - 适用: 源域不可关断的场景

2. Destination Domain（目标域）放置
   - 优点: 目标域通常是 Always-On 或开启的
   - 缺点: 长低电压信号连线，信号完整性可能有问题
   - 适用: 源域可关断的场景（推荐）

3. 边界放置
   - 放在两域物理边界处
   - 兼顾两方面考虑

业界通常选择: 在目标域（parent/接收侧）放置
UPF 中: -location parent 或 -location self
```

---

## 6. Isolation Cell 详细设计

### 6.1 Isolation Cell 类型

```
类型1: Clamp-to-0 (AND 隔离)
         ┌─────┐
 in ────→│ AND │──→ out
 iso_n ──→│     │
         └─────┘
iso_n=0 时, out=0 (无论 in 是什么)
iso_n=1 时, out=in (正常工作)

类型2: Clamp-to-1 (OR 隔离)
         ┌─────┐
 in ────→│ OR  │──→ out
 iso  ──→│     │
         └─────┘
iso=1 时, out=1
iso=0 时, out=in

类型3: Latch 隔离
         ┌───────┐
 in ────→│ Latch │──→ out
 iso_n ──→│       │
         └───────┘
iso_n=0 时, out=上次 in 的值 (锁存)
iso_n=1 时, out=in (透明)

类型4: High-Z 隔离 (三态)
iso=1 时, out=High-Z (高阻)
iso=0 时, out=in
```

### 6.2 Isolation 策略选择指南

| 下游逻辑需求 | 推荐 Isolation 类型 | 说明 |
|-------------|-------------------|------|
| 需要确定的低电平 | Clamp-to-0 | 默认选择，最安全 |
| 需要确定的高电平 | Clamp-to-1 | 如复位信号、片选取反 |
| 需要保持最后状态 | Latch | 减少恢复后的翻转 |
| 总线接口（非关键） | Clamp-to-0 | 总线空闲通常为 0 |
| 中断信号 | Clamp-to-0 | 避免误触发中断 |
| 使能信号 | 根据极性选择 | 确保关断时功能正确 |

### 6.3 Isolation Cell 供电

```
关键问题: Isolation Cell 自身的电源必须是 ON 的！

场景: Domain A (可关断) → Isolation Cell → Domain B (Always-On)

          Domain A (OFF)        Domain B (ON)
         ┌──────────────┐    ┌──────────────┐
         │   ▓▓▓▓▓▓▓   │    │              │
 VDD_A=0 │   (关断)     │    │   Logic B    │
         │              │    │              │
         └──────┬───────┘    └───────┬──────┘
                │                     │
         ┌──────▼─────────────────────▼───┐
         │        Isolation Cell          │
         │    供电: VDD_B (Always-On!)     │
         │    这样当 A 关断时 ISO 仍能工作  │
         └────────────────────────────────┘

UPF 中指定:
set_isolation iso_a \
    -domain PD_A \
    -isolation_power_net VDD_B_net \   ← ISO供电来自B域(ON)
    -isolation_ground_net VSS_net
```

---

## 7. Retention Register 详细设计

### 7.1 Retention Register 内部结构

```
标准 Retention Register (Balloon Latch 类型):

                VDD_switchable (可关断)
                    │
            ┌───────┴───────┐
            │  Master Latch  │ ← 正常的主锁存器
  D ────→   │               │
  CLK ───→  │               │──→ Q (正常输出)
            └───────┬───────┘
                    │
                    │ internal_node
                    │
            ┌───────▼───────┐
            │ Balloon Latch  │ ← 保持锁存器
            │  (Shadow)      │
  SAVE ──→  │               │
  RESTORE→  │               │
            │ VDD_always_on  │ ← 由 Always-On 电源供电！
            └───────────────┘

工作原理:
1. 正常工作: Master Latch 正常采样，Balloon Latch 待命
2. Save: SAVE 信号触发，internal_node 值存入 Balloon Latch
3. 关断: VDD_switchable 断电，Master Latch 数据丢失
         Balloon Latch 由 VDD_always_on 供电，数据保持
4. 恢复: VDD_switchable 重新上电
5. Restore: RESTORE 信号触发，Balloon Latch 值写回 Master Latch
6. 恢复正常工作
```

### 7.2 Retention 的面积和功耗开销

```
面积比较 (相对于标准寄存器):
┌────────────────────────┬──────────┬──────────┐
│ 寄存器类型              │ 面积比    │ 漏电比    │
├────────────────────────┼──────────┼──────────┤
│ 标准寄存器 (DFF)        │ 1.0x     │ 1.0x     │
│ Retention DFF (单电源)  │ 1.3~1.5x │ 1.2~1.4x │
│ Retention DFF (双电源)  │ 1.4~1.6x │ 1.3~1.5x │
│ 带 Save+Restore 控制    │ 1.5~1.8x │ 1.4~1.6x │
└────────────────────────┴──────────┴──────────┘

设计决策: 不是所有寄存器都需要 Retention！
- 只对需要保持的状态使用 Retention Register
- 可以用软件恢复的状态不需要 Retention
- 优先保持: 配置寄存器、关键状态机、程序计数器
- 可不保持: 数据通路寄存器（可重新计算/加载）
```

### 7.3 Save/Restore 时序要求

```
Save 时序:
     clk ─┐ ┌─┐ ┌─┐ ┌─
           └─┘ └─┘ └─┘

  save_en ───────┐   ┌──   (1个或多个时钟周期宽度)
                 └───┘

要求:
- save_en 必须在时钟活跃时触发 (因为寄存器值在时钟沿更新)
- save_en 宽度通常 >= 1 个时钟周期
- save_en 必须在 isolation 使能之前或同时完成

Restore 时序:
     clk ─┐ ┌─┐ ┌─┐ ┌─
           └─┘ └─┘ └─┘

restore_en ──────┐   ┌──
                 └───┘

要求:
- restore_en 在电源稳定后触发
- restore_en 宽度通常 >= 1 个时钟周期
- restore_en 必须在 isolation 取消之前完成
- restore_en 可以在时钟恢复之前或之后触发 (取决于实现)
```

---

## 8. 总线低功耗设计详解

### 8.1 AMBA Q-Channel 协议详解

Q-Channel 是 ARM 定义的设备级低功耗握手接口。

#### 信号定义

| 信号 | 方向 | 说明 |
|------|------|------|
| QREQN | Controller → Device | 低功耗请求（低有效） |
| QACCEPTN | Device → Controller | 接受低功耗请求（低有效） |
| QDENY | Device → Controller | 拒绝低功耗请求 |
| QACTIVE | Device → Controller | 设备活跃指示 |

#### 状态转换图

```
                    QREQN=1
                   QACCEPTN=1
              ┌──────────────────┐
              │                  │
              │     Q_RUN        │←──────────────┐
              │   (运行状态)      │               │
              └────────┬─────────┘               │
                       │                          │
                       │ QREQN=0                  │ QREQN=1
                       │ (请求进入低功耗)           │ (请求退出低功耗)
                       ▼                          │
              ┌──────────────────┐               │
              │    Q_REQUEST     │               │
              │  (请求中)        │               │
              └──┬──────────┬───┘               │
                 │          │                    │
    QACCEPTN=0   │          │ QDENY=1            │
    QDENY=0      │          │ QACCEPTN=1         │
    (接受)       │          │ (拒绝)              │
                 ▼          ▼                    │
     ┌────────────────┐  ┌───────────────┐      │
     │   Q_STOPPED    │  │   Q_DENIED    │      │
     │  (已停止)      │  │  (已拒绝)     │──────┘
     └───────┬────────┘  └───────────────┘
             │                        (自动返回 Q_RUN)
             │ QREQN=1
             │ (请求退出低功耗)
             ▼
     ┌────────────────┐
     │    Q_EXIT      │
     │  (退出中)      │──────→ QACCEPTN=1 → Q_RUN
     └────────────────┘
```

#### Q-Channel 使用示例

```verilog
// Q-Channel Slave (设备侧) 示例
module qchannel_slave (
    input  wire clk,
    input  wire rst_n,

    // Q-Channel 接口
    input  wire qreqn,      // 低功耗请求
    output reg  qacceptn,   // 接受响应
    output reg  qdeny,      // 拒绝响应
    output wire qactive,    // 设备活跃

    // 设备状态
    input  wire device_busy, // 设备忙（有未完成事务）
    output reg  device_idle  // 设备空闲（可以进入低功耗）
);

    localparam Q_RUN     = 2'd0;
    localparam Q_REQUEST = 2'd1;
    localparam Q_STOPPED = 2'd2;
    localparam Q_EXIT    = 2'd3;

    reg [1:0] state, next_state;

    assign qactive = device_busy;  // 有事务时保持 active

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= Q_RUN;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        qacceptn   = 1'b1;
        qdeny      = 1'b0;
        device_idle = 1'b0;

        case (state)
            Q_RUN: begin
                qacceptn = 1'b1;
                if (!qreqn)
                    next_state = Q_REQUEST;
            end

            Q_REQUEST: begin
                if (device_busy) begin
                    // 设备忙，拒绝低功耗请求
                    qdeny    = 1'b1;
                    qacceptn = 1'b1;
                    next_state = Q_RUN;  // 回到运行状态
                end else begin
                    // 设备空闲，接受低功耗请求
                    qacceptn = 1'b0;
                    qdeny    = 1'b0;
                    next_state = Q_STOPPED;
                end
            end

            Q_STOPPED: begin
                qacceptn    = 1'b0;
                device_idle = 1'b1;  // 通知内部可以关断时钟等
                if (qreqn)           // 控制器请求退出低功耗
                    next_state = Q_EXIT;
            end

            Q_EXIT: begin
                qacceptn = 1'b1;     // 响应退出完成
                next_state = Q_RUN;
            end
        endcase
    end

endmodule
```

### 8.2 AMBA P-Channel 协议详解

P-Channel 支持多个功耗状态（不仅是 ON/OFF），适用于更细粒度的电源管理。

```
信号:
PREQ [N-1:0]  : Controller → Device, 目标功耗状态
PSTATE [N-1:0]: Device → Controller, 当前功耗状态
PACCEPT       : Device → Controller, 接受状态转换
PDENY         : Device → Controller, 拒绝状态转换

典型功耗状态编码 (以 2-bit 为例):
00: FULL_ON    (全速运行)
01: CLK_GATED  (时钟门控)
10: RETENTION  (保持状态)
11: POWER_OFF  (电源关断)

状态转换:
FULL_ON → CLK_GATED → RETENTION → POWER_OFF
POWER_OFF → RETENTION → CLK_GATED → FULL_ON
(通常不允许跳过中间状态)
```

### 8.3 AXI 总线的低功耗考虑

```
AXI 总线空闲检测:
├── AW Channel: AWVALID=0 且无 pending write
├── W  Channel: WVALID=0 且无 pending write data
├── B  Channel: BVALID=0 且无 pending response
├── AR Channel: ARVALID=0 且无 pending read
└── R  Channel: RVALID=0 且无 pending read data

所有通道空闲 → 总线可以进入低功耗

低功耗模式:
1. 时钟门控: 总线空闲时关闭时钟（最快恢复）
2. Power Gating: 长时间空闲时关断电源（需要完整恢复流程）

注意事项:
- 必须等待所有 outstanding transaction 完成
- Read/Write interleaving 的事务必须完成
- AXI4 的 exclusive access 状态需要保持
- 需要处理好 low-power entry/exit 与正常事务的竞争
```

---

## 9. 电源管理单元(PMU)架构

### 9.1 PMU 详细架构

```
┌─────────────────────────────────────────────────────────────┐
│                    PMU (Power Management Unit)               │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ 寄存器接口    │  │ 中断控制器    │  │ 调试接口           │  │
│  │ (APB/AHB)    │  │              │  │ (JTAG bypass)     │  │
│  └──────┬───────┘  └──────┬───────┘  └───────┬───────────┘  │
│         │                  │                   │              │
│  ┌──────▼──────────────────▼───────────────────▼───────────┐ │
│  │              Main Power State Machine                    │ │
│  │  ┌───────┐  ┌───────┐  ┌───────┐  ┌──────────────────┐ │ │
│  │  │ ACTIVE│→ │ IDLE  │→ │STANDBY│→ │ SHUTDOWN/DEEPSLEEP│ │ │
│  │  └───────┘  └───────┘  └───────┘  └──────────────────┘ │ │
│  └─────────────────────────────────────────────────────────┘ │
│         │                  │                   │              │
│  ┌──────▼───────┐  ┌──────▼───────┐  ┌───────▼───────────┐ │
│  │ Domain        │  │ Clock        │  │ Voltage            │ │
│  │ Controllers   │  │ Controller   │  │ Controller         │ │
│  │               │  │              │  │                    │ │
│  │ ┌──────────┐  │  │ ┌──────────┐ │  │ ┌──────────────┐  │ │
│  │ │PD_CPU ctl│  │  │ │PLL on/off│ │  │ │PMIC interface │  │ │
│  │ │-iso_en   │  │  │ │clk div   │ │  │ │I2C/SPI       │  │ │
│  │ │-ret_save │  │  │ │clk gate  │ │  │ │OPP table     │  │ │
│  │ │-ret_rest │  │  │ │clk mux   │ │  │ │DVFS FSM      │  │ │
│  │ │-pwr_sw   │  │  │ └──────────┘ │  │ └──────────────┘  │ │
│  │ └──────────┘  │  └──────────────┘  └────────────────────┘ │
│  │ ┌──────────┐  │                                           │
│  │ │PD_GPU ctl│  │  ┌──────────────┐  ┌────────────────────┐ │
│  │ └──────────┘  │  │ Wakeup       │  │ Timer/Counter      │ │
│  │ ┌──────────┐  │  │ Controller   │  │ (for timed wakeup) │ │
│  │ │PD_xxx ctl│  │  │ -GPIO wakeup │  │                    │ │
│  │ └──────────┘  │  │ -IRQ wakeup  │  │ Watchdog Timer     │ │
│  └───────────────┘  │ -Timer wakeup│  │ (safety)           │ │
│                     │ -RTC alarm   │  └────────────────────┘ │
│                     └──────────────┘                         │
│                                                              │
│  ═══════════════════════════════════════════════════════════  │
│  VDD_ALWAYS_ON 供电 (PMU 自身供电域始终开启)                   │
└─────────────────────────────────────────────────────────────┘
```

### 9.2 PMU 寄存器映射示例

```
偏移地址    寄存器名           描述
────────────────────────────────────────────────────
0x000     PMU_CTRL           PMU 全局控制
0x004     PMU_STATUS         PMU 状态
0x008     PMU_IRQ_EN         中断使能
0x00C     PMU_IRQ_STATUS     中断状态
0x010     PMU_IRQ_CLEAR      中断清除

0x100     PD_CPU_CTRL        CPU 域控制
0x104     PD_CPU_STATUS      CPU 域状态
0x108     PD_CPU_ISO_CTRL    CPU 域隔离控制
0x10C     PD_CPU_RET_CTRL    CPU 域 Retention 控制

0x200     PD_GPU_CTRL        GPU 域控制
0x204     PD_GPU_STATUS      GPU 域状态
...

0x300     CLK_CTRL           时钟控制
0x304     CLK_DIV            时钟分频
0x308     CLK_GATE           时钟门控控制
0x30C     PLL_CTRL           PLL 控制

0x400     DVFS_CTRL          DVFS 控制
0x404     DVFS_STATUS        DVFS 状态
0x408     DVFS_OPP           目标 OPP
0x40C     DVFS_VOLTAGE       当前电压值

0x500     WAKEUP_EN          唤醒源使能
0x504     WAKEUP_STATUS      唤醒状态
0x508     WAKEUP_CLEAR       唤醒清除

0x600     TIMER_WAKEUP       定时唤醒设置
0x604     RTC_ALARM          RTC 闹钟设置
```

---

## 10. 实际 SoC 低功耗架构案例分析

### 10.1 移动 SoC 低功耗架构示例

```
以典型的移动 AP (Application Processor) 为例：

┌──────────────────────────────────────────────────────────────────┐
│                    Mobile SoC Architecture                        │
│                                                                   │
│  ┌─────────────────────────────────────────┐  ┌──────────────┐   │
│  │ CPU Cluster (big.LITTLE)                │  │  GPU          │   │
│  │ ┌──────────┐ ┌──────────┐               │  │  VDD_GPU     │   │
│  │ │ Big Core0│ │ Big Core1│  VDD_BIG     │  │  可关断       │   │
│  │ │ per-core │ │ per-core │  per-core    │  │  4 OPP levels │   │
│  │ │ DVFS     │ │ DVFS     │  power gating│  └──────────────┘   │
│  │ └──────────┘ └──────────┘               │                     │
│  │ ┌──────────┐ ┌──────────┐               │  ┌──────────────┐   │
│  │ │Little C0 │ │Little C1 │  VDD_LITTLE  │  │  NPU/DSP     │   │
│  │ │ per-core │ │ per-core │  per-core    │  │  VDD_NPU     │   │
│  │ │ DVFS     │ │ DVFS     │  power gating│  │  可关断       │   │
│  │ └──────────┘ └──────────┘               │  └──────────────┘   │
│  │ ┌──────────────────────────────────────┐│                     │
│  │ │ L2 Cache (VDD_CACHE, retention)     ││                     │
│  │ └──────────────────────────────────────┘│                     │
│  └─────────────────────────────────────────┘                     │
│                                                                   │
│  ┌────────────┐ ┌────────────┐ ┌──────────────────────────────┐  │
│  │ DDR Ctrl   │ │ Bus/NoC    │ │ Always-On Domain             │  │
│  │ VDD_DDR    │ │ VDD_BUS    │ │ VDD_AON                      │  │
│  │ Self-Refresh│ │ 可时钟门控 │ │ ┌───┐ ┌───┐ ┌────┐ ┌─────┐ │  │
│  └────────────┘ └────────────┘ │ │PMU│ │RTC│ │GPIO│ │Timer│ │  │
│                                 │ └───┘ └───┘ └────┘ └─────┘ │  │
│  ┌────────────┐ ┌────────────┐ │ ┌──────┐ ┌──────────────┐   │  │
│  │ Peripheral │ │ IO         │ │ │WDT   │ │Wakeup Logic  │   │  │
│  │ VDD_PERI   │ │ VDD_IO     │ │ └──────┘ └──────────────┘   │  │
│  │ 可关断     │ │ 1.8V/3.3V  │ └──────────────────────────────┘  │
│  └────────────┘ └────────────┘                                   │
└──────────────────────────────────────────────────────────────────┘

功耗状态矩阵：
┌──────────┬──────┬──────┬─────┬─────┬──────┬──────┬─────┬───────┐
│ 状态      │ Big  │Little│ GPU │ NPU │ DDR  │ Peri │ Bus │ AON   │
├──────────┼──────┼──────┼─────┼─────┼──────┼──────┼─────┼───────┤
│ Full Perf│ Turbo│ On   │ On  │ On  │ Active│ On  │ On  │ On    │
│ Normal   │ Nom  │ On   │ On  │ Off │ Active│ On  │ On  │ On    │
│ Light    │ Off  │ Low  │ Off │ Off │ Active│ Part │ CG  │ On    │
│ Idle     │ Off  │ Ret  │ Off │ Off │ S.Ref │ Off │ CG  │ On    │
│ Standby  │ Off  │ Off  │ Off │ Off │ S.Ref │ Off │ Off │ On    │
│ Shutdown │ Off  │ Off  │ Off │ Off │ Off  │ Off │ Off │ On    │
└──────────┴──────┴──────┴─────┴─────┴──────┴──────┴─────┴───────┘

CG=Clock Gated, Ret=Retention, S.Ref=Self-Refresh
```

### 10.2 低功耗设计的面试常见问题

| 问题 | 关键答题点 |
|------|----------|
| 什么是 Power Domain？ | 独立供电区域，可独立控制电压和电源 |
| DVFS 的切换顺序？ | 升：先升压后升频；降：先降频后降压 |
| Power Gating 的关断序列？ | Save → Isolate → Power Off |
| Power Gating 的恢复序列？ | Power On → Wait Stable → Restore → De-isolate |
| Level Shifter 什么时候需要？ | 跨电压域信号传输时 |
| Isolation Cell 什么时候需要？ | 可关断域向外部输出信号时 |
| Retention Register 的原理？ | Balloon Latch 由 Always-On 电源保持 |
| Clock Gating 节省什么功耗？ | 动态功耗（翻转功耗） |
| Power Gating 节省什么功耗？ | 静态功耗（漏电功耗） |
| Q-Channel 的作用？ | 设备级低功耗握手，协调进入/退出低功耗 |

---

> 返回 [主学习指南](../low_power_design_learning_guide.md) | 上一章 ← [基础理论详解](01_fundamentals.md) | 下一章 → [低功耗RTL设计详解](03_rtl_design.md)
