# UPF 2.0 Generator — 低功耗设计信息统计 → UPF 文件自动生成工具

## 简介

在实际芯片设计中，UPF 文件通常涉及大量重复模式（电源域、开关、隔离、保持等），手动编写容易出错且难以维护。本工具采用**"先统计低功耗设计信息，再自动生成 UPF"**的方式：

1. **填写 YAML 设计信息文件** — 统计电源域、开关、隔离策略等全部低功耗设计信息
2. **运行 Python 脚本** — 自动生成符合 IEEE 1801 (UPF 2.0) 标准的 UPF 文件

**支持层次化全芯片设计** — SoC 顶层 YAML 可通过 `includes` 引用各子系统 YAML，自动生成层次化 UPF（`load_upf`）或合并为单一平坦 UPF。

## 文件结构

```
tools/upf_generator/
├── gen_upf.py                  # Python UPF 生成脚本
├── lp_design_spec.yaml         # 低功耗设计信息模板（空白，带注释说明）
├── examples/
│   ├── mobile_star.yaml        # 单文件示例：Ch10 MobileStar SoC 完整设计
│   └── hierarchical/           # 层次化示例：全芯片跨 YAML 设计
│       ├── soc_top.yaml        # SoC 顶层 (引用下面的子系统)
│       ├── cpu_subsys.yaml     # CPU 子系统 (4 核 + 隔离 + 保持)
│       ├── gpu_subsys.yaml     # GPU 子系统 (电平转换)
│       ├── npu_subsys.yaml     # NPU 子系统
│       └── peri_subsys.yaml    # 外设子系统
└── README.md                   # 本文件
```

## 快速开始

### 1. 安装依赖

```bash
pip install pyyaml
```

### 2. 单文件模式（简单设计）

```bash
# 输出到终端预览
python tools/upf_generator/gen_upf.py tools/upf_generator/examples/mobile_star.yaml --stdout

# 生成到文件（默认使用 YAML 中配置的 output_file）
python tools/upf_generator/gen_upf.py tools/upf_generator/examples/mobile_star.yaml

# 指定输出文件
python tools/upf_generator/gen_upf.py tools/upf_generator/examples/mobile_star.yaml -o my_design.upf
```

### 3. 层次化模式（全芯片设计）

```bash
# 层次化: 生成顶层 UPF + 各子系统独立 UPF (使用 load_upf 引用)
python tools/upf_generator/gen_upf.py tools/upf_generator/examples/hierarchical/soc_top.yaml

# 平坦化: 合并所有子系统到单个 UPF 文件
python tools/upf_generator/gen_upf.py tools/upf_generator/examples/hierarchical/soc_top.yaml --flat

# 预览到终端
python tools/upf_generator/gen_upf.py tools/upf_generator/examples/hierarchical/soc_top.yaml --stdout
```

### 4. 创建自己的设计

```bash
# 复制模板
cp tools/upf_generator/lp_design_spec.yaml my_chip_spec.yaml

# 编辑 my_chip_spec.yaml，填写你的低功耗设计信息
# 不需要的功能留空列表 [] 即可

# 生成 UPF
python tools/upf_generator/gen_upf.py my_chip_spec.yaml
```

## 层次化设计详解

### 设计理念

全芯片低功耗设计通常按子系统划分：

```
soc_top.yaml          ← SoC 顶层：供电端口、常开域、DDR 域
├── cpu_subsys.yaml   ← CPU 子系统：4 个核心域、开关、隔离、保持
├── gpu_subsys.yaml   ← GPU 子系统：开关、隔离、电平转换
├── npu_subsys.yaml   ← NPU 子系统：开关、隔离
└── peri_subsys.yaml  ← 外设子系统：开关、隔离
```

### YAML 中的 includes 配置

在顶层 YAML 中通过 `includes` 字段引用各子系统：

```yaml
# soc_top.yaml
includes:
  - file: "cpu_subsys.yaml"      # 子系统 YAML 文件（相对或绝对路径）
    scope: "u_cpu_subsys"        # RTL 中的层次路径
  - file: "gpu_subsys.yaml"
    scope: "u_gpu"
```

### 跨层次电源线连接

层次化设计的关键：**子系统 YAML 必须声明 `supply_ports`**（从父层级接入的电源端口），工具会自动：

1. **子系统 UPF** — 生成 `create_supply_port` + `create_supply_net` + `connect_supply_net`（子系统内部连接）
2. **顶层 UPF** — 在 `load_upf` 之后生成 `connect_supply_net`（跨层次连接顶层网络 → 子系统端口）

```yaml
# cpu_subsys.yaml (子系统)
supply_ports:
  - name: VDD             # 子系统从父层级接入的电源
    direction: in
  - name: VSS
    direction: in
```

生成的跨层次连接 UPF 代码：

```tcl
# mobile_star_top.upf (顶层) — 自动生成的跨层次连接
load_upf cpu_subsys.upf -scope u_cpu_subsys
connect_supply_net VDD  -ports {u_cpu_subsys/VDD}   ;# 顶层 VDD → CPU 子系统
connect_supply_net VSS  -ports {u_cpu_subsys/VSS}
```

```tcl
# cpu_subsys.upf (子系统) — 声明供电端口 + 内部连接
create_supply_port VDD -direction in
create_supply_port VSS -direction in
create_supply_net VDD -domain PD_CPU
create_supply_net VSS -domain PD_CPU
connect_supply_net VDD -ports {VDD}
connect_supply_net VSS -ports {VSS}
```

