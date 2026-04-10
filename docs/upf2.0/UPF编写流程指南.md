# UPF 编写流程指南 — 层次化多文件架构（从架构到硅片）

> **按 Power Domain 划分独立 UPF 文件 → Top UPF 通过 `load_upf` 读取并用 `connect_supply_net` 自顶向下连接电源**
>
> 每一步都说明：UPF 命令 → RTL 设计注意事项 → 物理实现注意事项

---

## 总览：层次化 UPF 文件架构

### 为什么要分文件？

大型 SoC 的低功耗设计涉及数十个电源域。如果把所有域的 UPF 写在一个文件中：
- 文件臃肿、维护困难
- 子系统 IP 复用时需要手动复制粘贴
- 多团队并行开发容易冲突

**层次化方案**：每个子系统/Power Domain 有独立的 UPF 文件，顶层 UPF 通过 `load_upf` 加载各子系统 UPF，再用 `connect_supply_net` 将顶层电源网络连接到子系统的供电端口。

### 文件组织结构

```
upf/
├── soc_top.upf              ← 顶层 UPF（加载子系统 + 全局电源连接）
├── cpu_subsys.upf            ← CPU 子系统 UPF（PD_CPU, PD_CORE0-3）
├── gpu_subsys.upf            ← GPU 子系统 UPF（PD_GPU）
├── npu_subsys.upf            ← NPU 子系统 UPF（PD_NPU）
└── peri_subsys.upf           ← 外设子系统 UPF（PD_PERI）
```

### 数据流示意

```
                     soc_top.upf
                    ┌─────────────────────────────────────────────┐
                    │ upf_version 2.0                              │
                    │                                              │
                    │ ① 顶层域 + 全局供电网络                       │
                    │ ② load_upf cpu_subsys.upf -scope u_cpu_subsys│
                    │    → connect_supply_net VDD/VSS 到子系统端口  │
                    │ ③ load_upf gpu_subsys.upf -scope u_gpu       │
                    │    → connect_supply_net VDD/VSS 到子系统端口  │
                    │ ④ load_upf npu_subsys.upf -scope u_npu       │
                    │    → connect_supply_net VDD/VSS 到子系统端口  │
                    │ ⑤ load_upf peri_subsys.upf -scope u_peri     │
                    │    → connect_supply_net VDD/VSS 到子系统端口  │
                    │ ⑥ 顶层电源状态 + 仿真行为                     │
                    └─────────────────────────────────────────────┘
                         │          │          │          │
                    ┌────▼───┐ ┌───▼────┐ ┌───▼────┐ ┌───▼────┐
                    │cpu_sub │ │gpu_sub │ │npu_sub │ │peri_sub│
                    │sys.upf │ │sys.upf │ │sys.upf │ │sys.upf │
                    │        │ │        │ │        │ │        │
                    │ 域定义  │ │ 域定义  │ │ 域定义  │ │ 域定义  │
                    │ 供电端口│ │ 供电端口│ │ 供电端口│ │ 供电端口│
                    │ 开关    │ │ 开关    │ │ 开关    │ │ 开关    │
                    │ 隔离    │ │ 隔离    │ │ 隔离    │ │ 隔离    │
                    │ Retention│ │ LS     │ │        │ │        │
                    └────────┘ └────────┘ └────────┘ └────────┘
```

---

## 编写顺序总览

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  Phase A: 子系统 UPF（各团队并行编写）                                  │
│  ─────────────────────────────────────                                │
│  Step 1   UPF 版本声明                                                │
│  Step 2   子系统供电端口 (create_supply_port) ← 从顶层接入电源         │
│  Step 3   电源域定义 (create_power_domain)                            │
│  Step 4   供电网络 + 供电连接 (create_supply_net / connect_supply_net)│
│  Step 5   供电集合 (create_supply_set)            ← UPF 2.0          │
│  Step 6   电源开关 (create_power_switch)                              │
│  Step 7   隔离策略 (set_isolation + set_isolation_control)            │
│           + 隔离单元映射 (map_isolation_cell)                         │
│  Step 8   电平转换 (set_level_shifter)                                │
│  Step 9   状态保持 (set_retention + map_retention_cell)               │
│  Step 10  电源状态 + 仿真行为 (add_power_state / set_simstate)        │
│                                                                      │
│  Phase B: 顶层 UPF（SoC 集成团队编写）                                 │
│  ─────────────────────────────────────                                │
│  Step 11  顶层域 + 全局供电网络                                        │
│  Step 12  load_upf 加载子系统 + connect_supply_net 跨层次连接          │
│  Step 13  顶层电源状态 + 全局仿真行为                                  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

# Phase A：子系统 UPF 编写（以 CPU 子系统为例）

> 以 `cpu_subsys.upf` 为例，展示子系统级 UPF 的完整编写流程。
> GPU、NPU、外设子系统同理。

---

## Step 1：UPF 版本声明

### UPF 命令

```tcl
# ================================================================
# File: cpu_subsys.upf
# Description: CPU Subsystem UPF (独立子系统文件)
# Scope: u_cpu_subsys
# ================================================================
upf_version 2.0
```

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | 版本声明不影响 RTL，但决定了后续可用的命令集。每个子系统 UPF 文件的版本必须与顶层一致 |
| **物理实现** | 确认 EDA 工具链（DC/ICC2/Innovus）支持所选版本。所有文件版本必须统一——混合版本会导致语义冲突 |
| **常见错误** | ① 忘写版本声明<br>② 子系统 UPF 与顶层 UPF 版本不一致 |

---

## Step 2：子系统供电端口 — `create_supply_port`

### UPF 命令

```tcl
# ---- 从顶层接入的电源端口 ----
# 这些端口是子系统的"电源接口"，由顶层 UPF 通过 connect_supply_net 连接
create_supply_port VDD  -direction in    ;# 从顶层接入的主电源 0.9V
create_supply_port VSS  -direction in    ;# 从顶层接入的主地线
```

### 说明

在层次化设计中，子系统 UPF 必须声明**从父层级接入的供电端口**。这些端口是子系统的电源入口——类似 RTL 模块的输入端口，但描述的是电源而非信号。

