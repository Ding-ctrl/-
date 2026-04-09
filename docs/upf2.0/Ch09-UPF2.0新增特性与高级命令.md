# Ch09 - UPF 2.0 新增特性与高级命令

## 概述

UPF 2.0 (IEEE 1801-2013/2015) 相比 UPF 1.0 引入了多项重要增强，主要目标是：
1. **提高可复用性** — 让 IP 核的低功耗意图可以被封装和复用
2. **增强层次化支持** — 更好地处理 SoC 集成中的多层次电源描述
3. **改进仿真支持** — 更精确地模拟关断/上电行为

---

## 9.1 begin_power_model / end_power_model

### 命令语法

```tcl
begin_power_model model_name [-for {module_list}]
    # ... UPF 命令 ...
end_power_model
```

### 命令定义

定义一个**可复用的电源模型**，将一组低功耗意图封装为独立的模块，便于在 SoC 集成时复用。

### 参数详解

| 参数 | 含义 | 芯片上的影响 |
|------|------|------------|
| `model_name` | 模型名称 | IP 的低功耗意图封装 |
| `-for` | 适用的 HDL 模块 | 该模型对应哪些设计模块 |

### 对实际芯片的作用

Power Model 是 UPF 2.0 最重要的创新之一，直接解决了 **IP 复用**问题：

```
传统方式（UPF 1.0）：
  
  SoC UPF 文件需要了解 IP 内部的所有电源细节：
  
  ┌──────────────── SoC UPF ──────────────────┐
  │ create_power_domain PD_TOP ...             │
  │ create_power_domain PD_CPU ...             │
  │                                            │
  │ # 需要知道 CPU IP 内部结构！               │
  │ create_power_domain PD_CPU_CORE0           │
  │   -elements {u_cpu/u_core0}                │
  │ set_isolation iso_cpu_core0                │
  │   -domain PD_CPU_CORE0 ...                 │
  │ set_retention ret_cpu_core0                │
  │   -domain PD_CPU_CORE0 ...                 │
  │ # ... 更多内部细节 ...                      │
  └────────────────────────────────────────────┘
  
  问题：SoC 集成者需要深入了解每个 IP 的内部结构


Power Model 方式（UPF 2.0）：

  IP 提供方封装好 Power Model：
  
  ┌──────────── CPU IP Power Model ────────────┐
  │ begin_power_model PM_CPU -for {cpu_top}    │
  │                                            │
  │   # IP 内部的电源域、隔离、保持等           │
  │   create_power_domain PD_CORE0 ...         │
  │   create_power_domain PD_CORE1 ...         │
  │   set_isolation ...                        │
  │   set_retention ...                        │
  │   # 定义外部接口                            │
  │   set_port_attributes ...                  │
  │                                            │
  │ end_power_model                            │
  └────────────────────────────────────────────┘
  
  SoC 集成者只需要 apply：
  
  ┌──────────── SoC UPF ──────────────────────┐
  │ create_power_domain PD_TOP ...             │
  │                                            │
  │ # 不需要知道 CPU 内部细节！                 │
  │ apply_power_model PM_CPU -to {u_cpu}       │
  │                                            │
  └────────────────────────────────────────────┘
```

**芯片影响：** Power Model 本身不改变芯片结构，但极大地简化了**大型 SoC 集成**的 UPF 编写和管理。

### 使用示例

```tcl
# ===== IP 提供方定义 Power Model =====
begin_power_model PM_CPU_SUBSYS -for {cpu_subsystem}

    # 创建 IP 内部电源域
    create_power_domain PD_CPU_INT -include_scope
    create_power_domain PD_CORE0 -elements {u_core0}
    create_power_domain PD_CORE1 -elements {u_core1}
    
    # 定义供电端口（IP 的电源接口）
    create_supply_port VDD_CPU  -direction in
    create_supply_port VSS      -direction in
    create_supply_port VDD_RET  -direction in
    
    create_supply_net VDD_CPU -domain PD_CPU_INT
    create_supply_net VSS     -domain PD_CPU_INT
    create_supply_net VDD_RET -domain PD_CPU_INT
    
    connect_supply_net VDD_CPU -ports {VDD_CPU}
    connect_supply_net VSS     -ports {VSS}
    connect_supply_net VDD_RET -ports {VDD_RET}
    
    # 域供电设置
    set_domain_supply_net PD_CPU_INT \
        -primary_power_net VDD_CPU \
        -primary_ground_net VSS
    
    # IP 内部的低功耗策略
    create_power_switch SW_CORE0 \
        -domain PD_CORE0 \
        -input_supply_port {vin VDD_CPU} \
        -output_supply_port {vout VDD_CORE0} \
        -control_port {ctrl core0_pwr_en} \
        -on_state {on vin {ctrl}}
    
    set_isolation iso_core0 \
        -domain PD_CORE0 \
        -isolation_power_net VDD_CPU \
        -clamp_value 0 \
        -applies_to outputs
    
    set_retention ret_core0 \
        -domain PD_CORE0 \
        -retention_power_net VDD_RET \
        -save_signal {core0_save high} \
        -restore_signal {core0_restore high}
    
    # 定义端口属性（告知 SoC 集成者）
    set_port_attributes -ports {data_out[31:0]} \
        -attribute {UPF_is_isolated TRUE}
    
end_power_model
```

