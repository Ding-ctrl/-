"""
功耗优化模块 (Power Optimization Module)

分析和优化芯片功耗，包括：
- 动态功耗分析 (Dynamic power analysis)
- 静态功耗（漏电流）分析 (Static/leakage power analysis)
- 门控时钟建议 (Clock gating recommendations)
- 多阈值电压单元替换建议 (Multi-Vt cell swap recommendations)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from chip_design.netlist import Component, Net, Netlist


@dataclass
class PowerBreakdown:
    """
    功耗分解报告。
    Power breakdown report.

    Attributes:
        dynamic_mw: 动态功耗（毫瓦）/ Dynamic power in mW
        leakage_mw: 漏电流功耗（毫瓦）/ Leakage power in mW
        total_mw: 总功耗（毫瓦）/ Total power in mW
        top_consumers: 功耗最大的组件列表 / Top power-consuming components
    """

    dynamic_mw: float = 0.0
    leakage_mw: float = 0.0
    total_mw: float = 0.0
    top_consumers: List[Tuple[str, float]] = field(default_factory=list)

    def summary(self) -> str:
        """返回功耗分解摘要 / Return a power breakdown summary."""
        lines = [
            "Power Breakdown:",
            f"  Dynamic power : {self.dynamic_mw:.3f} mW",
            f"  Leakage power : {self.leakage_mw:.3f} mW",
            f"  Total power   : {self.total_mw:.3f} mW",
            "  Top consumers:",
        ]
        for name, pwr in self.top_consumers[:5]:
            lines.append(f"    {name:20s}  {pwr:.3f} mW")
        return "\n".join(lines)

    def __repr__(self) -> str:
        return self.summary()


@dataclass
class PowerOptimizationSuggestion:
    """
    功耗优化建议。
    A single power optimization suggestion.

    Attributes:
        component_name: 涉及的组件名 / Component name
        suggestion_type: 建议类型 / Suggestion type
        description: 详细描述 / Detailed description
        estimated_saving_mw: 预计节省功耗（毫瓦）/ Estimated power saving in mW
    """

    component_name: str
    suggestion_type: str
    description: str
    estimated_saving_mw: float = 0.0

    def __repr__(self) -> str:
        return (
            f"Suggestion[{self.suggestion_type}] {self.component_name}: "
            f"{self.description} (saves ~{self.estimated_saving_mw:.3f} mW)"
        )


# Leakage ratio per cell type (relative to dynamic power)
_LEAKAGE_RATIO: Dict[str, float] = {
    "FF": 0.30,
    "AND2": 0.10,
    "OR2": 0.10,
    "NAND2": 0.08,
    "NOR2": 0.08,
    "XOR2": 0.12,
    "BUF": 0.05,
    "INV": 0.04,
    "MUX2": 0.14,
}
_DEFAULT_LEAKAGE_RATIO = 0.15

# Multi-Vt saving: High-Vt variant saves ~30% leakage at a small timing cost
_HIGH_VT_LEAKAGE_SAVING = 0.30


class PowerOptimizer:
    """
    功耗优化器：分析网表功耗并给出优化建议。
    Power optimizer: analyzes netlist power and generates optimization suggestions.

    Usage::

        from chip_design import Netlist, PowerOptimizer

        netlist = Netlist("my_design")
        # ... populate netlist ...
        optimizer = PowerOptimizer(netlist, activity_factor=0.2)
        breakdown = optimizer.analyze()
        print(breakdown.summary())
        suggestions = optimizer.suggest_optimizations()
        for s in suggestions:
            print(s)
    """

    def __init__(self, netlist: Netlist, activity_factor: float = 0.2) -> None:
        """
        初始化功耗优化器。
        Initialize the power optimizer.

        Args:
            netlist: 要分析的网表 / Netlist to analyze
            activity_factor: 平均开关活动系数（0~1）/ Average switching activity factor (0-1)
        """
        self.netlist = netlist
        self.activity_factor = max(0.0, min(activity_factor, 1.0))

    def analyze(self, top_n: int = 10) -> PowerBreakdown:
        """
        分析网表的功耗分布。
        Analyze the power distribution of the netlist.

        Args:
            top_n: 返回功耗最大的前 N 个组件 / Number of top consumers to return

        Returns:
            PowerBreakdown 报告 / A PowerBreakdown report
        """
        dynamic_total = 0.0
        leakage_total = 0.0
        per_component: List[Tuple[str, float]] = []

        for comp in self.netlist.components.values():
            dyn = comp.power_mw * self.activity_factor
            leak_ratio = _LEAKAGE_RATIO.get(comp.cell_type, _DEFAULT_LEAKAGE_RATIO)
            leak = comp.power_mw * leak_ratio
            dynamic_total += dyn
            leakage_total += leak
            per_component.append((comp.name, dyn + leak))

        per_component.sort(key=lambda x: x[1], reverse=True)

        return PowerBreakdown(
            dynamic_mw=dynamic_total,
            leakage_mw=leakage_total,
            total_mw=dynamic_total + leakage_total,
            top_consumers=per_component[:top_n],
        )

    def suggest_optimizations(self) -> List[PowerOptimizationSuggestion]:
        """
        生成功耗优化建议。
        Generate power optimization suggestions.

        包含以下类型的建议 / Includes suggestions of the following types:
        - ``multi_vt``: 将时序裕量充足的单元替换为高阈值电压版本
        - ``clock_gating``: 对触发器密集区域建议加入门控时钟
        - ``buffer_removal``: 移除冗余缓冲器

        Returns:
            PowerOptimizationSuggestion 列表 / List of suggestions
        """
        suggestions: List[PowerOptimizationSuggestion] = []
        suggestions.extend(self._multi_vt_suggestions())
        suggestions.extend(self._clock_gating_suggestions())
        suggestions.extend(self._buffer_removal_suggestions())
        return suggestions

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _multi_vt_suggestions(self) -> List[PowerOptimizationSuggestion]:
        """建议将非关键路径上的单元替换为高Vt版本。"""
        suggestions = []
        for comp in self.netlist.components.values():
            if comp.cell_type in ("BUF", "INV", "AND2", "OR2", "NAND2", "NOR2"):
                leak_ratio = _LEAKAGE_RATIO.get(comp.cell_type, _DEFAULT_LEAKAGE_RATIO)
                saving = comp.power_mw * leak_ratio * _HIGH_VT_LEAKAGE_SAVING
                if saving > 0.001:
                    suggestions.append(
                        PowerOptimizationSuggestion(
                            component_name=comp.name,
                            suggestion_type="multi_vt",
                            description=(
                                f"Replace {comp.cell_type} with high-Vt variant to reduce leakage "
                                f"(timing slack permitting)"
                            ),
                            estimated_saving_mw=saving,
                        )
                    )
        return suggestions

    def _clock_gating_suggestions(self) -> List[PowerOptimizationSuggestion]:
        """对相邻触发器组建议添加门控时钟。"""
        suggestions = []
        ff_comps = [c for c in self.netlist.components.values() if c.cell_type == "FF"]
        if len(ff_comps) >= 4:
            total_ff_power = sum(c.power_mw for c in ff_comps)
            # Typical clock gating saves 20-40% of FF dynamic power
            saving = total_ff_power * self.activity_factor * 0.30
            suggestions.append(
                PowerOptimizationSuggestion(
                    component_name="FF_cluster",
                    suggestion_type="clock_gating",
                    description=(
                        f"Insert clock gating logic for {len(ff_comps)} flip-flops "
                        f"to reduce dynamic switching power"
                    ),
                    estimated_saving_mw=saving,
                )
            )
        return suggestions

    def _buffer_removal_suggestions(self) -> List[PowerOptimizationSuggestion]:
        """识别可能冗余的缓冲器。"""
        suggestions = []
        # Find BUF cells that are the only component on their net
        driven_nets: Dict[str, List[str]] = {}
        for net in self.netlist.nets.values():
            driven_nets.setdefault(net.driver, []).append(net.name)

        for comp in self.netlist.components.values():
            if comp.cell_type == "BUF":
                nets = driven_nets.get(comp.name, [])
                if len(nets) == 1:
                    net = self.netlist.nets.get(nets[0])
                    if net and len(net.sinks) == 1:
                        saving = comp.power_mw * self.activity_factor * 0.5
                        suggestions.append(
                            PowerOptimizationSuggestion(
                                component_name=comp.name,
                                suggestion_type="buffer_removal",
                                description=(
                                    f"BUF '{comp.name}' drives a single sink; "
                                    f"consider removing if timing allows"
                                ),
                                estimated_saving_mw=saving,
                            )
                        )
        return suggestions
