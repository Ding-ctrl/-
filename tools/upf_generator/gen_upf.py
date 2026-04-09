#!/usr/bin/env python3
"""
UPF 2.0 Generator — 从低功耗设计信息 YAML 文件生成标准 UPF 文件

用法:
    python gen_upf.py <design_spec.yaml>           # 输出到 YAML 中指定的文件
    python gen_upf.py <design_spec.yaml> -o out.upf # 指定输出文件
    python gen_upf.py <design_spec.yaml> --stdout   # 输出到终端

依赖: PyYAML (pip install pyyaml)
"""

import argparse
import os
import sys
from datetime import datetime

import yaml


# ================================================================
# UPF Section Generators
# ================================================================

def gen_header(proj):
    """生成 UPF 文件头部注释和版本声明"""
    name = proj.get("name", "Unnamed")
    desc = proj.get("description", "")
    version = proj.get("upf_version", "2.0")
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = [
        "# ================================================================",
        f"# File: {proj.get('output_file', name + '.upf')}",
        f"# Description: {desc}",
        f"# Standard: IEEE 1801 (UPF {version})",
        f"# Generated: {now}",
        "# Generator: gen_upf.py",
        "# ================================================================",
        "",
        f"upf_version {version}",
    ]
    return lines


def gen_power_domains(domains):
    """Section 1: 电源域定义"""
    if not domains:
        return []
    lines = [
        "",
        "# ================================================================",
        "# Section 1: 电源域定义",
        "# ================================================================",
    ]
    for d in domains:
        desc = d.get("description", "")
        if desc:
            lines.append(f"\n# {desc}")
        name = d["name"]
        if d.get("is_top"):
            lines.append(f"create_power_domain {name} -include_scope")
        else:
            elements = d.get("elements", "")
            lines.append(
                f"create_power_domain {name} -elements {{{elements}}}"
            )
    return lines


def gen_supply_network(spec):
    """Section 2: 供电端口、网络、供电集合"""
    ports = spec.get("supply_ports", [])
    domains = spec.get("power_domains", [])
    switched = spec.get("switched_supply_nets", [])
    sets = spec.get("supply_sets", [])
    version = spec.get("project", {}).get("upf_version", "2.0")

    lines = [
        "",
        "# ================================================================",
        "# Section 2: 供电端口与网络",
        "# ================================================================",
    ]

    # Supply ports
    if ports:
        lines.append("\n# --- 顶层电源端口（芯片 PAD）---")
        for p in ports:
            desc = p.get("description", "")
            comment = f"   ;# {desc}" if desc else ""
            lines.append(
                f"create_supply_port {p['name']}   "
                f"-direction {p.get('direction', 'in')}{comment}"
            )

    # Global supply nets (from ports, created on top domain)
    top_domain = None
    for d in domains:
        if d.get("is_top"):
            top_domain = d["name"]
            break

    if ports and top_domain:
        lines.append("\n# --- 全局供电网络 ---")
        for p in ports:
            lines.append(
                f"create_supply_net {p['name']}   -domain {top_domain}"
            )

    # Switched supply nets
    if switched:
        lines.append("\n# --- 可切换供电网络 ---")
        for s in switched:
            lines.append(
                f"create_supply_net {s['name']} "
                f"-domain {s['domain']}"
            )

    # Connect ports to nets
    if ports:
        lines.append("\n# --- 连接端口到网络 ---")
        for p in ports:
            lines.append(
                f"connect_supply_net {p['name']}  -ports {{{p['name']}}}"
            )

    # Supply Sets (UPF 2.0)
    if sets and version == "2.0":
        lines.append("")
        lines.append(
            "# --- 定义供电集合 (UPF 2.0 Supply Set) ---"
        )
        for ss in sets:
            lines.append(f"create_supply_set {ss['name']} \\")
            lines.append(
                f"    -function {{power {ss['power_net']}}} \\"
            )
            lines.append(f"    -function {{ground {ss['ground_net']}}}")
            lines.append("")

    # Domain supply net assignment
    if domains:
        lines.append("# --- 为各域关联供电网络 ---")
        for d in domains:
            lines.append(f"set_domain_supply_net {d['name']} \\")
            lines.append(
                f"    -primary_power_net {d['primary_power']} \\"
            )
            lines.append(
                f"    -primary_ground_net {d['primary_ground']}"
            )
            lines.append("")

    return lines


