"""
芯片网表数据结构 (Chip Netlist Data Structures)

定义芯片设计的基本数据结构：组件、连线和网表。
(Defines the fundamental data structures for chip design: components, nets, and netlists.)
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


@dataclass
class Component:
    """
    表示芯片中的一个组件（逻辑单元）。
    Represents a component (logic cell) in the chip.

    Attributes:
        name: 组件名称 / Component name
        cell_type: 单元类型，例如 AND2, OR2, FF, BUF / Cell type (e.g. AND2, OR2, FF, BUF)
        width: 组件宽度（微米）/ Component width in micrometers
        height: 组件高度（微米）/ Component height in micrometers
        x: X 坐标（布局后）/ X coordinate (after placement)
        y: Y 坐标（布局后）/ Y coordinate (after placement)
        power_mw: 功耗（毫瓦）/ Power consumption in milliwatts
        delay_ps: 传播延迟（皮秒）/ Propagation delay in picoseconds
        fixed: 是否固定位置（如 I/O pad）/ Whether position is fixed (e.g. I/O pad)
    """

    name: str
    cell_type: str
    width: float = 1.0
    height: float = 1.0
    x: float = 0.0
    y: float = 0.0
    power_mw: float = 0.1
    delay_ps: float = 10.0
    fixed: bool = False

    def center(self) -> Tuple[float, float]:
        """返回组件中心坐标 / Return the center coordinates of the component."""
        return (self.x + self.width / 2.0, self.y + self.height / 2.0)

    def overlaps(self, other: "Component") -> bool:
        """检查是否与另一组件重叠 / Check if this component overlaps another."""
        return (
            self.x < other.x + other.width
            and self.x + self.width > other.x
            and self.y < other.y + other.height
            and self.y + self.height > other.y
        )

    def __repr__(self) -> str:
        return (
            f"Component(name={self.name!r}, type={self.cell_type!r}, "
            f"pos=({self.x:.2f},{self.y:.2f}), "
            f"size={self.width:.2f}x{self.height:.2f})"
        )


@dataclass
class Net:
    """
    表示连接多个组件引脚的连线（网络）。
    Represents a net connecting pins of multiple components.

    Attributes:
        name: 网络名称 / Net name
        driver: 驱动该网络的组件名称 / Name of the driving component
        sinks: 接收该网络的组件名称列表 / List of sink component names
        weight: 网络权重（用于优化）/ Net weight used during optimization
    """

    name: str
    driver: str
    sinks: List[str] = field(default_factory=list)
    weight: float = 1.0

    def all_components(self) -> List[str]:
        """返回该网络涉及的所有组件名 / Return all component names involved in this net."""
        return [self.driver] + self.sinks

    def half_perimeter_wirelength(self, netlist: "Netlist") -> float:
        """
        计算半周长线长（HPWL）作为布线长度的估算。
        Compute Half-Perimeter Wirelength (HPWL) as an estimate of routing length.
        """
        comps = [netlist.components[c] for c in self.all_components() if c in netlist.components]
        if len(comps) < 2:
            return 0.0
        xs = [c.center()[0] for c in comps]
        ys = [c.center()[1] for c in comps]
        return (max(xs) - min(xs) + max(ys) - min(ys)) * self.weight

    def __repr__(self) -> str:
        return f"Net(name={self.name!r}, driver={self.driver!r}, sinks={self.sinks})"


class Netlist:
    """
    芯片网表，包含所有组件和连线。
    Chip netlist containing all components and nets.

    Attributes:
        name: 设计名称 / Design name
        die_width: 芯片宽度（微米）/ Die width in micrometers
        die_height: 芯片高度（微米）/ Die height in micrometers
        components: 组件字典 {名称: 组件} / Component dict {name: Component}
        nets: 网络字典 {名称: 网络} / Net dict {name: Net}
    """

    def __init__(self, name: str, die_width: float = 100.0, die_height: float = 100.0) -> None:
        self.name = name
        self.die_width = die_width
        self.die_height = die_height
        self.components: Dict[str, Component] = {}
        self.nets: Dict[str, Net] = {}

    def add_component(self, component: Component) -> None:
        """添加组件到网表 / Add a component to the netlist."""
        self.components[component.name] = component

    def add_net(self, net: Net) -> None:
        """添加网络到网表 / Add a net to the netlist."""
        self.nets[net.name] = net

    def total_wirelength(self) -> float:
        """计算所有网络的总半周长线长 / Compute total HPWL across all nets."""
        return sum(net.half_perimeter_wirelength(self) for net in self.nets.values())

    def total_overlap_area(self) -> float:
        """
        计算所有组件对之间的总重叠面积。
        Compute total overlap area between all pairs of components.
        """
        comps = list(self.components.values())
        total = 0.0
        for i, a in enumerate(comps):
            for b in comps[i + 1 :]:
                if a.overlaps(b):
                    ox = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
                    oy = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                    total += ox * oy
        return total

    def is_legal(self) -> bool:
        """
        检查布局是否合法（无重叠且在芯片范围内）。
        Check if the placement is legal (no overlaps and within die bounds).
        """
        for comp in self.components.values():
            if comp.x < 0 or comp.y < 0:
                return False
            if comp.x + comp.width > self.die_width:
                return False
            if comp.y + comp.height > self.die_height:
                return False
        return math.isclose(self.total_overlap_area(), 0.0, abs_tol=1e-6)

    def summary(self) -> str:
        """返回网表摘要信息 / Return a summary of the netlist."""
        return (
            f"Netlist '{self.name}': "
            f"{len(self.components)} components, "
            f"{len(self.nets)} nets, "
            f"die={self.die_width}x{self.die_height}µm, "
            f"HPWL={self.total_wirelength():.2f}µm"
        )

    def __repr__(self) -> str:
        return self.summary()