---

## 9.2 apply_power_model

### 命令语法

```tcl
apply_power_model model_name
    -to {instance_list}
    [-supply_map {model_port soc_net}] ...
```

### 命令定义

将一个预定义的 Power Model 应用到设计实例上。

### 对实际芯片的作用

```tcl
# SoC 集成者使用 Power Model
apply_power_model PM_CPU_SUBSYS \
    -to {u_cpu} \
    -supply_map {{VDD_CPU VDD_SW_CPU} \
                 {VSS VSS} \
                 {VDD_RET VDD}}
```

**芯片影响：**
- `u_cpu` 实例自动获得 PM_CPU_SUBSYS 中定义的所有低功耗策略
- 供电映射：SoC 级的 `VDD_SW_CPU` 连接到 IP 的 `VDD_CPU` 端口
- 等效于在 `u_cpu` 下手动写入 Power Model 中的所有 UPF 命令

---

## 9.3 set_port_attributes

### 命令语法

```tcl
set_port_attributes
    -ports {port_list}
    [-attribute {attr_name attr_value}] ...
    [-receiver_supply supply_set]
    [-driver_supply supply_set]
    [-related_power_port port_name]
    [-related_ground_port port_name]
```

### 命令定义

设置端口的电源相关属性，用于描述 IP 边界端口的电气特性。

### 对实际芯片的作用

```
IP 端口属性示意：

┌───────────── CPU IP ──────────────────┐
│                                        │
│  ┌──────┐                              │
│  │      │──→ data_out[31:0]  ──────── │──→ 到 SoC 总线
│  │ Core │                              │
│  │      │←── data_in[31:0]  ←──────── │←── 从 SoC 总线
│  └──────┘                              │
│                                        │
│  端口属性：                              │
│  data_out: 已隔离，供电域 = PD_CPU      │
│  data_in:  需要常开供电，电平 = VDD     │
│                                        │
└────────────────────────────────────────┘

set_port_attributes 告知 SoC 集成者：
- 哪些端口已经在 IP 内部做了隔离
- 哪些端口需要外部做电平转换
- 端口信号所属的供电域
```

### 使用示例

```tcl
# 声明端口已在 IP 内部隔离
set_port_attributes \
    -ports {data_out[31:0] valid_out ready_out} \
    -attribute {UPF_is_isolated TRUE}

# 声明端口的供电关系
set_port_attributes \
    -ports {data_out[31:0]} \
    -driver_supply SS_CPU \
    -related_power_port VDD_CPU \
    -related_ground_port VSS

# 声明端口已经做了电平转换
set_port_attributes \
    -ports {cross_domain_signal} \
    -attribute {UPF_is_level_shifted TRUE}
```

---

## 9.4 set_simstate_behavior

### 命令语法

```tcl
set_simstate_behavior behavior
    [-domain domain_name]
    [-elements {element_list}]
```

### 命令定义

定义域在关断状态下的**仿真行为**，控制仿真器如何表现关断域的信号。

### 行为选项

| 行为 | 含义 | 仿真中的表现 |
|------|------|------------|
| `CORRUPT` | 信号损坏 | 输出 X（不确定态），最严格 |
| `NORMAL` | 正常行为 | 继续正常仿真（忽略关断） |
| `CORRUPT_STATE_ON_ACTIVATE` | 上电时损坏 | 重新上电时所有寄存器变 X |
| `CORRUPT_STATE_ON_DEACTIVATE` | 关断时损坏 | 关断瞬间所有寄存器变 X |

### 对实际芯片的作用

`set_simstate_behavior` 不直接影响芯片物理结构，但**影响仿真的准确性**：

```
CORRUPT 模式（推荐）：

关断前:  FF_Q = 1    →    关断中: FF_Q = X    →    上电后: FF_Q = X
                                                    (需要 restore 或 reset)

→ 最接近真实芯片行为
→ 能发现未正确隔离的信号
→ 能验证 Retention 的正确性

NORMAL 模式（调试用）：

关断前:  FF_Q = 1    →    关断中: FF_Q = 1    →    上电后: FF_Q = 1
                          (继续正常仿真)

→ 不反映真实芯片行为
→ 仅用于功能调试阶段
→ 不能发现低功耗相关的 Bug
```