顶层 UPF 在 `load_upf` 后会通过 `connect_supply_net` 将全局电源网络（VDD/VSS）连接到这些端口。

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① 供电端口不出现在 RTL 中，是 UPF 专属描述<br>② 端口命名需要与顶层约定一致——顶层 `connect_supply_net` 会引用这些端口名<br>③ RTL 子系统模块只有信号端口，电源由 UPF 描述；但设计师需知道本子系统接入几路电源 |
| **物理实现** | ① 子系统供电端口对应物理上从上层电源网格进入子系统区域的**电源走线入口**<br>② 在 P&R 中，子系统的 Power Ring 从这些端口接收电源<br>③ 多电压子系统（如 CPU 子系统同时需要 VDD 和 VDD_RET）需要声明多个端口 |
| **常见错误** | ① 忘记声明供电端口——导致顶层 `connect_supply_net` 无目标<br>② 端口 direction 写成 `out`——子系统是电源的接收方，应为 `in`<br>③ 端口名与顶层 `connect_supply_net` 中引用的名称不匹配 |

---

## Step 3：子系统电源域定义 — `create_power_domain`

### UPF 命令

```tcl
# 子系统顶层域（子系统内的常开逻辑，如 L2 Cache、总线接口）
create_power_domain PD_CPU -include_scope \
    -supply {primary SS_CPU}

# 各 CPU 核心独立域（支持大小核独立关断）
create_power_domain PD_CORE0 -elements {u_core0} \
    -supply {primary SS_CORE0}   ;# A55 小核
create_power_domain PD_CORE1 -elements {u_core1} \
    -supply {primary SS_CORE1}   ;# A55 小核
create_power_domain PD_CORE2 -elements {u_core2} \
    -supply {primary SS_CORE2}   ;# A76 大核
create_power_domain PD_CORE3 -elements {u_core3} \
    -supply {primary SS_CORE3}   ;# A76 大核
```

### 说明

在子系统 UPF 中，`-elements` 路径是**相对于子系统作用域**的。例如 `u_core0` 是相对于 `u_cpu_subsys` 的路径，不需要写全路径 `u_cpu_subsys/u_core0`——这是由顶层 `load_upf -scope u_cpu_subsys` 自动确定的。

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① `-elements` 路径是**相对于子系统模块顶层**的，不是全局路径<br>② 子系统 RTL 中，`u_core0`~`u_core3` 必须是子系统模块的直接或间接实例<br>③ 子系统常开域用 `-include_scope` 包含未分配的逻辑（如 L2 Cache、总线桥）<br>④ UPF 2.0 推荐在创建域时通过 `-supply {primary SS_XXX}` 直接绑定供电集合 |
| **物理实现** | ① 子系统内的各域对应 Floorplan 中子系统区域内的**子分区**<br>② 各核心域之间需要留 **guard band**（通常 5-20μm）<br>③ 子系统总面积 = 各核心域面积 + L2 Cache + 域间 guard band + Power Switch 面积<br>④ 子系统内的常开逻辑（L2 Cache 等）放在子系统中心，便于与各核心域互连 |
| **常见错误** | ① 路径写成全局路径（如 `u_cpu_subsys/u_core0`）——在子系统 UPF 中应写 `u_core0`<br>② 忘记创建子系统顶层域（`-include_scope`），导致 L2 Cache 等逻辑无域归属 |

---

## Step 4：供电网络与连接

### UPF 命令

```tcl
# ---- 常开供电网络（来自顶层） ----
create_supply_net VDD  -domain PD_CPU
create_supply_net VSS  -domain PD_CPU

# 连接子系统供电端口到内部网络
connect_supply_net VDD  -ports {VDD}
connect_supply_net VSS  -ports {VSS}

# ---- 可切换供电网络（由各核心的 Power Switch 驱动） ----
create_supply_net VDD_SW_CORE0 -domain PD_CORE0
create_supply_net VDD_SW_CORE1 -domain PD_CORE1
create_supply_net VDD_SW_CORE2 -domain PD_CORE2
create_supply_net VDD_SW_CORE3 -domain PD_CORE3
```

### 说明

子系统内的供电网络分为两类：
1. **常开网络**（VDD/VSS）：从子系统供电端口接入，贯穿整个子系统
2. **可切换网络**（VDD_SW_COREn）：由子系统内的 Power Switch 输出驱动

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① 供电网络不在 RTL 中出现<br>② 但 RTL 设计师需要理解：各核心接可切换电源（可关断），L2 Cache 接常开电源（不关断） |
| **物理实现** | ① 常开网络从子系统供电端口经 Power Ring 进入，作为 Power Switch 的输入<br>② 可切换网络从 Power Switch 输出端驱动域内 Power Mesh<br>③ 两类网络**物理隔离**——通过 Power Switch 连接<br>④ 命名规范：`VDD_SW_` 前缀标识可切换网络 |
| **常见错误** | ① 忘记把子系统供电端口 `connect_supply_net` 到内部网络<br>② 可切换网络忘记指定 `-domain` |

---

## Step 5：供电集合 — `create_supply_set`

### UPF 命令

```tcl
# 子系统常开供电集合
create_supply_set SS_CPU \
    -function {power VDD} \
    -function {ground VSS}

# 各核心可切换供电集合
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

# 常开供电集合（用于隔离/Retention 单元供电）
create_supply_set SS_ALWAYS_ON \
    -function {power VDD} \
    -function {ground VSS}
```

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① 无直接影响<br>② 命名规范 `PD_XXX` → `SS_XXX` 便于追踪域与供电集合的对应关系 |
| **物理实现** | ① `SS_ALWAYS_ON` 必须指向常开网络 VDD——隔离/Retention 单元由常开电源供电<br>② 后端工具通过 Supply Set 自动关联隔离和 Retention 单元的供电来源 |
| **常见错误** | ① `SS_CORE0` 的 power 错误指向常开 VDD 而非 `VDD_SW_CORE0`<br>② 忘记创建 `SS_ALWAYS_ON` |

---

## Step 6：电源开关 — `create_power_switch`

### UPF 命令