def gen_power_switches(switches):
    """Section 3: 电源开关"""
    if not switches:
        return []
    lines = [
        "",
        "# ================================================================",
        "# Section 3: 电源开关",
        "# ================================================================",
    ]
    for sw in switches:
        on_state = sw.get("on_state_name", "on")
        ctrl_port = sw.get("control_port", "ctrl")
        lines.append(f"\ncreate_power_switch {sw['name']} \\")
        lines.append(f"    -domain {sw['domain']} \\")
        lines.append(
            f"    -input_supply_port  {{vin  {sw['input_supply']}}} \\"
        )
        lines.append(
            f"    -output_supply_port {{vout {sw['output_supply']}}} \\"
        )
        lines.append(
            f"    -control_port       {{{ctrl_port} {sw['control_net']}}} \\"
        )
        # ack_port is optional
        if sw.get("ack_port") and sw.get("ack_net"):
            lines.append(
                f"    -on_state           "
                f"{{{on_state} vin {{{ctrl_port}}}}} \\"
            )
            lines.append(
                f"    -ack_port           "
                f"{{{sw['ack_port']} {sw['ack_net']} {{{on_state}}}}}"
            )
        else:
            lines.append(
                f"    -on_state           "
                f"{{{on_state} vin {{{ctrl_port}}}}}"
            )
    return lines


def gen_isolation(strategies, version):
    """Section 4: 隔离策略"""
    if not strategies:
        return []
    lines = [
        "",
        "# ================================================================",
        "# Section 4: 隔离策略",
        "# ================================================================",
    ]
    for iso in strategies:
        lines.append(f"\nset_isolation {iso['name']} \\")
        lines.append(f"    -domain {iso['domain']} \\")

        # Optional: target specific elements
        if iso.get("elements"):
            lines.append(f"    -elements {{{iso['elements']}}} \\")

        # UPF 2.0 supply set or UPF 1.0 nets
        if version == "2.0" and iso.get("isolation_supply_set"):
            lines.append(
                f"    -isolation_supply_set {iso['isolation_supply_set']} \\"
            )
        else:
            if iso.get("isolation_power_net"):
                lines.append(
                    f"    -isolation_power_net "
                    f"{iso['isolation_power_net']} \\"
                )
            if iso.get("isolation_ground_net"):
                lines.append(
                    f"    -isolation_ground_net "
                    f"{iso['isolation_ground_net']} \\"
                )

        lines.append(f"    -clamp_value {iso['clamp_value']} \\")
        lines.append(f"    -applies_to {iso['applies_to']}")
    return lines


def gen_level_shifters(shifters):
    """Section 5: 电平转换"""
    if not shifters:
        return []
    lines = [
        "",
        "# ================================================================",
        "# Section 5: 电平转换",
        "# ================================================================",
    ]
    for ls in shifters:
        lines.append(f"\nset_level_shifter {ls['name']} \\")
        lines.append(f"    -domain {ls['domain']} \\")
        lines.append(f"    -applies_to {ls['applies_to']} \\")
        lines.append(f"    -rule {ls['rule']}")
    return lines


def gen_retention(strategies, version):
    """Section 6: 状态保持"""
    if not strategies:
        return []
    lines = [
        "",
        "# ================================================================",
        "# Section 6: 状态保持",
        "# ================================================================",
    ]
    for ret in strategies:
        save_sig = ret.get("save_signal", "")
        save_lvl = ret.get("save_level", "high")
        restore_sig = ret.get("restore_signal", "")
        restore_lvl = ret.get("restore_level", "high")

        lines.append(f"\nset_retention {ret['name']} \\")
        lines.append(f"    -domain {ret['domain']} \\")

        if version == "2.0" and ret.get("retention_supply_set"):
            lines.append(
                f"    -retention_supply_set {ret['retention_supply_set']} \\"
            )
        else:
            if ret.get("retention_power_net"):
                lines.append(
                    f"    -retention_power_net "
                    f"{ret['retention_power_net']} \\"
                )
            if ret.get("retention_ground_net"):
                lines.append(
                    f"    -retention_ground_net "
                    f"{ret['retention_ground_net']} \\"
                )

        lines.append(
            f"    -save_signal    {{{save_sig}    {save_lvl}}} \\"
        )
        lines.append(
            f"    -restore_signal {{{restore_sig} {restore_lvl}}}"
        )
    return lines


