"""
布线优化模块 (Routing Optimization Module)

提供全局布线和详细布线的基础工具：
- 基于 Steiner 树近似的最小线长估算 (Steiner tree approximation)
- 拥塞热图生成 (Congestion heatmap generation)
- 布线违规检测 (Routing violation detection)

(Provides foundational tools for global and detailed routing:
 Steiner tree approximation, congestion heatmap, and violation detection.)
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from chip_design.netlist import Net, Netlist


@dataclass
class RouteSegment:
    """
    一条布线段（水平或垂直线段）。
    A routing segment (horizontal or vertical wire segment).

    Attributes:
        x1, y1: 起点坐标 / Start coordinates
        x2, y2: 终点坐标 / End coordinates
        layer: 布线层（1=M1, 2=M2, ...）/ Routing layer
        net_name: 所属网络名 / Net name
    """

    x1: float
    y1: float
    x2: float
    y2: float
    layer: int = 1
    net_name: str = ""

    @property
    def length(self) -> float:
        """布线段长度 / Segment length."""
        return math.hypot(self.x2 - self.x1, self.y2 - self.y1)

    def __repr__(self) -> str:
        return (
            f"RouteSegment(({self.x1:.1f},{self.y1:.1f})->({self.x2:.1f},{self.y2:.1f}), "
            f"L{self.layer}, net={self.net_name!r})"
        )


@dataclass
class CongestionMap:
    """
    布线拥塞热图。
    Routing congestion heatmap.

    Attributes:
        grid_rows: 网格行数 / Number of grid rows
        grid_cols: 网格列数 / Number of grid columns
        density: 各网格单元的线密度矩阵 / Wire density per grid cell
        die_width: 芯片宽度 / Die width
        die_height: 芯片高度 / Die height
    """

    grid_rows: int
    grid_cols: int
    density: List[List[float]]
    die_width: float
    die_height: float

    def max_congestion(self) -> float:
        """最大拥塞密度 / Maximum congestion density."""
        return max(d for row in self.density for d in row)

    def average_congestion(self) -> float:
        """平均拥塞密度 / Average congestion density."""
        flat = [d for row in self.density for d in row]
        return sum(flat) / len(flat) if flat else 0.0

    def hotspots(self, threshold: float = 0.8) -> List[Tuple[int, int, float]]:
        """
        返回密度超过阈值的网格单元。
        Return grid cells with density above threshold.

        Args:
            threshold: 密度阈值（相对于最大值）/ Density threshold relative to max

        Returns:
            (row, col, density) 元组列表 / List of (row, col, density) tuples
        """
        max_d = self.max_congestion()
        if max_d == 0.0:
            return []
        spots = []
        for r, row in enumerate(self.density):
            for c, d in enumerate(row):
                if d / max_d >= threshold:
                    spots.append((r, c, d))
        return spots

    def summary(self) -> str:
        """返回拥塞图摘要 / Return congestion map summary."""
        hotspot_count = len(self.hotspots())
        return (
            f"CongestionMap {self.grid_rows}x{self.grid_cols}: "
            f"avg={self.average_congestion():.3f}, "
            f"max={self.max_congestion():.3f}, "
            f"hotspots={hotspot_count}"
        )


@dataclass
class RoutingReport:
    """
    布线分析报告。
    Routing analysis report.

    Attributes:
        total_wirelength: 总估算线长（微米）/ Total estimated wirelength in µm
        segments: 布线段列表 / List of route segments
        congestion_map: 拥塞热图 / Congestion map
        violations: 布线违规列表（网络名）/ Routing violations (net names)
    """

    total_wirelength: float = 0.0
    segments: List[RouteSegment] = field(default_factory=list)
    congestion_map: Optional[CongestionMap] = None
    violations: List[str] = field(default_factory=list)

    def summary(self) -> str:
        """返回布线报告摘要 / Return routing report summary."""
        lines = [
            "Routing Report:",
            f"  Total wirelength : {self.total_wirelength:.2f} µm",
            f"  Route segments   : {len(self.segments)}",
            f"  Violations       : {len(self.violations)}",
        ]
        if self.congestion_map:
            lines.append(f"  Congestion       : {self.congestion_map.summary()}")
        return "\n".join(lines)

    def __repr__(self) -> str:
        return self.summary()


class RoutingOptimizer:
    """
    布线优化器：生成 L 形布线并分析拥塞。
    Routing optimizer: generates L-shaped routes and analyzes congestion.

    Usage::

        from chip_design import Netlist, RoutingOptimizer

        netlist = Netlist("my_design")
        # ... populate and place netlist ...
        router = RoutingOptimizer(netlist, grid_rows=10, grid_cols=10)
        report = router.route()
        print(report.summary())
    """

    def __init__(
        self,
        netlist: Netlist,
        grid_rows: int = 10,
        grid_cols: int = 10,
        preferred_h_layer: int = 1,
        preferred_v_layer: int = 2,
    ) -> None:
        """
        初始化布线优化器。
        Initialize the routing optimizer.

        Args:
            netlist: 已完成布局的网表 / Placed netlist
            grid_rows: 拥塞网格行数 / Number of congestion grid rows
            grid_cols: 拥塞网格列数 / Number of congestion grid columns
            preferred_h_layer: 水平布线首选层 / Preferred layer for horizontal routes
            preferred_v_layer: 垂直布线首选层 / Preferred layer for vertical routes
        """
        self.netlist = netlist
        self.grid_rows = grid_rows
        self.grid_cols = grid_cols
        self.preferred_h_layer = preferred_h_layer
        self.preferred_v_layer = preferred_v_layer

    def route(self) -> RoutingReport:
        """
        执行简单 L 形布线并生成布线报告。
        Perform simple L-shaped routing and generate a routing report.

        Returns:
            RoutingReport 实例 / A RoutingReport instance
        """
        all_segments: List[RouteSegment] = []
        violations: List[str] = []

        for net in self.netlist.nets.values():
            segs = self._route_net(net)
            if not segs and net.sinks:
                violations.append(net.name)
            all_segments.extend(segs)

        total_wl = sum(s.length for s in all_segments)
        cmap = self._build_congestion_map(all_segments)

        return RoutingReport(
            total_wirelength=total_wl,
            segments=all_segments,
            congestion_map=cmap,
            violations=violations,
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _route_net(self, net: Net) -> List[RouteSegment]:
        """
        使用简单的中心-辐射拓扑为网络生成 L 形布线段。
        Generate L-shaped route segments for a net using a star topology.
        """
        netlist = self.netlist
        driver = netlist.components.get(net.driver)
        if driver is None:
            return []

        segments: List[RouteSegment] = []
        dx, dy = driver.center()

        for sink_name in net.sinks:
            sink = netlist.components.get(sink_name)
            if sink is None:
                continue
            sx, sy = sink.center()

            # L-shaped route: horizontal then vertical
            # Horizontal segment on preferred_h_layer
            if not math.isclose(dx, sx):
                segments.append(
                    RouteSegment(
                        x1=dx, y1=dy, x2=sx, y2=dy,
                        layer=self.preferred_h_layer,
                        net_name=net.name,
                    )
                )
            # Vertical segment on preferred_v_layer
            if not math.isclose(dy, sy):
                segments.append(
                    RouteSegment(
                        x1=sx, y1=dy, x2=sx, y2=sy,
                        layer=self.preferred_v_layer,
                        net_name=net.name,
                    )
                )

        return segments

    def _build_congestion_map(self, segments: List[RouteSegment]) -> CongestionMap:
        """
        将布线段投影到网格，构建拥塞密度矩阵。
        Project route segments onto the grid to build a congestion density matrix.
        """
        rows = self.grid_rows
        cols = self.grid_cols
        die_w = self.netlist.die_width
        die_h = self.netlist.die_height
        cell_w = die_w / cols
        cell_h = die_h / rows

        density = [[0.0] * cols for _ in range(rows)]

        for seg in segments:
            # Find which grid cells the segment passes through (bounding box approximation)
            min_x = min(seg.x1, seg.x2)
            max_x = max(seg.x1, seg.x2)
            min_y = min(seg.y1, seg.y2)
            max_y = max(seg.y1, seg.y2)

            c_start = max(0, min(int(min_x / cell_w), cols - 1))
            c_end = max(0, min(int(max_x / cell_w), cols - 1))
            r_start = max(0, min(int(min_y / cell_h), rows - 1))
            r_end = max(0, min(int(max_y / cell_h), rows - 1))

            for r in range(r_start, r_end + 1):
                for c in range(c_start, c_end + 1):
                    density[r][c] += seg.length / ((r_end - r_start + 1) * (c_end - c_start + 1))

        return CongestionMap(
            grid_rows=rows,
            grid_cols=cols,
            density=density,
            die_width=die_w,
            die_height=die_h,
        )