```tcl
# Core0 电源开关
create_power_switch SW_CORE0 \
    -domain PD_CORE0 \
    -input_supply_port  {vin  VDD} \
    -output_supply_port {vout VDD_SW_CORE0} \
    -control_port       {ctrl pmu_core0_pwr_en} \
    -on_state           {on vin {ctrl}} \
    -ack_port           {ack pmu_core0_pwr_ack {on}}

# Core1-3 类似...
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
```

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① `-control_port` 中的信号（如 `pmu_core0_pwr_en`）必须在子系统 RTL 中存在<br>② 这些控制信号通常由子系统内部的电源控制器（或从顶层 PMU 传入）驱动<br>③ control 和 ack 信号必须属于子系统的**常开域** PD_CPU（不能放在被关断的核心域内！）<br>④ PMU 的上电/断电序列必须正确：save → iso_en → power_off → ... → power_on → restore → iso_dis |
| **物理实现** | ① Header Switch (PMOS) 放在 VDD 侧，串联在 VDD → Virtual VDD 路径上<br>② 开关管面积通常占域面积的 **5-15%**<br>③ 开关管要求**均匀分布**，避免 IR drop 不均匀<br>④ 上电瞬间 **rush current** 通过 daisy-chain 分级导通控制 |
| **常见错误** | ① `-on_state` 的布尔表达式使用 control_port 端口名 `ctrl` 而非信号名<br>② 忘记 `-ack_port`<br>③ 在子系统 UPF 中引用了顶层的信号路径 |

### 上电/断电时序（RTL PMU 必须实现）

```
断电序列:
  1. PMU 发出 save 信号 → Retention FF 保存状态
  2. PMU 使能隔离 (iso_en = 1)
  3. PMU 关断 Power Switch (pwr_en = 0)
  4. 等待 ack 确认关断完成

上电序列:
  1. PMU 打开 Power Switch (pwr_en = 1) — 分级导通
  2. 等待 ack 确认上电稳定
  3. PMU 发出 restore 信号 → Retention FF 恢复状态
  4. PMU 撤销隔离 (iso_en = 0)
  5. 核心恢复运行
```

---

## Step 7：隔离策略 — `set_isolation` + `set_isolation_control` + `map_isolation_cell`

### 7a. 隔离策略定义 — `set_isolation`

```tcl
# 各核心输出隔离
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

# AXI 总线信号特殊处理（锁存最后值避免协议违规）
set_isolation iso_core0_axi \
    -domain PD_CORE0 \
    -elements {u_core0/axi_*} \
    -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value latch \
    -applies_to outputs
```

### 7b. 隔离控制信号 — `set_isolation_control` ⭐

> **`set_isolation` 只声明了"需要隔离"和"钳位值"，但没有指定是哪个信号控制隔离单元的使能。`set_isolation_control` 补充了这一关键信息——告诉 EDA 工具用哪个信号、什么极性来控制隔离单元。**

#### 命令语法

```tcl
set_isolation_control isolation_name
    -domain domain_name
    -isolation_signal signal_name
    -isolation_sense {high | low}
    [-location {self | parent | sibling | fanout | ...}]
```

#### 参数说明

| 参数 | 含义 | 说明 |
|------|------|------|
| `isolation_name` | 关联的隔离策略名称 | 必须与 `set_isolation` 中定义的名称一致 |
| `-domain` | 应用的电源域 | 必须与 `set_isolation` 中的 `-domain` 一致 |
| `-isolation_signal` | 控制隔离使能的信号 | 该信号**必须属于常开域**（否则域关断后控制信号也丢失） |
| `-isolation_sense high` | 高有效隔离 | 信号为 1 时正常通过，为 0 时钳位（AND 型隔离单元） |
| `-isolation_sense low` | 低有效隔离 | 信号为 0 时正常通过，为 1 时钳位（OR 型隔离单元） |
| `-location` | 隔离单元放置位置 | `self`=源域内, `parent`=父域/接收域侧（推荐） |

#### UPF 命令

```tcl
# 每个 set_isolation 必须配对一个 set_isolation_control
set_isolation_control iso_core0 \
    -domain PD_CORE0 \
    -isolation_signal pmu_core0_iso_en \
    -isolation_sense high \
    -location parent

set_isolation_control iso_core1 \
    -domain PD_CORE1 \
    -isolation_signal pmu_core1_iso_en \
    -isolation_sense high \
    -location parent

set_isolation_control iso_core2 \
    -domain PD_CORE2 \
    -isolation_signal pmu_core2_iso_en \
    -isolation_sense high \
    -location parent

set_isolation_control iso_core3 \
    -domain PD_CORE3 \
    -isolation_signal pmu_core3_iso_en \
    -isolation_sense high \
    -location parent

# AXI 总线隔离也需要配对控制信号（复用同一信号）
set_isolation_control iso_core0_axi \
    -domain PD_CORE0 \
    -isolation_signal pmu_core0_iso_en \
    -isolation_sense high \
    -location parent
```

#### 控制信号时序要求

```
═══ 下电序列 ═══                    ═══ 上电序列 ═══

  pmu_coreX_iso_en                    power_sw_en
      ┌────────────                       ┌────────────
  ────┘  ① 先使能隔离               ─────┘  ① 先上电

  power_sw_en                         power_ack
      ────────┐                           ┌────────────
              └────                  ─────┘  ② 电源稳定
        ② 再关断电源
                                      pmu_coreX_iso_en
                                          ────────┐
                                                  └────
                                            ③ 最后释放隔离
```

> ⚠️ **关键约束**：`pmu_coreX_iso_en` 信号必须由**常开域（PD_CPU）内的 PMU 控制器**驱动。如果 iso_en 信号属于可关断域，则域关断后 iso_en 本身也丢失，隔离单元行为不确定！

### 7c. 隔离单元映射 — `map_isolation_cell`（可选）

> 指定隔离策略使用哪个库单元实现。不指定时 EDA 工具会自动选择。

