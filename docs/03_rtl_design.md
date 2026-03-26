# 第三阶段：低功耗 RTL 设计（详细版）

> 本文档是[芯片低功耗设计完整学习指南](../low_power_design_learning_guide.md)第三阶段的深入展开，覆盖所有 RTL 层面的低功耗编码技术和实战模式。

---

## 目录

- [1. Clock Gating 编码模式全集](#1-clock-gating-编码模式全集)
- [2. 操作数隔离详解](#2-操作数隔离详解)
- [3. 数据编码与总线优化](#3-数据编码与总线优化)
- [4. Memory 低功耗设计详解](#4-memory-低功耗设计详解)
- [5. 状态机低功耗设计](#5-状态机低功耗设计)
- [6. 流水线与并行度优化](#6-流水线与并行度优化)
- [7. 毛刺控制详解](#7-毛刺控制详解)
- [8. PMU 完整 RTL 设计](#8-pmu-完整-rtl-设计)
- [9. Always-On 域设计实践](#9-always-on-域设计实践)
- [10. RTL 低功耗检查清单](#10-rtl-低功耗检查清单)

---

## 1. Clock Gating 编码模式全集

### 1.1 基础 Clock Gating 推断模式

综合工具自动推断 Clock Gating 的条件：寄存器具有条件使能的写入。

```verilog
// 模式 1: if-else 条件写入（最常见）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        data_q <= '0;
    else if (wr_en)        // ← 综合工具识别为 CG enable
        data_q <= data_d;
end

// 模式 2: case 语句中的默认保持
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cfg_reg <= '0;
    else begin
        case (addr)
            ADDR_CFG0: cfg_reg <= wdata;
            // 其他地址时 cfg_reg 保持不变 → 自动推断 CG
        endcase
    end
end

// 模式 3: 多路选择器控制
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        result <= '0;
    else if (valid)
        result <= (sel == 2'b00) ? src_a :
                  (sel == 2'b01) ? src_b :
                  (sel == 2'b10) ? src_c :
                                   src_d;
end
```

### 1.2 反面模式（Anti-patterns）—— 综合工具无法推断 CG

```verilog
// 反模式 1: 无条件赋值 → 无法推断 CG
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        data_q <= '0;
    else
        data_q <= data_d;  // 每个周期都写入，无 CG 机会
end

// 修复: 添加使能条件
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        data_q <= '0;
    else if (data_valid || data_changed)  // 添加使能
        data_q <= data_d;
end


// 反模式 2: 自赋值（综合工具可能不识别）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        data_q <= '0;
    else
        data_q <= wr_en ? data_d : data_q;  // 自赋值 ← 某些工具不优化
end

// 修复: 改为 if-else
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        data_q <= '0;
    else if (wr_en)
        data_q <= data_d;
    // else 隐含保持
end


// 反模式 3: 计数器（每周期递增，但可以添加使能）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        counter <= '0;
    else
        counter <= counter + 1;  // 始终在计数 → 无 CG
end

// 修复: 添加运行使能
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        counter <= '0;
    else if (counter_en)
        counter <= counter + 1;
end
```

### 1.3 高级 Clock Gating 技术

#### 多级 Clock Gating

```verilog
// 层次化时钟门控：模块级 + 寄存器级

module sub_module (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        module_en,    // 模块级使能（控制整个模块的时钟）
    input  wire        reg_a_en,     // 寄存器A使能
    input  wire        reg_b_en,     // 寄存器B使能
    input  wire [31:0] data_a,
    input  wire [31:0] data_b,
    output reg  [31:0] reg_a,
    output reg  [31:0] reg_b
);

    // 第一级 CG：模块级
    // 当 module_en=0 时，整个模块时钟关断
    wire clk_module;
    // 综合工具自动推断此级 CG

    // 第二级 CG：寄存器级
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reg_a <= '0;
        else if (module_en && reg_a_en)  // 两级使能组合
            reg_a <= data_a;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reg_b <= '0;
        else if (module_en && reg_b_en)
            reg_b <= data_b;
    end

endmodule

// 综合工具可能优化为:
// clk → ICG1(module_en) → clk_gated → ICG2(reg_a_en) → reg_a
//                                    → ICG3(reg_b_en) → reg_b
```

#### 手动 Clock Gating（系统级）

```verilog
// 当需要对整个子系统时钟进行门控时
// 通常由 PMU 或顶层控制器管理

module sys_clock_gate (
    input  wire clk_in,        // 原始时钟
    input  wire rst_n,
    input  wire clk_en,        // 系统级使能（来自 PMU）
    input  wire scan_en,       // DFT scan enable (bypass)
    output wire clk_out        // 门控后时钟
);

    // 使用负沿锁存器避免毛刺
    reg latch_en;

    always @(*) begin
        if (!clk_in)
            latch_en <= clk_en | scan_en;
    end

    assign clk_out = clk_in & latch_en;

    // 或者例化工艺库中的标准 ICG 单元:
    // CKLNQD1 u_icg (.CP(clk_in), .E(clk_en), .TE(scan_en), .Q(clk_out));

endmodule
```

### 1.4 Clock Gating 的 DFT 考虑

```
Clock Gating 与 DFT (Design for Test) 的交互:

问题: Scan 测试时，需要时钟自由翻转来移位数据
     如果 CG enable 为 0，时钟被门控，scan chain 无法工作

解决方案: ICG 单元自带 Test Enable (TE) 端口

         ┌──────────────┐
  CLK ──→│              │
  EN  ──→│  ICG Cell    │──→ Gated CLK
  TE  ──→│ (Test Enable)│
         └──────────────┘

  Gated_CLK = CLK & Latch(EN | TE)

  正常模式: TE=0, ICG 受 EN 控制
  Scan 模式: TE=1, ICG 始终开启（旁路门控）

在综合时指定:
  set_clock_gating_style -sequential_cell latch \
      -positive_edge_logic {integrated:CKLNQD1} \
      -control_signal scan_enable
```

---

## 2. 操作数隔离详解

### 2.1 操作数隔离的基本原理

```
问题: 即使结果不被使用，运算单元的输入变化也会导致内部翻转

示例: 乘法器
┌──────┐
│      │
a ──→  │  MUL  │──→ result ──→ MUX ──→ output
b ──→  │      │            ↑
│      │         sel
└──────┘

当 sel=0 时，MUL 的结果不被使用
但如果 a 和 b 还在变化，MUL 内部大量翻转 → 浪费功耗！

解决: 当结果不被使用时，强制输入为常量（0 或保持）

┌──────┐
│ AND  │──→ a_gated ──→ ┌──────┐
a ──→  │      │           │      │
sel ──→│      │           │  MUL  │──→ result
└──────┘           b ──→  │      │
┌──────┐           └──────┘
│ AND  │──→ b_gated
b ──→  │      │
sel ──→│      │
└──────┘

sel=0: a_gated=0, b_gated=0 → MUL 输入不变 → 无翻转
sel=1: a_gated=a, b_gated=b → MUL 正常计算
```

### 2.2 操作数隔离的完整编码模式

```verilog
// ═══════════════════════════════════════════
// 模式 1: 手动操作数隔离（AND gate 方式）
// ═══════════════════════════════════════════
module alu_with_isolation (
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    input  wire [1:0]  alu_op,
    input  wire        alu_en,     // ALU 使能
    output reg  [31:0] result
);

    // 操作数隔离
    wire [31:0] a_iso = alu_en ? op_a : 32'b0;
    wire [31:0] b_iso = alu_en ? op_b : 32'b0;

    // 各运算单元也单独隔离
    wire        is_add = alu_en & (alu_op == 2'b00);
    wire        is_sub = alu_en & (alu_op == 2'b01);
    wire        is_mul = alu_en & (alu_op == 2'b10);
    wire        is_div = alu_en & (alu_op == 2'b11);

    wire [31:0] add_a = is_add ? a_iso : 32'b0;
    wire [31:0] add_b = is_add ? b_iso : 32'b0;
    wire [31:0] mul_a = is_mul ? a_iso : 32'b0;
    wire [31:0] mul_b = is_mul ? b_iso : 32'b0;

    wire [31:0] add_result = add_a + add_b;
    wire [31:0] mul_result = mul_a * mul_b;  // 乘法器只在 is_mul 时翻转

    always @(*) begin
        case (alu_op)
            2'b00: result = add_result;
            2'b10: result = mul_result;
            default: result = 32'b0;
        endcase
    end

endmodule


// ═══════════════════════════════════════════
// 模式 2: 保持型隔离（LATCH 方式）
// ═══════════════════════════════════════════
// 当不使能时保持上一次的输入值（比归零方式翻转更少）
module hold_isolation (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [31:0] data_in,
    output reg  [31:0] data_held
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_held <= '0;
        else if (enable)
            data_held <= data_in;  // 只在使能时更新
        // else 保持上次的值 → 输入不变 → 下游运算单元不翻转
    end

endmodule
```

### 2.3 综合工具自动操作数隔离

```tcl
# Design Compiler 自动操作数隔离
# 工具可以自动识别"结果不被使用的运算单元"并插入隔离逻辑

# 启用自动操作数隔离
set_operand_isolation_style -logic and     ;# 使用 AND 门隔离
# 或
set_operand_isolation_style -logic or      ;# 使用 OR 门隔离（适合高有效场景）

# 指定用于隔离的标准单元
set_operand_isolation_cell [get_lib_cells */AND2X1]

# 编译时启用
compile_ultra -gate_clock

# 检查结果
report_operand_isolation
```

### 2.4 操作数隔离的功耗收益分析

```
运算单元      无隔离时功耗    有隔离后功耗    节省比例    适合程度
──────────────────────────────────────────────────────────────
乘法器(MUL)   高（大量进位） 几乎为 0       ~95%        ★★★★★
除法器(DIV)   很高           几乎为 0       ~97%        ★★★★★
加法器(ADD)   中             几乎为 0       ~90%        ★★★★
移位器(SHIFT) 中低           几乎为 0       ~85%        ★★★
比较器(CMP)   低             接近 0         ~80%        ★★★
MUX          低             很低           ~50%        ★★

原则: 运算越复杂（门数越多），隔离收益越大
```

---

## 3. 数据编码与总线优化

### 3.1 Gray Code 详解

```verilog
// ═══════════════════════════════════════════
// Binary vs Gray Code 翻转率对比
// ═══════════════════════════════════════════
//
// Binary:  000 → 001 → 010 → 011 → 100 → 101 → 110 → 111
// 翻转位数:       1       2       1       3       1       2       1
// 平均翻转: (1+2+1+3+1+2+1)/7 = 1.57 位/次
//
// Gray:    000 → 001 → 011 → 010 → 110 → 111 → 101 → 100
// 翻转位数:       1       1       1       1       1       1       1
// 平均翻转: 1.0 位/次 (始终只翻转1位！)

// Binary 转 Gray Code
function [N-1:0] bin2gray;
    input [N-1:0] bin;
    bin2gray = bin ^ (bin >> 1);
endfunction

// Gray Code 转 Binary
function [N-1:0] gray2bin;
    input [N-1:0] gray;
    integer i;
    begin
        gray2bin[N-1] = gray[N-1];
        for (i = N-2; i >= 0; i = i - 1)
            gray2bin[i] = gray2bin[i+1] ^ gray[i];
    end
endfunction

// 应用场景:
// 1. 跨时钟域 FIFO 的读写指针（经典用法）
// 2. 地址计数器（减少地址线翻转）
// 3. 状态机编码（相邻状态只差1位）

// Gray Code 计数器
module gray_counter #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             enable,
    output wire [WIDTH-1:0] gray_out,
    output wire [WIDTH-1:0] bin_out
);

    reg [WIDTH-1:0] bin_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bin_counter <= '0;
        else if (enable)
            bin_counter <= bin_counter + 1'b1;
    end

    assign bin_out  = bin_counter;
    assign gray_out = bin_counter ^ (bin_counter >> 1);

endmodule
```

### 3.2 Bus Invert Coding

```verilog
// ═══════════════════════════════════════════
// Bus Invert Coding
// ═══════════════════════════════════════════
// 原理: 如果下一个数据与当前数据的汉明距离 > 位宽/2,
//        则取反传输，并用1位标志位指示

module bus_invert_encoder #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] data_in,
    input  wire             valid,
    input  wire             clk,
    input  wire             rst_n,
    output reg  [WIDTH-1:0] data_out,
    output reg              invert_flag  // 1=数据已取反
);

    reg [WIDTH-1:0] prev_data;
    wire [WIDTH-1:0] xor_result;
    wire [$clog2(WIDTH):0] hamming_dist;

    assign xor_result = data_in ^ prev_data;

    // 计算汉明距离（翻转位数）
    integer i;
    reg [$clog2(WIDTH):0] count;
    always @(*) begin
        count = 0;
        for (i = 0; i < WIDTH; i = i + 1)
            count = count + xor_result[i];
    end
    assign hamming_dist = count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out    <= '0;
            invert_flag <= 1'b0;
            prev_data   <= '0;
        end else if (valid) begin
            if (hamming_dist > WIDTH/2) begin
                // 翻转位数过多，取反传输
                data_out    <= ~data_in;
                invert_flag <= 1'b1;
            end else begin
                // 翻转位数可接受，正常传输
                data_out    <= data_in;
                invert_flag <= 1'b0;
            end
            prev_data <= data_in;
        end
    end

endmodule

// 理论分析:
// 无 Bus Invert: 最坏情况翻转 N 位
// 有 Bus Invert: 最坏情况翻转 N/2 位 + 1位标志
// 平均可减少 25%~30% 的总线翻转
```

### 3.3 总线空闲保持

```verilog
// ═══════════════════════════════════════════
// 总线空闲时保持（避免驱动为 0）
// ═══════════════════════════════════════════

// 不推荐: 空闲时驱动为0
// 如果上一个数据是 0xFFFFFFFF, 驱动为 0 会翻转 32 位！
assign bus_data = bus_valid ? real_data : 32'h0;  // BAD

// 推荐: 空闲时保持上一个值
reg [31:0] bus_data_q;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        bus_data_q <= '0;
    else if (bus_valid)
        bus_data_q <= real_data;
end
assign bus_data = bus_valid ? real_data : bus_data_q;  // GOOD: 保持不变
```

---

## 4. Memory 低功耗设计详解

### 4.1 SRAM 功耗模式

```
SRAM 的功耗状态:

┌──────────────┬───────────────┬────────────┬──────────────────────┐
│ 模式          │ 相对功耗      │ 数据保持   │ 恢复时间              │
├──────────────┼───────────────┼────────────┼──────────────────────┤
│ Active R/W   │ 100%          │ ✓          │ 0 (即时)             │
│ Standby      │ ~30%          │ ✓          │ 0 (即时)             │
│ Light Sleep  │ ~10%          │ ✓          │ 1~2 cycles           │
│ Deep Sleep   │ ~3%           │ ✓          │ 3~10 cycles          │
│ Shutdown     │ ~0.1%         │ ✗          │ 需重新初始化          │
└──────────────┴───────────────┴────────────┴──────────────────────┘

各模式的实现:
- Active:     CS=1, 正常读写
- Standby:    CS=0, 外围电路关断，存储阵列维持
- Light Sleep: LS=1, 降低内部电压，保持数据
- Deep Sleep:  DS=1, 进一步降压，部分外围关断
- Shutdown:    SD=1, 完全断电，数据丢失
```

### 4.2 Memory 分 Bank 设计详解

```verilog
// ═══════════════════════════════════════════
// 4-Bank SRAM 低功耗控制
// ═══════════════════════════════════════════
module memory_bank_controller #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter NUM_BANKS  = 4,
    parameter BANK_BITS  = 2   // log2(NUM_BANKS)
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // 外部访问接口
    input  wire                    access_req,
    input  wire                    write_en,
    input  wire [ADDR_WIDTH-1:0]   addr,
    input  wire [DATA_WIDTH-1:0]   wdata,
    output wire [DATA_WIDTH-1:0]   rdata,

    // 低功耗控制
    input  wire                    sleep_req,       // 请求进入低功耗
    input  wire [NUM_BANKS-1:0]    bank_force_on    // 强制某些bank保持开启
);

    // Bank 选择
    wire [BANK_BITS-1:0] bank_sel = addr[ADDR_WIDTH-1:ADDR_WIDTH-BANK_BITS];

    // 每个 Bank 的控制信号
    reg  [NUM_BANKS-1:0] bank_cs;       // Chip Select
    reg  [NUM_BANKS-1:0] bank_ls;       // Light Sleep
    reg  [NUM_BANKS-1:0] bank_ds;       // Deep Sleep

    // Bank 活跃检测 (用于自动进入低功耗)
    reg  [7:0]  bank_idle_counter [NUM_BANKS-1:0];
    wire [NUM_BANKS-1:0] bank_idle;

    genvar i;
    generate
        for (i = 0; i < NUM_BANKS; i = i + 1) begin : bank_ctrl
            // 空闲计数器: 如果一个 Bank 超过 N 个周期没被访问
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    bank_idle_counter[i] <= '0;
                else if (access_req && bank_sel == i)
                    bank_idle_counter[i] <= '0;  // 访问时清零
                else if (bank_idle_counter[i] < 8'hFF)
                    bank_idle_counter[i] <= bank_idle_counter[i] + 1'b1;
            end

            assign bank_idle[i] = (bank_idle_counter[i] >= 8'd32);  // 32周期未访问视为空闲

            // Bank 片选: 只选中需要的 Bank
            always @(*) begin
                bank_cs[i] = access_req && (bank_sel == i);
            end

            // 低功耗控制
            always @(*) begin
                if (sleep_req && !bank_force_on[i]) begin
                    bank_ls[i] = 1'b0;  // 系统sleep时进入Deep Sleep
                    bank_ds[i] = 1'b1;
                end else if (bank_idle[i] && !bank_force_on[i]) begin
                    bank_ls[i] = 1'b1;  // 空闲时进入Light Sleep
                    bank_ds[i] = 1'b0;
                end else begin
                    bank_ls[i] = 1'b0;  // 正常工作
                    bank_ds[i] = 1'b0;
                end
            end
        end
    endgenerate

    // Bank 数据选择
    wire [DATA_WIDTH-1:0] bank_rdata [NUM_BANKS-1:0];

    // 例化 SRAM (示意)
    generate
        for (i = 0; i < NUM_BANKS; i = i + 1) begin : sram_inst
            // sram_1rw u_sram (
            //     .clk     (clk),
            //     .cs      (bank_cs[i]),
            //     .we      (write_en),
            //     .addr    (addr[ADDR_WIDTH-BANK_BITS-1:0]),
            //     .wdata   (wdata),
            //     .rdata   (bank_rdata[i]),
            //     .ls      (bank_ls[i]),    // Light Sleep
            //     .ds      (bank_ds[i])     // Deep Sleep
            // );
        end
    endgenerate

    assign rdata = bank_rdata[bank_sel];

endmodule
```

### 4.3 Memory 电压缩放

```
SRAM 电压缩放面临的挑战:

1. 读稳定性 (Read Stability):
   - 读操作时，存储节点电压可能被干扰
   - 低电压下 SNM (Static Noise Margin) 减小
   - 解决: 读辅助电路 (Read Assist)

2. 写能力 (Write Ability):
   - 低电压下驱动力不足，可能写失败
   - 解决: 写辅助电路 (Write Assist)
     - Negative Bitline (NBL): 位线下拉到负电压
     - Word Line Boosting: 字线电压提升
     - Cell VDD Collapse: 短暂降低存储单元 VDD

3. 保持稳定性 (Retention):
   - 待机时降低电压可减少漏电
   - 但电压太低数据会丢失
   - 最低保持电压 (V_min_retention) 取决于工艺变异

典型 SRAM 电压范围:
┌──────────┬────────────────┬──────────────────┐
│ 模式      │ 电压范围        │ 说明              │
├──────────┼────────────────┼──────────────────┤
│ 正常读写  │ 0.7V ~ 1.0V    │ 全速访问           │
│ 降压读写  │ 0.6V ~ 0.7V    │ 低速访问 + Assist  │
│ 保持模式  │ 0.4V ~ 0.6V    │ 不可访问，仅保持    │
│ 关断      │ 0V             │ 数据丢失           │
└──────────┴────────────────┴──────────────────┘
```

---

## 5. 状态机低功耗设计

### 5.1 状态编码对比

```verilog
// ═══════════════════════════════════════════
// 5 个状态的 FSM 编码方式对比
// ═══════════════════════════════════════════

// Binary 编码: 面积最小，但翻转率高
// S0=000, S1=001, S2=010, S3=011, S4=100
// S0→S1: 1 bit 翻转
// S1→S2: 2 bits 翻转
// S3→S4: 3 bits 翻转 ← 最坏情况

// Gray 编码: 相邻状态仅 1 bit 翻转
// S0=000, S1=001, S2=011, S3=010, S4=110
// 任意相邻: 1 bit 翻转 ← 最优

// One-Hot 编码: 只有 2 bits 翻转（一个置1，一个清0）
// S0=00001, S1=00010, S2=00100, S3=01000, S4=10000
// 任意转换: 2 bits 翻转
// 优点: 翻转率固定，解码简单，组合逻辑快
// 缺点: 需要更多寄存器位

// 编码方式选择指南:
// ┌──────────────┬────────┬────────────┬───────────────┐
// │ 编码方式      │ 位宽    │ 平均翻转    │ 推荐场景       │
// ├──────────────┼────────┼────────────┼───────────────┤
// │ Binary       │ log2(N)│ 较高       │ 状态数多(>16)  │
// │ Gray         │ log2(N)│ 最低(1bit) │ 顺序转换为主   │
// │ One-Hot      │ N      │ 固定(2bit) │ 状态数少(<16)  │
// │ 定制编码     │ 可变    │ 可优化     │ 特殊转换模式   │
// └──────────────┴────────┴────────────┴───────────────┘
```

### 5.2 低功耗状态机设计示例

```verilog
// ═══════════════════════════════════════════
// 带低功耗控制的数据处理 FSM
// ═══════════════════════════════════════════
module low_power_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        data_valid,
    input  wire [31:0] data_in,
    output reg  [31:0] result,
    output reg         result_valid,
    output reg         busy,

    // 低功耗控制输出
    output reg         datapath_en,    // 数据通路使能
    output reg         mem_access_en,  // Memory 访问使能
    output reg         output_en       // 输出使能
);

    // One-Hot 编码 (低功耗友好)
    localparam S_IDLE    = 5'b00001;
    localparam S_LOAD    = 5'b00010;
    localparam S_PROCESS = 5'b00100;
    localparam S_STORE   = 5'b01000;
    localparam S_DONE    = 5'b10000;

    reg [4:0] state, next_state;

    // 状态寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // 下一状态逻辑 + 低功耗使能控制
    always @(*) begin
        // 默认值：所有使能关闭（低功耗友好）
        next_state   = state;
        datapath_en  = 1'b0;
        mem_access_en = 1'b0;
        output_en    = 1'b0;
        busy         = 1'b1;
        result_valid = 1'b0;

        case (1'b1)  // One-Hot synthesis style
            state[0]: begin  // S_IDLE
                busy = 1'b0;
                // 空闲状态：所有使能为0，功耗最低
                if (start)
                    next_state = S_LOAD;
            end

            state[1]: begin  // S_LOAD
                mem_access_en = 1'b1;  // 仅开启 Memory
                if (data_valid)
                    next_state = S_PROCESS;
            end

            state[2]: begin  // S_PROCESS
                datapath_en = 1'b1;    // 仅开启数据通路
                next_state = S_STORE;
            end

            state[3]: begin  // S_STORE
                mem_access_en = 1'b1;  // 仅开启 Memory
                output_en     = 1'b1;  // 开启输出
                next_state = S_DONE;
            end

            state[4]: begin  // S_DONE
                output_en    = 1'b1;
                result_valid = 1'b1;
                next_state   = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule

// 低功耗收益分析:
// 传统设计: datapath 和 memory 始终使能
// 优化设计: 每个状态只使能需要的资源
//
// S_IDLE:    0% 资源使能 (最低功耗)
// S_LOAD:    Memory ON, Datapath OFF (节省 datapath 功耗)
// S_PROCESS: Datapath ON, Memory OFF (节省 memory 功耗)
// S_STORE:   Memory + Output ON
// S_DONE:    Output ON
```

---

## 6. 流水线与并行度优化

### 6.1 流水线降压降频优化

```
原理: 插入流水线可以提高频率，但我们可以反过来利用——
      保持同样吞吐率，降低频率和电压。

无流水线:
  ┌──────────────────────────────────────┐
  │         组合逻辑 (延迟 = T)          │
  └──────────────────────────────────────┘
  频率 = 1/T, 电压 = V_DD
  功耗 = C × V_DD² × (1/T)

2 级流水线:
  ┌──────────────────┐ ┌──────────────────┐
  │  Stage 1 (T/2)   │→│  Stage 2 (T/2)   │
  └──────────────────┘ └──────────────────┘
  
  选择1: 提高频率 → 频率 = 2/T (性能翻倍)
  选择2: 保持吞吐率，降频降压
         频率 = 1/T (不变)
         电压可以降低 (因为每级延迟余量大)
         设电压降为 0.7V_DD
         功耗 = 2C × (0.7V_DD)² × (1/T) = 0.98 × C × V_DD² × (1/T)
         加上流水线寄存器增加 ~10% 功耗
         总功耗 ≈ 原来的 ~60% (因为 V² 效应)

结论: 用面积换功耗，2级流水线可节省约 40% 功耗！
```

### 6.2 并行化降功耗

```
原理: N 个并行单元，每个以 1/N 频率运行

单路 @ f, V_DD:
  P_single = C × V_DD² × f

N 路并行 @ f/N, V_low:
  (V_low 可以更低，因为频率要求低)
  设 V_low = V_DD × √(1/N)  (简化假设)
  P_parallel = N × C × V_low² × (f/N)
             = N × C × (V_DD²/N) × (f/N)
             = C × V_DD² × f / N
             = P_single / N

理论上：N 路并行可以将功耗降低到 1/N（忽略额外开销）
实际上：考虑互连、控制逻辑等开销，2~4 路并行效果最好
```

---

## 7. 毛刺控制详解

### 7.1 毛刺产生的原因

```
组合逻辑中，不同输入路径延迟不同导致中间翻转

示例: F = A & B

路径延迟:
  A: 经过 3 级逻辑，延迟 3ns
  B: 经过 1 级逻辑，延迟 1ns

时序:
A(旧=1) ──────────────┐         (3ns延迟)
                       └── A(新=0)

B(旧=0) ──────┐                  (1ns延迟)
              └── B(新=1)

F = A & B:
t=0:   F = 1 & 0 = 0
t=1ns: F = 1 & 1 = 1  ← B先到，产生毛刺脉冲！
t=3ns: F = 0 & 1 = 0  ← A后到，F回到正确值

F: 0──┐  ┌──0   ← 毛刺宽度约2ns
      └──┘
      1 (glitch!)

这个毛刺会向下游传播，每一级都可能产生新的毛刺
→ 深层组合逻辑中毛刺呈指数增长
```

### 7.2 毛刺消除技术

```verilog
// 技术 1: 插入流水线寄存器（截断毛刺传播）
// 组合逻辑深度超过 4-5 级时考虑

// 技术 2: 平衡路径延迟
// 在综合阶段，工具可以通过 buffer 插入平衡路径

// 技术 3: 重新编码减少翻转
// 例如使用 Gray Code 代替 Binary

// 技术 4: 对毛刺敏感的输出加寄存器采样
module glitch_free_output (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        combo_output,  // 组合逻辑输出（可能有毛刺）
    output reg         clean_output   // 无毛刺输出
);
    // 用寄存器采样，消除毛刺
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clean_output <= 1'b0;
        else
            clean_output <= combo_output;
    end
endmodule

// 技术 5: 门控时钟消除时钟毛刺
// 使用 ICG 确保门控时钟无毛刺（前面已详述）
```

---

## 8. PMU 完整 RTL 设计

### 8.1 PMU Power Domain Controller

```verilog
// ═══════════════════════════════════════════
// 单个 Power Domain 控制器
// ═══════════════════════════════════════════
module pd_controller (
    input  wire clk,
    input  wire rst_n,

    // 控制接口
    input  wire pd_on_req,        // 开域请求
    input  wire pd_off_req,       // 关域请求
    output reg  pd_is_on,         // 域状态
    output reg  pd_busy,          // 正在切换

    // Power Switch 控制
    output reg  power_switch_en,  // 电源开关使能
    input  wire power_switch_ack, // 电源开关稳定确认

    // Isolation 控制
    output reg  iso_enable,       // 隔离使能（高有效）

    // Retention 控制
    output reg  ret_save,         // 保存触发
    output reg  ret_restore,      // 恢复触发

    // Clock 控制
    output reg  clk_enable,       // 时钟使能

    // 计时器
    output reg  [15:0] timer_cnt  // 通用延时计时器
);

    // 状态定义
    localparam PD_ON         = 4'd0;
    localparam PD_SAVE       = 4'd1;  // Retention Save
    localparam PD_CLK_OFF    = 4'd2;  // 关闭时钟
    localparam PD_ISOLATE    = 4'd3;  // 使能隔离
    localparam PD_SW_OFF     = 4'd4;  // 关断电源开关
    localparam PD_OFF        = 4'd5;  // 完全关断
    localparam PD_SW_ON      = 4'd6;  // 开启电源开关
    localparam PD_WAIT_STAB  = 4'd7;  // 等待电源稳定
    localparam PD_RESTORE    = 4'd8;  // Retention Restore
    localparam PD_DEISOLATE  = 4'd9;  // 取消隔离
    localparam PD_CLK_ON     = 4'd10; // 恢复时钟

    reg [3:0] state, next_state;

    // 主状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= PD_ON;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            PD_ON:
                if (pd_off_req) next_state = PD_SAVE;

            PD_SAVE:
                if (timer_cnt == 16'd2)  // Save 持续 2 个周期
                    next_state = PD_CLK_OFF;

            PD_CLK_OFF:
                next_state = PD_ISOLATE;  // 关闭时钟后立即隔离

            PD_ISOLATE:
                if (timer_cnt == 16'd1)   // 隔离稳定 1 个周期
                    next_state = PD_SW_OFF;

            PD_SW_OFF:
                if (power_switch_ack)     // 等待 power switch 完全关断
                    next_state = PD_OFF;

            PD_OFF:
                if (pd_on_req) next_state = PD_SW_ON;

            PD_SW_ON:
                if (power_switch_ack)     // 等待 power switch 开启
                    next_state = PD_WAIT_STAB;

            PD_WAIT_STAB:
                if (timer_cnt == 16'd100) // 等待电源稳定 (可配置)
                    next_state = PD_RESTORE;

            PD_RESTORE:
                if (timer_cnt == 16'd2)   // Restore 持续 2 个周期
                    next_state = PD_DEISOLATE;

            PD_DEISOLATE:
                next_state = PD_CLK_ON;

            PD_CLK_ON:
                next_state = PD_ON;

            default: next_state = PD_ON;
        endcase
    end

    // 输出逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            power_switch_en <= 1'b1;   // 默认开启
            iso_enable      <= 1'b0;   // 默认不隔离
            ret_save        <= 1'b0;
            ret_restore     <= 1'b0;
            clk_enable      <= 1'b1;   // 默认时钟开启
            pd_is_on        <= 1'b1;
            pd_busy         <= 1'b0;
        end else begin
            // 默认值
            ret_save    <= 1'b0;
            ret_restore <= 1'b0;
            pd_busy     <= (state != PD_ON) && (state != PD_OFF);

            case (state)
                PD_SAVE:     ret_save        <= 1'b1;
                PD_CLK_OFF:  clk_enable      <= 1'b0;
                PD_ISOLATE:  iso_enable       <= 1'b1;
                PD_SW_OFF:   power_switch_en  <= 1'b0;
                PD_OFF:      pd_is_on         <= 1'b0;
                PD_SW_ON:    power_switch_en  <= 1'b1;
                PD_RESTORE:  ret_restore      <= 1'b1;
                PD_DEISOLATE: iso_enable      <= 1'b0;
                PD_CLK_ON: begin
                    clk_enable <= 1'b1;
                    pd_is_on   <= 1'b1;
                end
            endcase
        end
    end

    // 通用计时器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timer_cnt <= '0;
        else if (state != next_state)
            timer_cnt <= '0;      // 状态切换时清零
        else
            timer_cnt <= timer_cnt + 1'b1;
    end

endmodule
```

---

## 9. Always-On 域设计实践

### 9.1 Always-On 域的模块列表

```
Always-On Domain 典型包含:
┌──────────────────────────────────────────────────┐
│ Always-On Domain                                  │
│                                                   │
│ ┌──────────┐  关键: 控制其他所有域的上下电          │
│ │ PMU      │  包含: 状态机、寄存器、PMIC接口        │
│ └──────────┘                                      │
│                                                   │
│ ┌──────────┐  功能: 低功耗下仍可接收中断唤醒       │
│ │ Wakeup   │  包含: 中断检测、GPIO唤醒、RTC闹钟    │
│ │ Logic    │                                      │
│ └──────────┘                                      │
│                                                   │
│ ┌──────────┐  功能: 保持系统时间基准               │
│ │ RTC      │  使用: 32.768 kHz 低频时钟            │
│ └──────────┘                                      │
│                                                   │
│ ┌──────────┐  功能: 防止系统死锁                   │
│ │ Watchdog │  即使主处理器关断也能检测异常          │
│ └──────────┘                                      │
│                                                   │
│ ┌──────────┐  功能: 电压/温度监测                  │
│ │ Monitors │  包含: PVT sensor, thermal sensor     │
│ └──────────┘                                      │
│                                                   │
│ ┌──────────┐  功能: 唤醒用GPIO（最少的引脚）       │
│ │ AON GPIO │  通常只有几个关键引脚                  │
│ └──────────┘                                      │
│                                                   │
│ ┌──────────┐  功能: 安全相关的密钥/状态保持         │
│ │ Security │  包含: OTP控制器、安全状态             │
│ │ State    │                                      │
│ └──────────┘                                      │
│                                                   │
│ 设计约束:                                          │
│ - 总面积 < 芯片面积的 5%                            │
│ - 总功耗 < 50μW (目标)                             │
│ - 全部使用 HVT 单元                                │
│ - 使用最低工作电压                                  │
│ - 时钟频率: 32kHz (RTC) / 低频 IRC                 │
└──────────────────────────────────────────────────┘
```

---

## 10. RTL 低功耗检查清单

### 10.1 代码审查 Checklist

```
RTL 低功耗代码审查清单:

寄存器:
□ 所有寄存器都有使能条件？(可推断 Clock Gating)
□ 没有无条件的自赋值？(data_q <= en ? data_d : data_q)
□ 计数器有使能信号？
□ 没有不必要的寄存器初始化翻转？

运算单元:
□ 不使用时输入被隔离？(操作数隔离)
□ 乘法器/除法器有使能控制？
□ ALU 各运算单元独立使能？

Memory:
□ 使用 Bank 划分？
□ 有 Light Sleep / Deep Sleep 控制？
□ 读写使能信号完备？
□ 无效访问被阻止？

总线:
□ 空闲时保持上一值（不驱动为0）？
□ 地址使用 Gray Code？
□ 考虑 Bus Invert Coding？

状态机:
□ 使用合适的编码方式？(One-Hot / Gray)
□ 每个状态只使能需要的资源？
□ 空闲状态关闭所有不需要的模块？

组合逻辑:
□ 关键路径毛刺是否受控？
□ 深层组合逻辑是否需要流水线？
□ MUX 树是否优化？

时钟:
□ 手动 ICG 使用正确的锁存器型？
□ DFT bypass 信号（TE）正确连接？
□ 无组合逻辑生成的时钟？

低功耗控制:
□ PMU 控制信号完备？
□ 隔离/保持控制时序正确？
□ 唤醒路径延迟满足要求？
```

---

> 返回 [主学习指南](../low_power_design_learning_guide.md) | 上一章 ← [低功耗架构设计详解](02_architecture.md) | 下一章 → [UPF 验证详解](04_upf_verification.md)
