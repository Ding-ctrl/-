# Copilot Instructions

## 低功耗 Verilog 编码约束

### 1. 时钟门控（Clock Gating）

- **必须**使用时钟门控单元（ICG，Integrated Clock Gating Cell）来关闭空闲模块的时钟，禁止在 RTL 中直接用组合逻辑对 `clk` 做 AND/OR 操作。
- ICG 例化格式统一如下，`en` 信号必须为寄存器输出，不得为纯组合逻辑：

```verilog
// 推荐：使用标准 ICG 单元
CKLNQD1 u_icg (
    .CP  (clk),
    .E   (clk_en_r),   // 寄存器输出的使能信号
    .TE  (1'b0),       // 测试使能，由扫描链控制
    .Q   (clk_gated)
);
```

- 颗粒度要求：尽量在子模块入口处添加时钟门控，避免全局时钟始终翻转。

---

### 2. 操作数隔离（Operand Isolation）

- 对于大位宽的组合运算单元（乘法器、加法器等），当结果不被使用时，**必须**对输入操作数进行门控置零，防止无效翻转产生动态功耗：

```verilog
// 推荐：操作数隔离
assign mult_a = op_valid ? data_a : {WIDTH{1'b0}};
assign mult_b = op_valid ? data_b : {WIDTH{1'b0}};
assign result = mult_a * mult_b;
```

---

### 3. 寄存器使能（Register Enable）

- 寄存器在数据不更新时**必须**保持原值（使用 `load_en` 控制），禁止每拍无条件写入相同数据：

```verilog
// 推荐：带使能的寄存器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        data_r <= '0;
    else if (load_en)
        data_r <= data_in;
    // 无 else 分支，寄存器保持原值
end
```

---

### 4. 减少毛刺（Glitch Reduction）

- 组合逻辑深度不得超过 **8 个逻辑级（logic levels）**，超出时须插入流水线寄存器以减少毛刺翻转。
- 优先使用格雷码（Gray Code）对状态机和计数器编码，降低每次状态转移时的翻转位数：

```verilog
// 推荐：格雷码计数器（以4位为例）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) gray_cnt <= 4'b0000;
    else        gray_cnt <= (bin_cnt >> 1) ^ bin_cnt; // 由二进制转格雷码
end
```

---

### 5. 电源域与多电压（Power Domain / Multi-Voltage）

- 跨电源域信号**必须**插入电平转换器（Level Shifter），并在信号名后缀 `_ls` 以便识别。
- 进入掉电域（power-off domain）的信号**必须**经过隔离单元（Isolation Cell），隔离使能信号命名为 `iso_en`：

```verilog
// 推荐：显式标注隔离使能
assign data_to_off_domain = iso_en ? 1'b0 : data_internal;
```

- RTL 文件头部注释中**必须**声明该模块所属电源域，例如：

```verilog
// Module  : my_block
// Domain  : VDD_CORE (always-on: VDD_AON)
// Voltage : 0.75V ~ 1.1V
```

---

### 6. 低功耗状态机（FSM）

- 状态机编码默认使用 **one-hot** 或 **格雷码**，禁止在高翻转路径上使用二进制编码。
- 状态机在 IDLE 状态时，应关闭所有非必要的时钟门控和操作数隔离使能。

---

### 7. 存储器（Memory / SRAM）

- 读写使能信号必须精确控制，**禁止**在不需要读写时拉高 `mem_en` 或 `wen`。
- 对于多 bank SRAM，根据访问地址仅激活对应 bank，其余 bank 保持低功耗（light-sleep / shut-down）模式。

---

### 8. 代码风格通用要求

| 条目 | 要求 |
|------|------|
| 命名 | 低功耗相关信号以 `_lp`、`_pg`（power gate）、`_iso`、`_ls` 后缀区分 |
| 注释 | 每个 ICG、隔离单元、电平转换器必须有单行注释说明其所在电源域 |
| 参数化 | 位宽、电压档位等使用 `parameter` / `localparam`，禁止 magic number |
| 仿真 | RTL 仿真必须开启功耗感知仿真（如 `$power_toggle_log`）以验证门控效果 |
| Lint | 提交前须通过低功耗相关 lint 规则（如 Spyglass LPHD ruleset） |