### 使用示例

```tcl
# 推荐：关断域使用 CORRUPT（最接近真实芯片）
set_simstate_behavior CORRUPT \
    -domain PD_CPU

set_simstate_behavior CORRUPT \
    -domain PD_GPU

# 常开域使用 NORMAL
set_simstate_behavior NORMAL \
    -domain PD_TOP
```

---

## 9.5 set_repeater

### 命令语法

```tcl
set_repeater repeater_name
    -domain domain_name
    [-elements {element_list}]
    [-input_supply_set supply_set]
    [-output_supply_set supply_set]
```

### 命令定义

在跨域信号路径上定义**中继/缓冲单元**，确保信号在穿越可关断域时仍能正确传播。

### 对实际芯片的作用

```
场景：信号穿越可关断域

  PD_A (常开)    PD_B (可关断)    PD_C (常开)
       │              │               │
  ┌───┐│         ┌───┐│          ┌───┐│
  │FF ├┼─signal──┼───┼┼──signal──┼───┼┼→
  └───┘│         │BUF││          │   ││
       │         └───┘│          └───┘│
       │              │               │
       
  问题：当 PD_B 关断时，穿越 PD_B 的信号路径被切断！
  
  解决：使用 Repeater (Always-On Buffer)
  
  PD_A (常开)    PD_B (可关断)    PD_C (常开)
       │              │               │
  ┌───┐│    ┌─────────┼──────┐   ┌───┐│
  │FF ├┼───→│Repeater │      │──→│   ││
  └───┘│    │(AO Buf) │      │   └───┘│
       │    │ VDD_AO  │      │        │
       │    └─────────┼──────┘        │
       │              │               │
       
  Repeater 使用 Always-On 电源供电
  → 即使 PD_B 关断，信号仍能通过
```

### 使用示例

```tcl
# 穿越 PD_GPU 域的 CPU 到 DDR 的信号需要 Repeater
set_repeater rep_through_gpu \
    -domain PD_GPU \
    -elements {u_gpu/pass_through_*}
```

---

## 9.6 Supply Set Handle (UPF 2.0)

### 概念

Supply Set Handle 是 UPF 2.0 引入的**间接引用机制**，允许在不知道具体供电网络名称的情况下引用电源。