def gen_power_states(states):
    """Section 7: 电源状态定义"""
    if not states:
        return []
    lines = [
        "",
        "# ================================================================",
        "# Section 7: 电源状态定义",
        "# ================================================================",
    ]
    for ps in states:
        target = ps["target"]
        state_list = ps.get("states", [])
        if not state_list:
            continue

        if len(state_list) == 1:
            s = state_list[0]
            expr = s["expr"]
            lines.append(
                f"add_power_state {target} "
                f"-state {{{s['name']} "
                f"-supply_expr {{power == `{{{expr}}}}}}}"
            )
        else:
            lines.append(f"add_power_state {target} \\")
            for i, s in enumerate(state_list):
                expr = s["expr"]
                trailing = " \\" if i < len(state_list) - 1 else ""
                lines.append(
                    f"    -state {{{s['name']} "
                    f"-supply_expr {{power == `{{{expr}}}}}}}{trailing}"
                )
    lines.append("")
    return lines


def gen_sim_states(sim_states):
    """Section 8: 仿真行为"""
    if not sim_states:
        return []
    lines = [
        "",
        "# ================================================================",
        "# Section 8: 仿真行为",
        "# ================================================================",
    ]
    for ss in sim_states:
        lines.append(
            f"set_simstate_behavior {ss['behavior']} "
            f"-domain {ss['domain']}"
        )
    return lines


def gen_footer():
    """UPF 文件尾部"""
    return [
        "",
        "# ================================================================",
        "# End of UPF",
        "# ================================================================",
    ]


# ================================================================
# Main
# ================================================================

def generate_upf(spec):
    """从设计规格字典生成完整 UPF 文件内容（字符串列表）"""
    proj = spec.get("project", {})
    version = proj.get("upf_version", "2.0")

    all_lines = []
    all_lines.extend(gen_header(proj))
    all_lines.extend(gen_power_domains(spec.get("power_domains", [])))
    all_lines.extend(gen_supply_network(spec))
    all_lines.extend(gen_power_switches(spec.get("power_switches", [])))
    all_lines.extend(
        gen_isolation(spec.get("isolation_strategies", []), version)
    )
    all_lines.extend(gen_level_shifters(spec.get("level_shifters", [])))
    all_lines.extend(
        gen_retention(spec.get("retention_strategies", []), version)
    )
    all_lines.extend(gen_power_states(spec.get("power_states", [])))
    all_lines.extend(gen_sim_states(spec.get("sim_states", [])))
    all_lines.extend(gen_footer())
    return all_lines


def main():
    parser = argparse.ArgumentParser(
        description="从低功耗设计信息 YAML 生成 UPF 2.0 文件"
    )
    parser.add_argument(
        "spec_file",
        help="低功耗设计信息 YAML 文件路径"
    )
    parser.add_argument(
        "-o", "--output",
        help="输出 UPF 文件路径 (默认: YAML 中 project.output_file)"
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="输出到终端而不是文件"
    )
    args = parser.parse_args()

    # 读取 YAML
    with open(args.spec_file, "r", encoding="utf-8") as f:
        spec = yaml.safe_load(f)

    # 生成 UPF
    upf_lines = generate_upf(spec)
    upf_text = "\n".join(upf_lines) + "\n"

    if args.stdout:
        sys.stdout.write(upf_text)
    else:
        out_path = args.output or spec.get("project", {}).get(
            "output_file", "output.upf"
        )
        # 如果 output 是相对路径，基于 spec_file 目录
        if not os.path.isabs(out_path):
            base_dir = os.path.dirname(os.path.abspath(args.spec_file))
            out_path = os.path.join(base_dir, out_path)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(upf_text)
        print(f"✅ UPF 文件已生成: {out_path}")


if __name__ == "__main__":
    main()