### 生成的 UPF 结构

**层次化模式（默认）** — 每个子系统生成独立 UPF，顶层用 `load_upf` + `connect_supply_net` 连接：

```tcl
# mobile_star_top.upf (顶层)
upf_version 2.0
create_power_domain PD_TOP -include_scope
create_supply_port VDD -direction in
create_supply_net VDD -domain PD_TOP
...
# 层次化 UPF: 加载子系统 + 跨层次电源连接
load_upf cpu_subsys.upf -scope u_cpu_subsys
connect_supply_net VDD  -ports {u_cpu_subsys/VDD}
connect_supply_net VSS  -ports {u_cpu_subsys/VSS}

load_upf gpu_subsys.upf -scope u_gpu
connect_supply_net VDD  -ports {u_gpu/VDD}
connect_supply_net VSS  -ports {u_gpu/VSS}
```

```tcl
# cpu_subsys.upf (子系统独立 UPF)
upf_version 2.0
create_power_domain PD_CPU -include_scope
create_supply_port VDD -direction in
create_supply_port VSS -direction in
create_supply_net VDD -domain PD_CPU
...
```

**平坦模式 (`--flat`)** — 合并所有子系统到单个 UPF：

```bash
python gen_upf.py soc_top.yaml --flat
```

## YAML 模板说明

模板以**最复杂的低功耗设计为基础**（多核 SoC、多电源域、多电压岛），涵盖 UPF 2.0 所有主要功能。简单设计只需填写需要的部分：

| YAML 段落 | 对应 UPF 功能 | 简单设计是否必填 |
|-----------|-------------|:---:|
| `project` | 文件头、版本 | ✅ |
| `includes` | 层次化子系统引用 | 全芯片设计时填 |
| `supply_ports` | 芯片电源 PAD | ✅ (顶层) |
| `power_domains` | 电源域定义 | ✅ |
| `switched_supply_nets` | 可切换供电网络 | 有开关域时填 |
| `supply_sets` | UPF 2.0 供电集合 | UPF 2.0 时填 |
| `power_switches` | 电源开关 | 有关断域时填 |
| `isolation_strategies` | 隔离策略 | 有关断域时填 |
| `level_shifters` | 电平转换 | 有跨电压域时填 |
| `retention_strategies` | 状态保持 | 需要 Retention 时填 |
| `power_states` | 电源状态 | 需要定义状态时填 |
| `sim_states` | 仿真行为 | 可选 |

### 简单设计示例

只有一个可关断域的最简设计，只需填写：

```yaml
project:
  name: "SimpleChip"
  upf_version: "2.0"
  output_file: "simple_chip.upf"

supply_ports:
  - name: VDD
    direction: in
  - name: VSS
    direction: in

power_domains:
  - name: PD_TOP
    elements: null
    is_top: true
    primary_power: VDD
    primary_ground: VSS
  - name: PD_CORE
    elements: "u_core"
    is_top: false
    primary_power: VDD_SW
    primary_ground: VSS

switched_supply_nets:
  - name: VDD_SW
    domain: PD_CORE

power_switches:
  - name: SW_CORE
    domain: PD_CORE
    input_supply: VDD
    output_supply: VDD_SW
    control_port: ctrl
    control_net: pmu_core_en
    on_state_name: "on"

isolation_strategies:
  - name: iso_core
    domain: PD_CORE
    isolation_power_net: VDD
    isolation_ground_net: VSS
    clamp_value: 0
    applies_to: outputs

# 不需要的段落留空即可
includes: []
supply_sets: []
level_shifters: []
retention_strategies: []
power_states: []
sim_states: []
```

## 支持的 UPF 命令

| UPF 命令 | 说明 |
|---------|------|
| `upf_version` | UPF 版本声明 |
| `create_power_domain` | 电源域定义 (UPF 2.0: 含 `-supply {primary}` 绑定) |
| `create_supply_port` | 供电端口 |
| `create_supply_net` | 供电网络 |
| `connect_supply_net` | 端口-网络连接 |
| `create_supply_set` | 供电集合 (UPF 2.0) |
| `set_domain_supply_net` | 域供电分配 (UPF 1.0 回退，2.0 已由 `-supply` 替代) |
| `create_power_switch` | 电源开关 |
| `set_isolation` | 隔离策略 |
| `set_level_shifter` | 电平转换 |
| `set_retention` | 状态保持 |
| `add_power_state` | 电源状态 |
| `set_simstate_behavior` | 仿真行为 |
| `load_upf` | 层次化加载子系统 UPF |

## 设计理念

- **以最复杂设计为模板** — 模板覆盖完整的多核 SoC 低功耗场景
- **简单设计按需填写** — 不需要的功能留空列表 `[]`，生成的 UPF 会自动跳过
- **层次化全芯片支持** — `includes` 引用子系统 YAML，生成 `load_upf` 层次化 UPF
- **平坦化合并** — `--flat` 选项将所有子系统合并为单一 UPF，便于调试
- **UPF 1.0 / 2.0 兼容** — 设置 `upf_version: "1.0"` 时自动使用 UPF 1.0 语法
- **可审查** — YAML 文件本身就是低功耗设计的规格文档，便于团队评审
