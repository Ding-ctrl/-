"""
芯片设计AI优化工具包 (Chip Design AI Optimization Toolkit)

提供以下优化能力 (Provides the following optimization capabilities):
- 布局优化 (Placement Optimization)
- 时序分析 (Timing Analysis)
- 功耗优化 (Power Optimization)
- 布线优化 (Routing Optimization)
"""

from chip_design.netlist import Component, Net, Netlist
from chip_design.placement import PlacementOptimizer
from chip_design.timing import TimingAnalyzer
from chip_design.power import PowerOptimizer
from chip_design.routing import RoutingOptimizer

__version__ = "0.1.0"
__all__ = [
    "Component",
    "Net",
    "Netlist",
    "PlacementOptimizer",
    "TimingAnalyzer",
    "PowerOptimizer",
    "RoutingOptimizer",
]