```tcl
# 每个电源域自动有一个 primary supply set handle
# 可以通过 domain_name.primary 引用

# 例如：
add_power_state PD_CPU.primary \
    -state {ON  -supply_expr {power == `{FULL_ON, 0.9}}} \
    -state {OFF -supply_expr {power == `{OFF}}}

# PD_CPU.primary 自动引用 PD_CPU 域的主要供电集合
# 无需知道具体的 supply net 名称
```

### 对实际芯片的作用

Supply Set Handle 简化了**层次化设计**中的电源引用：

```
没有 Supply Set Handle（UPF 1.0）：
  
  SoC 集成时必须知道 IP 内部的具体网络名
  → 耦合度高，复用困难

有 Supply Set Handle（UPF 2.0）：

  IP 定义：
    create_supply_set my_primary \
        -function {power VDD_INT} \
        -function {ground VSS_INT}
  
  SoC 集成：
    apply_power_model PM_IP -to {u_ip} \
        -supply_map {{my_primary SS_SOC}}
    
  → 只需映射 Supply Set，不需知道内部网络名
  → 解耦合，提高复用性
```

---

## 9.7 UPF 2.0 新增特性总结

```
UPF 2.0 特性全景图：

┌──────────────────────────────────────────────────────┐
│                    UPF 2.0 增强特性                     │
│                                                       │
│  ┌─────────────────┐   ┌──────────────────────────┐  │
│  │ 可复用性增强      │   │ 仿真增强                  │  │
│  │                  │   │                          │  │
│  │ • Power Model   │   │ • set_simstate_behavior  │  │
│  │ • apply_power   │   │ • CORRUPT / NORMAL       │  │
│  │   _model        │   │ • 更精确的 X 传播         │  │
│  │ • set_port      │   │                          │  │
│  │   _attributes   │   └──────────────────────────┘  │
│  └─────────────────┘                                  │
│                                                       │
│  ┌─────────────────┐   ┌──────────────────────────┐  │
│  │ 供电描述简化      │   │ 其他增强                   │  │
│  │                  │   │                          │  │
│  │ • Supply Set    │   │ • set_repeater           │  │
│  │ • Supply Set    │   │ • 增强的 add_power_state │  │
│  │   Handle        │   │ • 更好的层次化支持        │  │
│  │ • 统一的函数映射 │   │ • 策略自动推断与合并      │  │
│  └─────────────────┘   └──────────────────────────┘  │
│                                                       │
└──────────────────────────────────────────────────────┘
```

---

## 9.8 层次化 UPF 设计实践

### 9.8.1 load_upf 命令

```tcl
# load_upf 用于在顶层引用子系统的 UPF 文件
load_upf sub_system.upf -scope instance_path
```

**层次化 UPF 的典型结构：**

```
soc_top.upf (顶层)
  │
  ├── create_power_domain PD_TOP ...
  ├── create_supply_port VDD / VSS ...
  ├── create_supply_net VDD / VSS ...
  │
  ├── load_upf cpu_subsys.upf -scope u_cpu
  │     └── cpu_subsys.upf:
  │           ├── create_power_domain PD_CPU -include_scope
  │           ├── create_power_domain PD_CORE0 ...
  │           ├── create_supply_port VDD -direction in
  │           ├── create_power_switch SW_CORE0 ...
  │           ├── set_isolation ...
  │           └── set_retention ...
  │
  ├── load_upf gpu_subsys.upf -scope u_gpu
  │     └── gpu_subsys.upf: (类似结构)
  │
  ├── connect_supply_net VDD -ports {u_cpu/VDD}  ← 跨层次连接
  ├── connect_supply_net VSS -ports {u_cpu/VSS}
  ├── connect_supply_net VDD -ports {u_gpu/VDD}
  ├── connect_supply_net VSS -ports {u_gpu/VSS}
  │
  └── add_power_state ... (系统级电源状态)
```

### 9.8.2 层次化 vs 平坦化的选择

```
层次化 UPF (load_upf):
  
  优点：
  ✅ 各子系统独立开发和验证
  ✅ IP 复用更容易
  ✅ 团队并行开发
  ✅ 便于维护和调试
  
  缺点：
  ❌ 跨层次电源连接需要额外描述
  ❌ 工具的层次化支持需要验证
  ❌ 调试时需要跟踪多个文件

平坦化 UPF (单文件):
  
  优点：
  ✅ 简单直观，所有信息在一个文件中
  ✅ 工具兼容性最好
  ✅ 调试方便
  
  缺点：
  ❌ 大型 SoC 文件巨大（数千行）
  ❌ IP 复用困难
  ❌ 团队协作困难

  建议：
  ├── 小型设计 (< 5 个域): 平坦化
  ├── 中型设计 (5-20 个域): 按子系统层次化
  └── 大型 SoC (> 20 个域): 层次化 + Power Model
```

### 9.8.3 策略合并与自动推断

UPF 2.0 支持策略的**自动推断和合并**：

```tcl
# 场景：IP 内部已有隔离，SoC 层也定义了隔离
# UPF 2.0 工具可以自动检测并避免重复插入

# IP 内部 UPF:
set_isolation iso_ip_internal \
    -domain PD_IP \
    -clamp_value 0 \
    -applies_to outputs

set_port_attributes \
    -ports {data_out[31:0]} \
    -attribute {UPF_is_isolated TRUE}  ← 声明已隔离

# SoC 顶层 UPF:
set_isolation iso_ip_external \
    -domain PD_IP \
    -clamp_value 0 \
    -applies_to outputs

# EDA 工具识别到 data_out 已有 UPF_is_isolated 属性
# → 不会重复插入隔离单元
# → 避免了面积浪费和性能损失
```

### 9.8.4 UPF 3.0 (IEEE 1801-2018) 展望

```
UPF 3.0 的主要新增特性：

1. 增强的供电描述
   - 支持更复杂的电压调节器建模
   - 支持多轨电源 (Multi-rail Supply)
   - 更好的模拟/混合信号支持

2. 改进的仿真控制
   - 更细粒度的 Simstate 控制
   - 支持 partial power-down 仿真
   - 改进的 X 传播模型

3. 先进工艺支持
   - 更好的 FinFET/GAA 偏置建模
   - 支持 Back-Bias 控制
   - 多阈值电压混合使用的描述

4. 系统级功耗意图
   - 支持芯片间的功耗描述（Chiplet）
   - 支持 Package-level 电源描述
   - 与系统级功耗管理协议的集成
```

---

## 9.9 本章小结

| 命令/特性 | 芯片设计中的意义 |
|-----------|----------------|
| `begin/end_power_model` | IP 低功耗意图封装 → SoC 集成效率提升 |
| `apply_power_model` | IP 低功耗策略实例化 → 简化 SoC UPF 编写 |
| `set_port_attributes` | IP 端口电源特性描述 → 跨层次信息传递 |
| `set_simstate_behavior` | 仿真行为控制 → 更准确的功耗仿真 |
| `set_repeater` | 跨域信号中继 → 穿越关断域的信号保持 |
| Supply Set / Handle | 供电描述简化 → 层次化设计支持 |

> **下一章：** [Ch10 - 完整 SoC 低功耗设计实战案例](Ch10-完整SoC低功耗设计实战.md)