```tcl
# 指定具体的隔离库单元（可选，工具默认会自动选择）
map_isolation_cell iso_core0 \
    -domain PD_CORE0 \
    -lib_cells {ISOCLAMP0_D4}           ;# AND 型, clamp-to-0

map_isolation_cell iso_core0_axi \
    -domain PD_CORE0 \
    -lib_cells {ISOLATCH_D4}            ;# Latch 型, clamp-to-last
```

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① 隔离使能信号（`pmu_coreX_iso_en`）必须在 RTL 中存在，由常开域的 PMU 控制器驱动<br>② `set_isolation_control` 中的 `-isolation_signal` 必须与 RTL 端口名完全匹配<br>③ `-clamp_value 0`：适用于大多数数据信号<br>④ `-clamp_value latch`：适用于 AXI/AHB 总线（避免协议违规）<br>⑤ 仔细审查每个跨域输出信号的安全钳位值 |
| **物理实现** | ① 隔离单元由**常开电源**供电（`SS_ALWAYS_ON`）<br>② 每个跨域输出信号需要一个隔离单元<br>③ 隔离单元增加信号路径延迟（通常 0.1-0.3ns）<br>④ `-location parent` 将隔离单元放在接收域侧（常开供电，推荐）<br>⑤ `map_isolation_cell` 可用于约束工具选用特定驱动强度的隔离单元 |
| **常见错误** | ① **只写了 `set_isolation` 没写 `set_isolation_control`** → 工具不知道用哪个信号控制<br>② iso_en 信号属于可关断域 → 域关断后隔离控制信号丢失<br>③ 所有信号都用 `clamp_value 0` 没有考虑总线协议<br>④ 隔离单元的供电写成了可关断域的电源<br>⑤ `-isolation_sense` 极性与 RTL 中的信号极性不匹配 |

### 钳位值选择指南

| 信号类型 | 推荐 clamp_value | 原因 |
|----------|-----------------|------|
| 普通数据信号 | `0` | 安全默认值 |
| 低有效复位 `rst_n` | `1` | 保持非复位状态，避免误触发复位 |
| AXI/AHB 总线 | `latch` | 锁存最后事务状态，避免协议违规 |
| 中断信号 | `0` | 避免虚假中断 |
| 握手信号 valid/ready | `0` | 避免虚假事务 |

---

## Step 8：电平转换 — `set_level_shifter`

### UPF 命令

```tcl
# CPU 子系统内部各核心与子系统常开域电压相同 → 通常不需要 Level Shifter
# 但如果核心支持 DVFS（如 A76 大核 0.9V/0.75V），建议加 Level Shifter

# 示例：Core2 (A76, DVFS 0.9V/0.75V) 输出到 PD_CPU (0.9V)
set_level_shifter ls_core2_out \
    -domain PD_CORE2 \
    -applies_to outputs \
    -rule both                ;# DVFS 场景用 both
```

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① RTL 不需要修改，但设计师需要明确哪些核心做 DVFS<br>② 如果域之间标称电压相同且不做 DVFS → 不需要 Level Shifter<br>③ `-rule both`：适用于 DVFS 场景（电压动态变化） |
| **物理实现** | ① Level Shifter 延迟较大（通常 0.2-0.5ns），对时序关键路径影响显著<br>② Level Shifter 需要**两路电源供电**（源端电压 + 目标端电压）<br>③ 如果同时需要隔离和电平转换，工具可以插入 **ISO+LS 复合单元** |
| **常见错误** | ① 忘记设置 `-rule` 参数<br>② 同电压域之间误加 Level Shifter 浪费面积 |

### 是否需要 Level Shifter 的判断

```
域A 和 域B 之间有信号传递？
    │
    ├── 电压相同且不做 DVFS → 不需要 Level Shifter
    ├── 电压相同但做 DVFS → 需要（rule both）
    └── 电压不同 → 需要
         ├── A 电压 > B 电压 → A outputs: high_to_low
         └── A 电压 < B 电压 → A outputs: low_to_high
```

---

## Step 9：状态保持 — `set_retention` + `map_retention_cell`

### 9a. 状态保持策略定义 — `set_retention`

> **注意**：`set_retention` 中的 `-save_signal` 和 `-restore_signal` 已经包含了控制信号定义（不同于 `set_isolation` 需要单独的 `set_isolation_control`）。

```tcl
# CPU 各核心寄存器保持
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
```

#### Save/Restore 控制信号说明

| 参数 | 信号名 | 含义 | 时序要求 |
|------|--------|------|---------|
| `-save_signal {pmu_core0_save high}` | `pmu_core0_save` | 高有效：脉冲时将 FF 数据保存到 Shadow Latch | **必须在断电前**触发，且 FF 数据此时仍有效 |
| `-restore_signal {pmu_core0_restore high}` | `pmu_core0_restore` | 高有效：脉冲时将 Shadow Latch 数据恢复到 FF | **必须在上电后、释放隔离前**触发 |

#### 控制信号时序关系

```
═══ 完整的下电 → 上电序列 ═══

  clk_enable    ──┐
                  └──────────────────────────────────────── (1) 先停时钟

  save          ────────┌───┐
                        │   └────────────────────────────── (2) 触发保存
                        ↑ FF 数据 → Shadow Latch

  iso_en        ─────────────┌───────────────────────────── (3) 使能隔离

  power_sw      ──────────────────┐
                                  └──────────────────────── (4) 最后断电

  ... (域处于关断状态，Shadow Latch 由常开电源保持) ...

  power_sw      ────────────────────────┌────────────────── (5) 先上电

  power_ack     ─────────────────────────────┌───────────── (6) 电源稳定

  restore       ──────────────────────────────────┌───┐
                                                  │   └──── (7) 触发恢复
                                                  ↑ Shadow Latch → FF

  iso_en        ────────────────────────────────────────┐
                                                        └── (8) 释放隔离

  clk_enable    ─────────────────────────────────────────┌── (9) 恢复时钟
```

> ⚠️ **关键约束**：`save` / `restore` / `iso_en` 信号都必须由**常开域的 PMU 控制器**驱动，不能属于可关断域。

### 9b. Retention 单元映射 — `map_retention_cell`（可选）

> 指定 Retention 策略使用哪个库单元实现。不指定时 EDA 工具会自动选择。

```tcl
# 指定具体的 Retention FF 库单元（可选，工具默认会自动选择）
map_retention_cell ret_core0 \
    -domain PD_CORE0 \
    -lib_cells {SDFFRQN_RET_D1}        ;# Balloon Latch 型 Retention FF

map_retention_cell ret_core1 \
    -domain PD_CORE1 \
    -lib_cells {SDFFRQN_RET_D1}

map_retention_cell ret_core2 \
    -domain PD_CORE2 \
    -lib_cells {SDFFRQN_RET_D1}

map_retention_cell ret_core3 \
    -domain PD_CORE3 \
    -lib_cells {SDFFRQN_RET_D1}
```

#### `map_retention_cell` 参数说明

