# Verilog 低功耗设计检查规则手册

> 面向 RTL 工程师的低功耗 Verilog 编码规范，覆盖从门级到模块级的全套检查规则。  
> 每条规则均含：**规则说明 · 反例 · 正例 · 工具检测提示**。

---

## 目录

1. [时钟门控（Clock Gating）](#1-时钟门控)
2. [寄存器使能与条件写](#2-寄存器使能与条件写)
3. [组合逻辑翻转抑制](#3-组合逻辑翻转抑制)
4. [总线与数据通路](#4-总线与数据通路)
5. [存储器访问](#5-存储器访问)
6. [状态机编码](#6-状态机编码)
7. [电源域与隔离单元](#7-电源域与隔离单元)
8. [复位策略](#8-复位策略)
9. [异步逻辑与跨时钟域](#9-异步逻辑与跨时钟域)
10. [工艺相关与综合提示](#10-工艺相关与综合提示)
11. [检查规则速查表](#11-检查规则速查表)

---

## 1 时钟门控

### LP-CLK-001：禁止在 always 块中直接使用门控时钟表达式

**问题**：手写 `clk & enable` 门控逻辑会产生毛刺，并且综合工具无法识别为标准时钟门控单元（ICG）。

```verilog
// ❌ 反例 — 毛刺风险，综合工具无法插入 ICG
always @(posedge (clk & enable)) begin
    q <= d;
end
```

```verilog
// ✅ 正例 — 使用寄存器使能，由综合工具插入 ICG
always @(posedge clk) begin
    if (enable)
        q <= d;
end
```

> 🔧 **工具提示**：Synopsys DC 的 `compile_ultra -gate_clock` 或 Cadence Genus 的 `set_db lp_clock_gating_style` 可自动推断并插入 ICG；SpyGlass 规则 `Clock_09` 检测手写门控时钟。

---

### LP-CLK-002：时钟门控使能信号必须在时钟下降沿或锁存相采样

**问题**：使能信号若在时钟上升沿前后跳变，会与 ICG 的 latch 产生竞争，导致毛刺时钟。

```verilog
// ❌ 反例 — 使能直接来自组合逻辑，可能在 posedge 附近跳变
assign cg_enable = (state == ACTIVE) & !flush;

always @(posedge clk) begin
    if (cg_enable) reg_q <= d;
end
```

```verilog
// ✅ 正例 — 使能在前一个 negedge 寄存，消除竞争窗口
always @(negedge clk or negedge rst_n) begin
    if (!rst_n) cg_en_lat <= 1'b0;
    else        cg_en_lat <= (state == ACTIVE) & !flush;
end

always @(posedge clk) begin
    if (cg_en_lat) reg_q <= d;
end
```

> 🔧 **工具提示**：SpyGlass `GlitchyClock` 规则；DC `check_clock_gating` 命令。

---

### LP-CLK-003：避免不必要的多级时钟分频

**问题**：RTL 中自行生成的分频时钟无法被综合工具识别为时钟树，功耗和时序均难以控制。

```verilog
// ❌ 反例 — 手写分频器产生"派生时钟"
reg clk_div2;
always @(posedge clk) clk_div2 <= ~clk_div2;
always @(posedge clk_div2) begin ... end
```

```verilog
// ✅ 正例 — 使用时钟使能代替分频，或让 SoC 时钟树统一管理
reg [1:0] cnt;
wire      clk_en_div2 = (cnt == 2'd1);
always @(posedge clk) cnt <= cnt + 1'b1;

always @(posedge clk) begin
    if (clk_en_div2) begin ... end
end
```

> 🔧 **工具提示**：DC `create_generated_clock` 必须对所有派生时钟显式声明；VC SpyGlass `STARC_2.3.3.1` 检测非 SDC 声明的派生时钟。

---

## 2 寄存器使能与条件写

### LP-REG-001：寄存器必须具备有效使能条件，避免每拍无意义翻转

```verilog
// ❌ 反例 — 每个时钟周期都写入，浪费翻转功耗
always @(posedge clk) begin
    pipeline_reg <= data_in;   // data_in 不变时仍然翻转
end
```

```verilog
// ✅ 正例 — 仅在数据有效时写入
always @(posedge clk) begin
    if (data_valid)
        pipeline_reg <= data_in;
end
```

> 🔧 **工具提示**：Power Compiler `report_power` 中 `internal power` 占比高，检查寄存器翻转率；Questa `toggle coverage` 识别高翻转寄存器。

---

### LP-REG-002：宽总线寄存器应按字段分组使能

**问题**：对 64-bit 寄存器整体使能，当只有低 8 位有效时，高位 56 个触发器仍然受到使能信号驱动，增加内部功耗。

```verilog
// ❌ 反例 — 整体使能 64-bit 寄存器
always @(posedge clk) begin
    if (wr_en) data_reg[63:0] <= wdata[63:0];
end
```

```verilog
// ✅ 正例 — 按字节使能，分段写入
always @(posedge clk) begin
    if (wr_en[0]) data_reg[ 7: 0] <= wdata[ 7: 0];
    if (wr_en[1]) data_reg[15: 8] <= wdata[15: 8];
    if (wr_en[2]) data_reg[23:16] <= wdata[23:16];
    if (wr_en[3]) data_reg[31:24] <= wdata[31:24];
    // ...
end
```

---

### LP-REG-003：移位寄存器优先使用 FIFO/存储器替代

**问题**：长移位寄存器（> 16 级）在 ASIC 中每级都有翻转，功耗远高于等效的 SRAM。

```verilog
// ❌ 反例 — 128 级移位寄存器
reg [7:0] shift_reg [0:127];
always @(posedge clk) begin
    integer i;
    for (i = 127; i > 0; i = i - 1)
        shift_reg[i] <= shift_reg[i-1];
    shift_reg[0] <= data_in;
end
```

```verilog
// ✅ 正例 — 用循环 FIFO + 地址指针替代
// 实现中使用 SRAM，翻转仅发生在读写端口
```

---

## 3 组合逻辑翻转抑制

### LP-CMB-001：避免多扇出长链组合逻辑

**问题**：过长的组合链在每次输入变化时，沿链路的所有中间节点都翻转，产生"毛刺功耗"。

```verilog
// ❌ 反例 — 过长的不必要加法链
assign result = a + b + c + d + e + f + g + h;
```

```verilog
// ✅ 正例 — 流水线打断，减少单周期翻转传播深度
always @(posedge clk) begin
    stage1 <= a + b + c + d;
    stage2 <= e + f + g + h;
end
assign result = stage1 + stage2;  // 或再流水一级
```

> 🔧 **工具提示**：DC `set_max_dynamic_power` 约束；Power Compiler `report_switching_activity` 观察内部节点翻转率。

---

### LP-CMB-002：多路选择器（MUX）的数据输入应在无效时保持稳定

```verilog
// ❌ 反例 — 未选中的加法器仍在翻转，其输出驱动 MUX 数据线
assign sum_a = op_a + const_a;  // 即使 sel=0 也在翻转
assign sum_b = op_b + const_b;
assign result = sel ? sum_b : sum_a;
```

```verilog
// ✅ 正例 — 操作数门控（Operand Isolation）
assign sum_a = (sel == 1'b0) ? (op_a + const_a) : '0;
assign sum_b = (sel == 1'b1) ? (op_b + const_b) : '0;
assign result = sel ? sum_b : sum_a;

// 或者由综合工具自动插入操作数隔离：
// 在 DC 中设置 set_operand_isolation_style
```

> 🔧 **工具提示**：Power Compiler `compile -power_opto` 自动插入操作数隔离；SpyGlass `Power_08` 检测未隔离的宽数据路径。

---

### LP-CMB-003：格雷码用于高翻转计数器

```verilog
// ❌ 反例 — 二进制计数器，最高位翻转在 0111→1000 时导致全位同时跳
reg [3:0] bin_cnt;
always @(posedge clk) bin_cnt <= bin_cnt + 1;
```

```verilog
// ✅ 正例 — 格雷码计数器，每次只有 1 位翻转
reg [3:0] gray_cnt;
wire [3:0] next_bin = gray_to_bin(gray_cnt) + 1;
always @(posedge clk)
    gray_cnt <= bin_to_gray(next_bin);
```

---

## 4 总线与数据通路

### LP-BUS-001：总线空闲时应保持稳定（总线保持）

```verilog
// ❌ 反例 — 总线无驱动时浮空，受下游逻辑影响随机翻转
assign bus = (master_req) ? data_out : 'z;  // 三态总线浮空
```

```verilog
// ✅ 正例 — 空闲时驱动稳定值（通常为上次值或全 0）
assign bus = (master_req) ? data_out : last_bus_val;
// 或在总线上增加 bus keeper cell（由物理实现插入）
```

---

### LP-BUS-002：数据路径宽度匹配，避免多余位传播

```verilog
// ❌ 反例 — 8-bit 数据零扩展到 32-bit 后参与 32-bit 运算
wire [31:0] data_ext = {24'b0, data_8bit};
wire [31:0] result   = data_ext * coeff;   // 高 24 位始终为 0，浪费
```

```verilog
// ✅ 正例 — 在必要时才扩展，或使用窄路径完成运算
wire [15:0] result_narrow = data_8bit * coeff_8bit;
wire [31:0] result = {{16{result_narrow[15]}}, result_narrow};
```

---

### LP-BUS-003：AXI/AHB 等总线接口必须在空闲时拉低有效信号

```verilog
// ❌ 反例 — VALID 信号未及时撤销，导致后续逻辑持续翻转
assign axi_wvalid = req_pending;   // req_pending 可能因组合逻辑毛刺而抖动
```

```verilog
// ✅ 正例 — VALID 信号寄存器输出，消除毛刺
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) axi_wvalid <= 1'b0;
    else        axi_wvalid <= req_pending_reg;
end
```

---

## 5 存储器访问

### LP-MEM-001：SRAM 读使能（RE）必须精确门控

```verilog
// ❌ 反例 — 每周期都使能 SRAM，即使不需要读取
sram_instance u_sram (
    .clk(clk),
    .re(1'b1),       // 始终使能，浪费读功耗
    .addr(addr),
    .dout(dout)
);
```

```verilog
// ✅ 正例 — 仅在需要时使能
wire sram_re = (state == READ_STATE) & addr_valid;
sram_instance u_sram (
    .clk(clk),
    .re(sram_re),
    .addr(addr),
    .dout(dout)
);
```

> 🔧 **工具提示**：SRAM 编译器（如 ARM Memory Compiler）的 `read enable` 管脚功耗模型在 Liberty 文件中有独立 `when` 条件，必须正确使用。

---

### LP-MEM-002：写使能（WE）必须避免误写

```verilog
// ❌ 反例 — WE 来自组合逻辑，可能产生毛刺写入
assign sram_we = (state == WRITE) & decode_hit;  // 组合毛刺风险
```

```verilog
// ✅ 正例 — WE 寄存器化，避免毛刺
always @(posedge clk) begin
    sram_we_r <= (state == WRITE) & decode_hit;
end
// 使用 sram_we_r 作为写使能
```

---

### LP-MEM-003：大容量存储器分 bank 管理，按需激活

```verilog
// ❌ 反例 — 单个大 SRAM，全时激活
// 等效于始终给整块 512KB SRAM 供电和时钟

// ✅ 正例 — 分 bank，按地址范围激活对应 bank
wire bank0_sel = (addr[18:17] == 2'b00);
wire bank1_sel = (addr[18:17] == 2'b01);
// ...
sram_bank u_bank0 (.re(sram_re & bank0_sel), ...);
sram_bank u_bank1 (.re(sram_re & bank1_sel), ...);
```

---

## 6 状态机编码

### LP-FSM-001：优先使用 one-hot 编码（ASIC 小状态机）

**权衡**：
| 编码方式 | 触发器数量 | 组合逻辑翻转 | 适用场景 |
|---------|-----------|------------|---------|
| 二进制   | log₂(N)   | 多态位同时跳 | 状态多（>16）|
| One-hot | N         | 每次仅 2 位翻转 | 状态少（≤16）|
| 格雷码  | log₂(N)   | 每次 1 位翻转 | 线性顺序状态 |

```verilog
// ✅ One-hot 编码示例（8 状态机）
localparam IDLE  = 8'b0000_0001;
localparam READ  = 8'b0000_0010;
localparam WRITE = 8'b0000_0100;
// ...
reg [7:0] state, next_state;
```

---

### LP-FSM-002：状态机输出寄存器化，消除组合输出毛刺

```verilog
// ❌ 反例 — 组合输出，状态跳转时产生毛刺
assign out_valid = (state == DATA_VALID);
```

```verilog
// ✅ 正例 — 输出寄存器化（Moore 型状态机）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) out_valid <= 1'b0;
    else        out_valid <= (next_state == DATA_VALID);
end
```

---

### LP-FSM-003：存在低功耗 IDLE 态，非活动时进入等待

```verilog
// ✅ 正例 — 状态机必须有明确的 IDLE/SLEEP 态
always @(posedge clk) begin
    case (state)
        IDLE: begin
            // 所有输出保持稳定，不触发下游翻转
            if (!req_valid) state <= IDLE;
            else            state <= ACTIVE;
        end
        // ...
    endcase
end
```

---

## 7 电源域与隔离单元

### LP-PD-001：跨电源域信号必须插入隔离单元（Isolation Cell）

```verilog
// ❌ 反例 — power_domain_B 关闭时，其输出信号为 X，直接连接到 always-on 域
// 这在 RTL 中不会报错，但实际硅片上会导致 always-on 域行为异常
assign ao_input = pd_b_output;  // pd_b_output 来自可关断域
```

```verilog
// ✅ 正例 — 在 UPF/CPF 中声明隔离策略，RTL 中保留接口注释
// RTL 层不直接实例化隔离单元（由综合工具根据 UPF 插入）
// 但必须在注释中标明：
// [ISO] 以下信号跨越 PD_B → PD_ALWAYS_ON，需要隔离
assign ao_input = pd_b_output;

// 对应 UPF：
// set_isolation iso_pd_b -domain PD_B -isolation_power_net VDD \
//     -isolation_ground_net VSS -clamp_value 0 -applies_to outputs
```

> 🔧 **工具提示**：SpyGlass `LP_01`~`LP_05` 系列规则专门检测跨域无隔离信号；Conformal Low Power 做等价性检查。

---

### LP-PD-002：电源开关（Power Switch）控制信号必须来自 always-on 域

```verilog
// ❌ 反例 — 电源开关控制信号本身在可关断域中
always @(posedge clk_pd) begin   // clk_pd 在可关断域
    pwr_switch_en <= some_logic;  // 若域已关，此寄存器无法工作
end
```

```verilog
// ✅ 正例 — 电源开关控制寄存器必须在 always-on 域
always @(posedge clk_ao) begin   // clk_ao 在 always-on 域
    pwr_switch_en <= ctrl_reg_bit;
end
```

---

### LP-PD-003：保持寄存器（Retention Register）必须在 SAVE/RESTORE 时序中正确操作

```verilog
// ✅ 正例 — 保持寄存器控制时序
// SAVE:  save_n 拉低（保存影子寄存器）→ 等待 tSAVE → 关断电源
// RESTORE: 上电稳定 → restore_n 拉低（恢复数据）→ 等待 tRESTORE → 释放复位
always @(posedge clk_ao) begin
    if (pm_state == SAVE)         save_n <= 1'b0;
    else                           save_n <= 1'b1;
    if (pm_state == RESTORE_DONE) restore_n <= 1'b1;
    else if (pm_state == RESTORE)  restore_n <= 1'b0;
end
```

---

## 8 复位策略

### LP-RST-001：优先使用同步复位，减少复位网络功耗

**权衡**：异步复位需要专用复位树（等价于额外时钟树），增加布线功耗；同步复位复用时钟树。

```verilog
// 异步复位（谨慎使用，仅 power-on 或 debug 场景）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) q <= '0;
    else        q <= d;
end

// ✅ 同步复位（低功耗设计首选）
always @(posedge clk) begin
    if (!rst_n) q <= '0;
    else        q <= d;
end
```

> 🔧 **工具提示**：若必须使用异步复位，SDC 中需声明 `set_false_path -from [get_ports rst_n]` 并单独约束复位树。

---

### LP-RST-002：复位信号不得有毛刺

```verilog
// ❌ 反例 — 复位来自组合逻辑
assign rst_n = global_rst_n & ~sw_reset_bit;  // sw_reset_bit 翻转可能产生毛刺复位
```

```verilog
// ✅ 正例 — 复位信号寄存器同步化
always @(posedge clk or negedge global_rst_n) begin
    if (!global_rst_n) rst_sync <= 2'b00;
    else               rst_sync <= {rst_sync[0], ~sw_reset_bit};
end
assign rst_n = rst_sync[1];
```

---

## 9 异步逻辑与跨时钟域

### LP-CDC-001：跨时钟域信号必须同步，消除亚稳态导致的额外翻转

```verilog
// ❌ 反例 — 直接使用跨域信号，亚稳态传播导致大量意外翻转
always @(posedge clk_b) begin
    data_b <= data_a;   // data_a 来自 clk_a 域，直接采样
end
```

```verilog
// ✅ 正例 — 双触发器同步器
reg [1:0] sync_ff;
always @(posedge clk_b or negedge rst_n_b) begin
    if (!rst_n_b) sync_ff <= 2'b0;
    else          sync_ff <= {sync_ff[0], data_a};
end
assign data_b_sync = sync_ff[1];
```

> 🔧 **工具提示**：SpyGlass CDC `W_CDC_*` 系列规则；Mentor CDC 工具 `clock domain crossing analysis`。

---

### LP-CDC-002：握手协议优于脉冲同步，减少跨域翻转次数

```verilog
// ✅ 正例 — 请求/确认握手，减少非必要跨域翻转
// 发送域：req 置高，等待 ack
// 接收域：检测 req，处理数据，ack 置高
// 发送域：检测 ack，req 置低（最少 2 次跨域翻转完成一次传输）
```

---

## 10 工艺相关与综合提示

### LP-SYN-001：在 RTL 注释中标注低功耗综合属性

```verilog
// ✅ 对时钟门控提示综合工具
/* synthesis clock_gating_logic */
always @(posedge clk) begin
    if (enable) q <= d;
end

// ✅ 对关键路径提示不做功耗优化
/* synthesis preserve */
reg critical_ff;
```

---

### LP-SYN-002：避免使用锁存器（Latch）

```verilog
// ❌ 反例 — 不完整的 if-else 产生意外 Latch
always @(*) begin
    if (sel)
        out = a;
    // 缺少 else，out 产生 latch —— 透明 latch 每个周期都可能导通
end
```

```verilog
// ✅ 正例 — 完整条件赋值
always @(*) begin
    if (sel) out = a;
    else     out = b;
end
```

> 🔧 **工具提示**：DC `check_design` 会报告推断的 latch；SpyGlass `W_LATCH` 规则。

---

### LP-SYN-003：多驱动（Multi-driver）和浮空（Floating）信号必须消除

```verilog
// ❌ 反例 — 信号浮空，不定态导致下游逻辑随机翻转
wire float_sig;   // 无驱动，仿真为 X，综合后随机值
```

```verilog
// ✅ 正例 — 所有信号必须有确定驱动
wire float_sig = 1'b0;   // 明确赋予稳定值
```

---

### LP-SYN-004：常量信号应直接连接 VDD/VSS，不走信号网络

```verilog
// ❌ 反例 — 常量信号通过普通连线传递，占用布线资源和翻转功耗
localparam CONST_EN = 1'b1;
assign module_en = CONST_EN;
```

```verilog
// ✅ 正例 — 在实例化时直接连接常量
submodule u_sub (
    .en(1'b1),   // 直接连 VDD，综合工具可优化掉 en 的内部逻辑
    .data(data_in)
);
```

---

## 11 检查规则速查表

| 规则 ID       | 类别     | 严重级别 | 描述                              | 推荐工具检查              |
|--------------|---------|--------|----------------------------------|------------------------|
| LP-CLK-001   | 时钟门控 | 🔴 高   | 禁止手写门控时钟表达式              | SpyGlass Clock_09       |
| LP-CLK-002   | 时钟门控 | 🔴 高   | ICG 使能必须无毛刺                  | DC check_clock_gating   |
| LP-CLK-003   | 时钟门控 | 🟡 中   | 避免 RTL 内手写分频时钟              | SpyGlass STARC_2.3.3.1  |
| LP-REG-001   | 寄存器   | 🟡 中   | 寄存器必须有有效使能条件             | Power Compiler report   |
| LP-REG-002   | 寄存器   | 🟡 中   | 宽总线寄存器按字节使能               | 代码审查                 |
| LP-REG-003   | 寄存器   | 🟡 中   | 长移位寄存器用 SRAM 替代             | 代码审查                 |
| LP-CMB-001   | 组合逻辑 | 🟡 中   | 过深组合链流水线打断                 | DC timing report        |
| LP-CMB-002   | 组合逻辑 | 🟡 中   | MUX 非选中输入操作数隔离             | SpyGlass Power_08       |
| LP-CMB-003   | 组合逻辑 | 🟢 低   | 高翻转计数器使用格雷码               | 代码审查                 |
| LP-BUS-001   | 总线     | 🟡 中   | 总线空闲时保持稳定                   | 代码审查                 |
| LP-BUS-002   | 总线     | 🟢 低   | 数据路径宽度匹配                    | 代码审查                 |
| LP-BUS-003   | 总线     | 🟡 中   | 总线 VALID 信号寄存器化              | 代码审查                 |
| LP-MEM-001   | 存储器   | 🔴 高   | SRAM 读使能精确门控                 | Liberty 功耗模型验证     |
| LP-MEM-002   | 存储器   | 🔴 高   | SRAM 写使能寄存器化防毛刺            | 代码审查 + 仿真          |
| LP-MEM-003   | 存储器   | 🟡 中   | 大容量存储器分 bank 管理             | 架构评审                 |
| LP-FSM-001   | 状态机   | 🟢 低   | 小状态机优先 one-hot 编码            | 综合报告                 |
| LP-FSM-002   | 状态机   | 🟡 中   | 状态机输出寄存器化                   | SpyGlass STARC          |
| LP-FSM-003   | 状态机   | 🟡 中   | 状态机必须有 IDLE 低功耗态           | 代码审查                 |
| LP-PD-001    | 电源域   | 🔴 高   | 跨电源域信号必须有隔离               | SpyGlass LP_01~LP_05    |
| LP-PD-002    | 电源域   | 🔴 高   | 电源开关控制来自 always-on 域        | UPF 一致性检查           |
| LP-PD-003    | 电源域   | 🔴 高   | 保持寄存器 SAVE/RESTORE 时序正确     | 功能仿真                 |
| LP-RST-001   | 复位     | 🟡 中   | 优先使用同步复位                    | 代码审查                 |
| LP-RST-002   | 复位     | 🔴 高   | 复位信号无毛刺                      | SpyGlass Reset_*        |
| LP-CDC-001   | 跨时钟域 | 🔴 高   | 跨域信号必须同步                    | SpyGlass CDC W_CDC_*    |
| LP-CDC-002   | 跨时钟域 | 🟡 中   | 握手协议优于脉冲同步                 | CDC 分析工具             |
| LP-SYN-001   | 综合     | 🟢 低   | RTL 注释标注综合属性                 | —                       |
| LP-SYN-002   | 综合     | 🔴 高   | 禁止意外 Latch                     | DC check_design         |
| LP-SYN-003   | 综合     | 🔴 高   | 消除多驱动和浮空信号                 | SpyGlass W_LATCH        |
| LP-SYN-004   | 综合     | 🟢 低   | 常量直接连 VDD/VSS                  | 综合优化报告             |

---

## 附录：低功耗设计流程建议

```
RTL 编写阶段
    ↓
[LP-CLK / LP-REG / LP-CMB 规则检查] ← SpyGlass Lint + Power
    ↓
功能仿真 + 翻转率统计 (saif/vcd 生成)
    ↓
综合（DC/Genus）+ UPF 导入
    ↓
[LP-PD / LP-CDC 规则验证] ← Conformal Low Power / VC LP
    ↓
功耗估算 (Power Compiler report_power)
    ↓
布局布线（ICC2/Innovus）+ 时钟树综合
    ↓
[LP-MEM / LP-SYN 最终验证]
    ↓
硅后测试与功耗测量对标
```

---

*本文档版本：v1.0 | 适用工艺节点：28nm 及以下 | 参考标准：STARC 低功耗编码规范、IEEE 1801 (UPF)*
