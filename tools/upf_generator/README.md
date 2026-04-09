# UPF 2.0 Generator — 低功耗设计信息统计 → UPF 文件自动生成工具

## 简介

在实际芯片设计中，UPF 文件通常涉及大量重复模式（电源域、开关、隔离、保持等），手动编写容易出错且难以维护。本工具采用**"先统计低功耗设计信息，再自动生成 UPF"**的方式：

1. **填写 YAML 设计信息文件** — 统计电源域、开关、隔离策略等全部低功耗设计信息
2. **运行 Python 脚本** — 自动生成符合 IEEE 1801 (UPF 2.0) 标准的 UPF 文件

## 文件结构

```
tools/upf_generator/
├── gen_upf.py                  # Python UPF 生成脚本
├── lp_design_spec.yaml         # 低功耗设计信息模板（空白，带注释说明）
├── examples/
│   └── mobile_star.yaml        # 预填示例：Ch10 MobileStar SoC 完整设计
└── README.md                   # 本文件
```

## 快速开始

### 1. 安装依赖

```bash
pip install pyyaml
```

### 2. 从示例生成 UPF

```bash
# 输出到终端预览
python tools/upf_generator/gen_upf.py tools/upf_generator/examples/mobile_star.yaml --stdout

# 生成到文件（默认使用 YAML 中配置的 output_file）
python tools/upf_generator/gen_upf.py tools/upf_generator/examples/mobile_star.yaml

# 指定输出文件
python tools/upf_generator/gen_upf.py tools/upf_generator/examples/mobile_star.yaml -o my_design.upf
```

### 3. 创建自己的设计

```bash
# 复制模板
cp tools/upf_generator/lp_design_spec.yaml my_chip_spec.yaml

# 编辑 my_chip_spec.yaml，填写你的低功耗设计信息
# 不需要的功能留空列表 [] 即可

# 生成 UPF
python tools/upf_generator/gen_upf.py my_chip_spec.yaml
```

## YAML 模板说明

模板以**最复杂的低功耗设计为基础**（多核 SoC、多电源域、多电压岛），涵盖 UPF 2.0 所有主要功能。简单设计只需填写需要的部分：

| YAML 段落 | 对应 UPF 功能 | 简单设计是否必填 |
|-----------|-------------|:---:|
| `project` | 文件头、版本 | ✅ |
| `supply_ports` | 芯片电源 PAD | ✅ |
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
| `create_power_domain` | 电源域定义 |
| `create_supply_port` | 供电端口 |
| `create_supply_net` | 供电网络 |
| `connect_supply_net` | 端口-网络连接 |
| `create_supply_set` | 供电集合 (UPF 2.0) |
| `set_domain_supply_net` | 域供电分配 |
| `create_power_switch` | 电源开关 |
| `set_isolation` | 隔离策略 |
| `set_level_shifter` | 电平转换 |
| `set_retention` | 状态保持 |
| `add_power_state` | 电源状态 |
| `set_simstate_behavior` | 仿真行为 |

## 设计理念

- **以最复杂设计为模板** — 模板覆盖完整的多核 SoC 低功耗场景
- **简单设计按需填写** — 不需要的功能留空列表 `[]`，生成的 UPF 会自动跳过
- **UPF 1.0 / 2.0 兼容** — 设置 `upf_version: "1.0"` 时会自动使用 `isolation_power_net` 而非 `isolation_supply_set`
- **可审查** — YAML 文件本身就是低功耗设计的规格文档，便于团队评审