| 参数 | 含义 |
|------|------|
| `ret_coreN` | 关联的 Retention 策略名称（必须与 `set_retention` 中的名称一致） |
| `-domain` | 应用的电源域 |
| `-lib_cells` | 指定使用的 Retention FF 库单元名称 |

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① save/restore 信号必须在 RTL 中存在，由常开域的 PMU 控制器驱动<br>② 不是所有域都需要 Retention——GPU（显存重载）、NPU（权重在 DDR）可以不做<br>③ 选择性 Retention：只保持关键寄存器（通用寄存器、状态机、配置寄存器）<br>④ save 必须在断电前、restore 必须在上电后隔离释放前触发 |
| **物理实现** | ① Retention FF 比标准 FF **面积大 30-50%**<br>② Retention FF 需要额外的常开电源引脚<br>③ **选择性 Retention** 可显著减少面积和漏电开销<br>④ `map_retention_cell` 可用于约束工具选用特定面积/延迟的 Retention FF |
| **常见错误** | ① save/restore 信号 edge 极性写反（`high` vs `low`）<br>② Retention 供电来源写成了可关断域的电源<br>③ 对所有寄存器都做 Retention 导致面积爆炸<br>④ **save/restore 信号属于可关断域**——域关断后信号丢失<br>⑤ restore 在隔离释放之后才触发——此时 FF 输出已经驱动下游逻辑，可能产生毛刺 |

---

## Step 10：子系统电源状态与仿真行为

### UPF 命令

```tcl
# 各核心供电集合的电压状态
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

# 仿真行为
set_simstate_behavior CORRUPT -domain PD_CORE0
set_simstate_behavior CORRUPT -domain PD_CORE1
set_simstate_behavior CORRUPT -domain PD_CORE2
set_simstate_behavior CORRUPT -domain PD_CORE3
```

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① `CORRUPT` 使域关断时仿真输出 X——帮助发现缺少隔离的 bug<br>② 确保状态定义覆盖所有 DVFS 电压点 |
| **物理实现** | ① 电压值必须与工艺库的 operating condition 匹配<br>② 不同电压状态对应不同的 STA signoff corner<br>③ OFF 状态触发工具检查隔离和 Retention 策略 |
| **常见错误** | ① 电压值与库文件不匹配<br>② 缺少 OFF 状态定义 |

---

# Phase B：顶层 UPF 编写

> 顶层 UPF 负责：定义全局域和供电网络 → 加载各子系统 UPF → 自顶向下连接电源

---

## Step 11：顶层域与全局供电网络

### UPF 命令

```tcl
# ================================================================
# File: soc_top.upf
# Description: MobileStar SoC Top-Level UPF (Hierarchical)
# ================================================================
upf_version 2.0

# ---- 顶层域（常开域）----
# 包含 PMU, GIC, Timer, RTC, WakeUp Logic, Bus Interconnect
create_power_domain PD_TOP -include_scope \
    -supply {primary SS_TOP}

# DDR 控制器域（通常不关断，但支持低功耗模式）
create_power_domain PD_DDR -elements {u_ddr_ctrl} \
    -supply {primary SS_DDR}

# ---- 顶层供电端口（芯片 PAD）----
create_supply_port VDD   -direction in    ;# 主电源 0.9V
create_supply_port VSS   -direction in    ;# 主地线
create_supply_port VDDQ  -direction in    ;# DDR I/O 电源 1.1V

# ---- 全局供电网络 ----
create_supply_net VDD   -domain PD_TOP
create_supply_net VSS   -domain PD_TOP
create_supply_net VDDQ  -domain PD_TOP

# ---- 连接 PAD 到网络 ----
connect_supply_net VDD   -ports {VDD}
connect_supply_net VSS   -ports {VSS}
connect_supply_net VDDQ  -ports {VDDQ}

# ---- 全局供电集合 ----
create_supply_set SS_TOP \
    -function {power VDD} \
    -function {ground VSS}
create_supply_set SS_DDR \
    -function {power VDD} \
    -function {ground VSS}
create_supply_set SS_DDR_IO \
    -function {power VDDQ} \
    -function {ground VSS}
create_supply_set SS_ALWAYS_ON \
    -function {power VDD} \
    -function {ground VSS}
```

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① 顶层只定义不被子系统覆盖的域（常开域 PD_TOP、DDR 域等）<br>② 子系统的域在子系统 UPF 中定义，顶层不需要重复<br>③ `-include_scope` 包含顶层中所有未被子系统或 DDR 域覆盖的逻辑 |
| **物理实现** | ① 顶层供电端口对应芯片 PAD/Bump<br>② 电源 PAD 数量决定 IR drop 和 EM 风险<br>③ 常开域逻辑（PMU、GIC 等）放在芯片中心或易于布线的位置<br>④ DDR 域通常靠近芯片边缘（与 DDR PHY 的 IO 相邻） |
| **常见错误** | ① 顶层试图定义子系统内部的域（如 PD_CORE0）——这是子系统 UPF 的职责<br>② 忘记创建 `SS_ALWAYS_ON` 全局常开供电集合 |

---

## Step 12：加载子系统 UPF + 自顶向下电源连接 ⭐

> **这是层次化 UPF 的核心步骤**

### UPF 命令

```tcl
# ================================================================
# 加载 CPU 子系统 UPF
# ================================================================
load_upf cpu_subsys.upf -scope u_cpu_subsys

# 自顶向下连接：将顶层 VDD/VSS 连接到 CPU 子系统的供电端口
connect_supply_net VDD -ports {u_cpu_subsys/VDD}
connect_supply_net VSS -ports {u_cpu_subsys/VSS}

# ================================================================
# 加载 GPU 子系统 UPF
# ================================================================
load_upf gpu_subsys.upf -scope u_gpu

# 自顶向下连接
connect_supply_net VDD -ports {u_gpu/VDD}
connect_supply_net VSS -ports {u_gpu/VSS}

# ================================================================
# 加载 NPU 子系统 UPF
# ================================================================
load_upf npu_subsys.upf -scope u_npu

# 自顶向下连接
connect_supply_net VDD -ports {u_npu/VDD}
connect_supply_net VSS -ports {u_npu/VSS}

# ================================================================
# 加载外设子系统 UPF
# ================================================================
load_upf peri_subsys.upf -scope u_peripherals

# 自顶向下连接
connect_supply_net VDD -ports {u_peripherals/VDD}
connect_supply_net VSS -ports {u_peripherals/VSS}
```

