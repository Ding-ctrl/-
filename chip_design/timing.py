"""
时序分析模块 (Timing Analysis Module)

基于静态时序分析（STA）方法计算关键路径延迟和时序裕量。
(Performs Static Timing Analysis (STA) to compute critical path delay and slack.)
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

from chip_design.netlist import Netlist


# Speed of light in SiO₂ interconnect approximation: ~1/3 c  →  ~100 µm/ps
_WIRE_DELAY_PS_PER_UM = 0.01  # picoseconds per micrometer of wire length


@dataclass
class TimingPath:
    """
    时序路径，从起点到终点。
    A timing path from a start point to an endpoint.

    Attributes:
        start: 起始组件名 / Start component name
        end: 终止组件名 / End component name
        path: 路径上的组件序列 / Sequence of component names along the path
        total_delay_ps: 总延迟（皮秒）/ Total delay in picoseconds
        slack_ps: 时序裕量（正值为满足时序）/ Slack in ps (positive means timing met)
        is_critical: 是否为关键路径 / Whether this is a critical path
    """

    start: str
    end: str
    path: List[str] = field(default_factory=list)
    total_delay_ps: float = 0.0
    slack_ps: float = 0.0
    is_critical: bool = False

    def __repr__(self) -> str:
        status = "CRITICAL" if self.is_critical else "ok"
        return (
            f"TimingPath({self.start} -> {self.end}, "
            f"delay={self.total_delay_ps:.1f}ps, "
            f"slack={self.slack_ps:.1f}ps, {status})"
        )


@dataclass
class TimingReport:
    """
    时序分析报告。
    Timing analysis report.

    Attributes:
        clock_period_ps: 时钟周期（皮秒）/ Clock period in picoseconds
        wns_ps: 最坏负裕量 / Worst Negative Slack (WNS)
        tns_ps: 总负裕量 / Total Negative Slack (TNS)
        critical_paths: 关键路径列表 / List of critical timing paths
        all_paths: 所有分析路径 / All analyzed paths
    """

    clock_period_ps: float
    wns_ps: float = 0.0
    tns_ps: float = 0.0
    critical_paths: List[TimingPath] = field(default_factory=list)
    all_paths: List[TimingPath] = field(default_factory=list)

    def timing_met(self) -> bool:
        """是否满足时序约束 / Check whether all timing constraints are met."""
        return self.wns_ps >= 0.0

    def summary(self) -> str:
        """返回时序报告摘要 / Return a summary of the timing report."""
        status = "PASS ✓" if self.timing_met() else "FAIL ✗"
        return (
            f"Timing Report [{status}]\n"
            f"  Clock period : {self.clock_period_ps:.1f} ps\n"
            f"  WNS          : {self.wns_ps:.1f} ps\n"
            f"  TNS          : {self.tns_ps:.1f} ps\n"
            f"  Critical paths: {len(self.critical_paths)}\n"
            f"  Total paths   : {len(self.all_paths)}"
        )

    def __repr__(self) -> str:
        return self.summary()


class TimingAnalyzer:
    """
    静态时序分析器。
    Static timing analyzer.

    通过遍历网表拓扑来计算每条路径的延迟，并识别关键路径。
    Traverses the netlist topology to compute path delays and identify critical paths.

    Usage::

        from chip_design import Netlist, TimingAnalyzer

        netlist = Netlist("my_design")
        # ... populate netlist ...
        analyzer = TimingAnalyzer(netlist, clock_period_ps=1000.0)
        report = analyzer.analyze()
        print(report.summary())
    """

    def __init__(self, netlist: Netlist, clock_period_ps: float = 1000.0) -> None:
        """
        初始化时序分析器。
        Initialize the timing analyzer.

        Args:
            netlist: 要分析的网表 / Netlist to analyze
            clock_period_ps: 时钟周期约束（皮秒）/ Clock period constraint in picoseconds
        """
        self.netlist = netlist
        self.clock_period_ps = clock_period_ps

    def analyze(self) -> TimingReport:
        """
        执行静态时序分析并返回报告。
        Perform static timing analysis and return a report.

        Returns:
            TimingReport 实例 / A TimingReport instance
        """
        netlist = self.netlist
        paths = self._enumerate_paths()

        for path in paths:
            path.total_delay_ps = self._compute_path_delay(path)
            path.slack_ps = self.clock_period_ps - path.total_delay_ps
            path.is_critical = path.slack_ps < 0.0

        critical = [p for p in paths if p.is_critical]
        wns = min((p.slack_ps for p in paths), default=0.0)
        tns = sum(p.slack_ps for p in paths if p.slack_ps < 0.0)

        return TimingReport(
            clock_period_ps=self.clock_period_ps,
            wns_ps=wns,
            tns_ps=tns,
            critical_paths=critical,
            all_paths=paths,
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _enumerate_paths(self) -> List[TimingPath]:
        """
        枚举所有从输入/触发器到输出/触发器的路径。
        Enumerate paths from all input/FF drivers to all output/FF sinks.
        """
        # Build adjacency: driver -> list of sinks
        adjacency: Dict[str, List[str]] = {name: [] for name in self.netlist.components}
        for net in self.netlist.nets.values():
            if net.driver in adjacency:
                for sink in net.sinks:
                    if sink in adjacency:
                        adjacency[net.driver].append(sink)

        paths: List[TimingPath] = []
        # DFS from each node that has no predecessors (source)
        has_predecessor: Set[str] = set()
        for sinks in adjacency.values():
            has_predecessor.update(sinks)

        sources = [n for n in adjacency if n not in has_predecessor]
        if not sources:
            # Fallback: treat all nodes as sources (handles cycles gracefully)
            sources = list(adjacency.keys())

        for src in sources:
            dfs_paths = self._dfs(src, adjacency)
            for path_nodes in dfs_paths:
                if len(path_nodes) >= 2:
                    paths.append(
                        TimingPath(start=path_nodes[0], end=path_nodes[-1], path=list(path_nodes))
                    )
        return paths

    def _dfs(
        self,
        start: str,
        adjacency: Dict[str, List[str]],
        max_depth: int = 20,
    ) -> List[List[str]]:
        """DFS 枚举所有从 start 出发的简单路径。"""
        results: List[List[str]] = []
        stack: List[Tuple[str, List[str], Set[str]]] = [(start, [start], {start})]
        while stack:
            node, path, visited = stack.pop()
            children = adjacency.get(node, [])
            if not children or len(path) >= max_depth:
                results.append(path)
                continue
            for child in children:
                if child not in visited:
                    stack.append((child, path + [child], visited | {child}))
            # If no unvisited children, record the path
            if all(c in visited for c in children):
                results.append(path)
        return results

    def _compute_path_delay(self, path: TimingPath) -> float:
        """
        计算路径总延迟 = 各组件延迟之和 + 互联线延迟。
        Compute total path delay = sum of component delays + interconnect delays.
        """
        netlist = self.netlist
        delay = 0.0
        for name in path.path:
            comp = netlist.components.get(name)
            if comp:
                delay += comp.delay_ps

        # Add wire delay between consecutive components
        for i in range(len(path.path) - 1):
            a = netlist.components.get(path.path[i])
            b = netlist.components.get(path.path[i + 1])
            if a and b:
                ax, ay = a.center()
                bx, by = b.center()
                dist = math.hypot(bx - ax, by - ay)
                delay += dist * _WIRE_DELAY_PS_PER_UM

        return delay