### 说明

`load_upf` + `connect_supply_net` 是层次化 UPF 的**核心模式**：

```
load_upf <子系统UPF文件> -scope <RTL实例名>
    ↓
  告诉工具：在 <RTL实例名> 对应的作用域下，
  按照 <子系统UPF文件> 的描述创建电源域、开关、隔离等。
    ↓
connect_supply_net <顶层网络> -ports {<RTL实例名>/<子系统供电端口>}
    ↓
  将顶层的全局电源网络（VDD/VSS）连接到
  子系统在 Step 2 中声明的 create_supply_port 端口。
    ↓
  完成自顶向下的电源连接！
```

### 自顶向下连接的物理含义

```
          芯片 PAD (VDD/VSS)
               │
    ═══════════╪═════════════════ 顶层 Power Ring ═══════
               │
    ┌──────────┼──────────┐
    │ PD_TOP   │          │
    │ (常开域)  │          │
    │ PMU/GIC  │          │
    │ Timer    │          │
    └──────────┼──────────┘
               │
    ┌──────────┼──────────────────┐
    │ connect_supply_net VDD      │  ← 自顶向下连接
    │ -ports {u_cpu_subsys/VDD}   │
    │          │                  │
    │  ┌───────┼──────────┐      │
    │  │ CPU 子系统 Power Ring    │
    │  │       │          │      │
    │  │  VDD ─┤          │      │
    │  │       │          │      │
    │  │  ┌────▼────┐     │      │
    │  │  │SW_CORE0 │     │      │
    │  │  │VDD→VDD_SW│    │      │
    │  │  └────┬────┘     │      │
    │  │       │          │      │
    │  │  PD_CORE0        │      │
    │  │  (可切换电源)      │      │
    │  └──────────────────┘      │
    └────────────────────────────┘
```

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① `-scope` 参数必须与 RTL 中子系统的**实例名**完全匹配<br>② 如 `u_cpu_subsys` 必须是顶层模块中 CPU 子系统实例的名称<br>③ 子系统 UPF 中的所有 `-elements` 路径都是相对于此 scope 的<br>④ 多团队并行开发时，只需约定子系统的实例名和供电端口名 |
| **物理实现** | ① `load_upf` 告诉后端工具在哪个物理区域应用子系统的电源意图<br>② `connect_supply_net` 对应物理上从顶层 Power Ring/Mesh 向子系统区域的**电源走线连接**<br>③ 每个 `connect_supply_net` 路径对应一条从顶层到子系统的电源供给通路<br>④ 子系统面积越大、功耗越高，需要更宽的电源走线（或更多 via）来满足 IR drop 要求 |
| **常见错误** | ① `-scope` 与 RTL 实例名不匹配——最常见的错误！<br>② 忘记在 `load_upf` 之后做 `connect_supply_net`——子系统"断电"（无电源供给）<br>③ `connect_supply_net` 的端口路径格式错误——正确格式：`{<scope>/<port_name>}`<br>④ 子系统 UPF 中的 `create_supply_port` 名称与顶层 `connect_supply_net` 中引用的不匹配 |

### load_upf vs apply_power_model 对比

```
load_upf（层次化文件加载）：
  ✓ 子系统有独立的 UPF 文件
  ✓ 支持多团队并行开发
  ✓ 子系统 UPF 可独立验证
  ✗ 需要手动管理跨层次连接

apply_power_model（IP 封装复用）：
  ✓ IP 的低功耗意图被封装为 Power Model
  ✓ SoC 集成者不需要了解 IP 内部结构
  ✗ 需要 IP 提供方预先定义 Power Model
  ✗ 灵活性较低（不能修改 IP 内部策略）
```

---

## Step 13：顶层电源状态与全局仿真行为

### UPF 命令

```tcl
# 顶层域电源状态
add_power_state SS_TOP \
    -state {ON -supply_expr {power == `{FULL_ON, 0.9}}}

add_power_state SS_DDR \
    -state {ON -supply_expr {power == `{FULL_ON, 0.9}}}

# 顶层仿真行为
set_simstate_behavior NORMAL  -domain PD_TOP
set_simstate_behavior NORMAL  -domain PD_DDR
```

### 注意事项

| 维度 | 注意事项 |
|------|---------|
| **RTL 设计** | ① 顶层只定义顶层域和 DDR 域的电源状态<br>② 子系统各域的电源状态在子系统 UPF 中定义<br>③ power-aware 仿真时，工具会自动合并所有层次的状态定义 |
| **物理实现** | ① 顶层常开域始终 ON——不需要 OFF 状态<br>② DDR 域如有 Self-Refresh 模式，可增加低功耗状态定义<br>③ 所有电压值必须与工艺库的 operating condition 匹配 |
| **常见错误** | ① 在顶层重复定义子系统内部域的电源状态<br>② 忘记给 DDR 域定义状态 |

---

## 完整文件示例汇总

### cpu_subsys.upf（完整）

```tcl
# ================================================================
# File: cpu_subsys.upf
# Description: CPU Subsystem — 4核 (2×A55 + 2×A76)
# Scope: u_cpu_subsys (由顶层 load_upf 指定)
# ================================================================
upf_version 2.0

# ---- Step 2: 供电端口 ----
create_supply_port VDD -direction in
create_supply_port VSS -direction in

# ---- Step 3: 电源域 ----
create_power_domain PD_CPU -include_scope -supply {primary SS_CPU}
create_power_domain PD_CORE0 -elements {u_core0} -supply {primary SS_CORE0}
create_power_domain PD_CORE1 -elements {u_core1} -supply {primary SS_CORE1}
create_power_domain PD_CORE2 -elements {u_core2} -supply {primary SS_CORE2}
create_power_domain PD_CORE3 -elements {u_core3} -supply {primary SS_CORE3}

# ---- Step 4: 供电网络 ----
create_supply_net VDD -domain PD_CPU
create_supply_net VSS -domain PD_CPU
connect_supply_net VDD -ports {VDD}
connect_supply_net VSS -ports {VSS}
create_supply_net VDD_SW_CORE0 -domain PD_CORE0
create_supply_net VDD_SW_CORE1 -domain PD_CORE1
create_supply_net VDD_SW_CORE2 -domain PD_CORE2
create_supply_net VDD_SW_CORE3 -domain PD_CORE3

# ---- Step 5: 供电集合 ----
create_supply_set SS_CPU       -function {power VDD}          -function {ground VSS}
create_supply_set SS_CORE0     -function {power VDD_SW_CORE0} -function {ground VSS}
create_supply_set SS_CORE1     -function {power VDD_SW_CORE1} -function {ground VSS}
create_supply_set SS_CORE2     -function {power VDD_SW_CORE2} -function {ground VSS}
create_supply_set SS_CORE3     -function {power VDD_SW_CORE3} -function {ground VSS}
create_supply_set SS_ALWAYS_ON -function {power VDD}          -function {ground VSS}

# ---- Step 6: 电源开关 ----
create_power_switch SW_CORE0 -domain PD_CORE0 \
    -input_supply_port {vin VDD} -output_supply_port {vout VDD_SW_CORE0} \
    -control_port {ctrl pmu_core0_pwr_en} -on_state {on vin {ctrl}} \
    -ack_port {ack pmu_core0_pwr_ack {on}}
create_power_switch SW_CORE1 -domain PD_CORE1 \
    -input_supply_port {vin VDD} -output_supply_port {vout VDD_SW_CORE1} \
    -control_port {ctrl pmu_core1_pwr_en} -on_state {on vin {ctrl}} \
    -ack_port {ack pmu_core1_pwr_ack {on}}
create_power_switch SW_CORE2 -domain PD_CORE2 \
    -input_supply_port {vin VDD} -output_supply_port {vout VDD_SW_CORE2} \
    -control_port {ctrl pmu_core2_pwr_en} -on_state {on vin {ctrl}} \
    -ack_port {ack pmu_core2_pwr_ack {on}}
create_power_switch SW_CORE3 -domain PD_CORE3 \
    -input_supply_port {vin VDD} -output_supply_port {vout VDD_SW_CORE3} \
    -control_port {ctrl pmu_core3_pwr_en} -on_state {on vin {ctrl}} \
    -ack_port {ack pmu_core3_pwr_ack {on}}

# ---- Step 7: 隔离 + 隔离控制 ----
set_isolation iso_core0 -domain PD_CORE0 -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 -applies_to outputs
set_isolation iso_core1 -domain PD_CORE1 -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 -applies_to outputs
set_isolation iso_core2 -domain PD_CORE2 -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 -applies_to outputs
set_isolation iso_core3 -domain PD_CORE3 -isolation_supply_set SS_ALWAYS_ON \
    -clamp_value 0 -applies_to outputs

# 隔离控制信号（必须配对 set_isolation）
set_isolation_control iso_core0 -domain PD_CORE0 \
    -isolation_signal pmu_core0_iso_en -isolation_sense high -location parent
set_isolation_control iso_core1 -domain PD_CORE1 \
    -isolation_signal pmu_core1_iso_en -isolation_sense high -location parent
set_isolation_control iso_core2 -domain PD_CORE2 \
    -isolation_signal pmu_core2_iso_en -isolation_sense high -location parent
set_isolation_control iso_core3 -domain PD_CORE3 \
    -isolation_signal pmu_core3_iso_en -isolation_sense high -location parent

# ---- Step 9: Retention + 单元映射 ----
set_retention ret_core0 -domain PD_CORE0 -retention_supply_set SS_ALWAYS_ON \
    -save_signal {pmu_core0_save high} -restore_signal {pmu_core0_restore high}
set_retention ret_core1 -domain PD_CORE1 -retention_supply_set SS_ALWAYS_ON \
    -save_signal {pmu_core1_save high} -restore_signal {pmu_core1_restore high}
set_retention ret_core2 -domain PD_CORE2 -retention_supply_set SS_ALWAYS_ON \
    -save_signal {pmu_core2_save high} -restore_signal {pmu_core2_restore high}
set_retention ret_core3 -domain PD_CORE3 -retention_supply_set SS_ALWAYS_ON \
    -save_signal {pmu_core3_save high} -restore_signal {pmu_core3_restore high}

# Retention 单元映射（可选）
map_retention_cell ret_core0 -domain PD_CORE0 -lib_cells {SDFFRQN_RET_D1}
map_retention_cell ret_core1 -domain PD_CORE1 -lib_cells {SDFFRQN_RET_D1}
map_retention_cell ret_core2 -domain PD_CORE2 -lib_cells {SDFFRQN_RET_D1}
map_retention_cell ret_core3 -domain PD_CORE3 -lib_cells {SDFFRQN_RET_D1}

# ---- Step 10: 电源状态 + 仿真行为 ----
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
set_simstate_behavior CORRUPT -domain PD_CORE0
set_simstate_behavior CORRUPT -domain PD_CORE1
set_simstate_behavior CORRUPT -domain PD_CORE2
set_simstate_behavior CORRUPT -domain PD_CORE3
```

### soc_top.upf（完整）

```tcl
# ================================================================
# File: soc_top.upf
# Description: MobileStar SoC 顶层 UPF (层次化)
# ================================================================
upf_version 2.0

# ---- 顶层域 ----
create_power_domain PD_TOP -include_scope -supply {primary SS_TOP}
create_power_domain PD_DDR -elements {u_ddr_ctrl} -supply {primary SS_DDR}

# ---- 顶层供电端口 (芯片 PAD) ----
create_supply_port VDD  -direction in
create_supply_port VSS  -direction in
create_supply_port VDDQ -direction in

# ---- 全局供电网络 ----
create_supply_net VDD  -domain PD_TOP
create_supply_net VSS  -domain PD_TOP
create_supply_net VDDQ -domain PD_TOP
connect_supply_net VDD  -ports {VDD}
connect_supply_net VSS  -ports {VSS}
connect_supply_net VDDQ -ports {VDDQ}

# ---- 全局供电集合 ----
create_supply_set SS_TOP       -function {power VDD}  -function {ground VSS}
create_supply_set SS_DDR       -function {power VDD}  -function {ground VSS}
create_supply_set SS_DDR_IO    -function {power VDDQ} -function {ground VSS}
create_supply_set SS_ALWAYS_ON -function {power VDD}  -function {ground VSS}

# ================================================================
# 加载子系统 UPF + 自顶向下电源连接
# ================================================================

# ---- CPU 子系统 ----
load_upf cpu_subsys.upf -scope u_cpu_subsys
connect_supply_net VDD -ports {u_cpu_subsys/VDD}
connect_supply_net VSS -ports {u_cpu_subsys/VSS}

# ---- GPU 子系统 ----
load_upf gpu_subsys.upf -scope u_gpu
connect_supply_net VDD -ports {u_gpu/VDD}
connect_supply_net VSS -ports {u_gpu/VSS}

# ---- NPU 子系统 ----
load_upf npu_subsys.upf -scope u_npu
connect_supply_net VDD -ports {u_npu/VDD}
connect_supply_net VSS -ports {u_npu/VSS}

# ---- 外设子系统 ----
load_upf peri_subsys.upf -scope u_peripherals
connect_supply_net VDD -ports {u_peripherals/VDD}
connect_supply_net VSS -ports {u_peripherals/VSS}

# ================================================================
# 顶层电源状态 + 仿真行为
# ================================================================
add_power_state SS_TOP -state {ON -supply_expr {power == `{FULL_ON, 0.9}}}
add_power_state SS_DDR -state {ON -supply_expr {power == `{FULL_ON, 0.9}}}
set_simstate_behavior NORMAL -domain PD_TOP
set_simstate_behavior NORMAL -domain PD_DDR
```

---

## 完整流程检查清单

### 子系统 UPF 检查（每个子系统）

- [ ] `upf_version` 与顶层一致
- [ ] 声明了 `create_supply_port VDD/VSS -direction in`
- [ ] 所有 `-elements` 路径是**相对于子系统作用域**的（不是全局路径）
- [ ] 子系统顶层域使用 `-include_scope`
- [ ] 常开网络和可切换网络正确区分
- [ ] `SS_ALWAYS_ON` 指向常开网络 VDD
- [ ] Power Switch 的 control/ack 信号属于子系统常开域
- [ ] 所有跨域输出信号都有合适的 clamp_value
- [ ] **每个 `set_isolation` 都配对了 `set_isolation_control`**
- [ ] **`set_isolation_control` 的 `-isolation_signal` 与 RTL 端口名匹配**
- [ ] **`-isolation_sense` 极性与 RTL 中信号的有效电平一致**
- [ ] Retention 的 save/restore 信号属于常开域
- [ ] **save/restore 信号极性（high/low）与 RTL 实际行为匹配**

### 顶层 UPF 检查

- [ ] 顶层 PAD 端口完整（VDD/VSS/VDDQ 等）
- [ ] 只定义顶层自身的域（PD_TOP、PD_DDR）——不定义子系统内部域
- [ ] 每个 `load_upf` 的 `-scope` 与 RTL 实例名完全匹配
- [ ] 每个 `load_upf` 后面紧跟 `connect_supply_net` 连接 VDD/VSS
- [ ] `connect_supply_net` 路径格式正确：`{<scope>/<port_name>}`

### RTL 设计检查

- [ ] PMU RTL 中包含所有 Power Switch 的 control/ack 信号
- [ ] PMU RTL 中包含所有 Isolation 的 enable 信号（`set_isolation_control` 中引用的）
- [ ] PMU RTL 中包含所有 Retention 的 save/restore 信号（`set_retention` 中引用的）
- [ ] PMU 上电/断电序列正确（save → iso_en → power_off → ... → power_on → restore → iso_dis）
- [ ] 所有 control/ack/save/restore/iso_en 信号都属于常开域
- [ ] 各子系统 RTL 模块的实例名与 `load_upf -scope` 匹配
- [ ] **iso_en/save/restore 信号的有效极性与 UPF 中声明的一致**

### 物理实现检查

- [ ] 每个子系统在 Floorplan 中有独立区域
- [ ] 可关断域之间预留 guard band（5-20μm）
- [ ] Power Switch 管面积预留充足（域面积的 5-15%）
- [ ] 电源 PAD 数量满足 IR drop 和 EM 要求
- [ ] 从顶层 Power Ring 到子系统的供电通路宽度满足电流需求
- [ ] Retention FF 面积增加已纳入估算（+30-50%）
- [ ] Level Shifter 延迟已纳入时序预算（+0.2-0.5ns）
- [ ] 隔离单元延迟已纳入时序预算（+0.1-0.3ns）
- [ ] 所有 DVFS 电压点都有对应的 STA signoff corner

### 验证检查

- [ ] 各子系统 UPF 可**独立**通过 power-aware lint check
- [ ] 顶层 + 子系统联合 power-aware 仿真覆盖所有功耗模式转换
- [ ] 关断域的输出在仿真中显示 X（确认 CORRUPT 生效）
- [ ] 隔离使能后输出值符合预期（0/1/latch）
- [ ] Retention 的 save/restore 后寄存器值正确恢复

---

## 参考文档

| 文档 | 说明 |
|------|------|
| [Ch01-UPF概述与基础概念](Ch01-UPF概述与基础概念.md) | UPF 历史、核心概念、完整示例 |
| [Ch02-电源域定义命令](Ch02-电源域定义命令.md) | `create_power_domain` 详解 |
| [Ch03-供电网络命令](Ch03-供电网络命令.md) | 供电端口、网络、连接命令 |
| [Ch04-电源开关命令](Ch04-电源开关命令.md) | `create_power_switch` 与 MTCMOS |
| [Ch05-隔离策略命令](Ch05-隔离策略命令.md) | `set_isolation`、`set_isolation_control`、`map_isolation_cell` 与隔离单元 |
| [Ch06-电平转换命令](Ch06-电平转换命令.md) | `set_level_shifter` 与跨压域信号 |
| [Ch07-状态保持命令](Ch07-状态保持命令.md) | `set_retention`、`map_retention_cell` 与 Balloon Latch |
| [Ch08-电源状态与状态表](Ch08-电源状态与状态表.md) | `add_power_state` 与功耗模式 |
| [Ch09-UPF2.0新增特性](Ch09-UPF2.0新增特性与高级命令.md) | `load_upf`、`begin_power_model`、Supply Set |
| [Ch10-完整SoC低功耗设计实战](Ch10-完整SoC低功耗设计实战.md) | 多核 SoC 完整 UPF 案例 |

---

*本文档基于 IEEE 1801-2013 (UPF 2.0) 标准编写。*
