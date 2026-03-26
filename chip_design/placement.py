"""
布局优化策略 (Placement Optimization Strategies)

实现多种布局优化算法：
- 模拟退火 (Simulated Annealing)
- 贪心布局 (Greedy Placement)
- 网格布局 (Grid-based Placement)

(Implements multiple placement optimization algorithms:
 simulated annealing, greedy placement, and grid-based placement.)
"""

from __future__ import annotations

import math
import random
from copy import deepcopy
from typing import List, Optional, Tuple

from chip_design.netlist import Component, Netlist


class PlacementOptimizer:
    """
    布局优化器，提供多种优化算法来最小化总线长并消除重叠。
    Placement optimizer providing multiple algorithms to minimize total wirelength
    and eliminate overlaps.

    Usage::

        from chip_design import Netlist, Component, Net, PlacementOptimizer

        netlist = Netlist("my_design", die_width=200, die_height=200)
        # ... add components and nets ...
        optimizer = PlacementOptimizer(netlist, seed=42)
        result = optimizer.simulated_annealing(max_iterations=10000)
        print(result.summary())
    """

    def __init__(self, netlist: Netlist, seed: Optional[int] = None) -> None:
        """
        初始化布局优化器。
        Initialize the placement optimizer.

        Args:
            netlist: 待优化的网表 / Netlist to optimize
            seed: 随机数种子（用于可重复性）/ Random seed for reproducibility
        """
        self.netlist = netlist
        self._rng = random.Random(seed)

    # ------------------------------------------------------------------
    # 公共接口 / Public interface
    # ------------------------------------------------------------------

    def grid_placement(self) -> Netlist:
        """
        将所有未固定组件按网格均匀排列。
        Arrange all non-fixed components on a uniform grid.

        Returns:
            完成布局的网表副本 / A copy of the netlist with updated placements.
        """
        result = deepcopy(self.netlist)
        movable = [c for c in result.components.values() if not c.fixed]
        if not movable:
            return result

        cols = math.ceil(math.sqrt(len(movable)))
        rows = math.ceil(len(movable) / cols)
        cell_w = result.die_width / cols
        cell_h = result.die_height / rows

        for idx, comp in enumerate(movable):
            col = idx % cols
            row = idx // cols
            comp.x = col * cell_w + (cell_w - comp.width) / 2.0
            comp.y = row * cell_h + (cell_h - comp.height) / 2.0
            # Clamp to die boundary
            comp.x = max(0.0, min(comp.x, result.die_width - comp.width))
            comp.y = max(0.0, min(comp.y, result.die_height - comp.height))

        return result

    def greedy_placement(self) -> Netlist:
        """
        贪心布局：按顺序放置每个组件到使线长增量最小的位置。
        Greedy placement: place each component at the position that minimizes
        the incremental wirelength.

        Returns:
            完成布局的网表副本 / A copy of the netlist with updated placements.
        """
        result = self.grid_placement()
        movable = [c for c in result.components.values() if not c.fixed]

        # Try a set of candidate positions and pick the best
        candidates = self._candidate_positions(result)
        for comp in movable:
            best_cost = result.total_wirelength()
            best_x, best_y = comp.x, comp.y
            for cx, cy in candidates:
                nx = max(0.0, min(cx, result.die_width - comp.width))
                ny = max(0.0, min(cy, result.die_height - comp.height))
                comp.x, comp.y = nx, ny
                cost = result.total_wirelength()
                if cost < best_cost:
                    best_cost = cost
                    best_x, best_y = nx, ny
            comp.x, comp.y = best_x, best_y

        return result

    def simulated_annealing(
        self,
        max_iterations: int = 50_000,
        initial_temperature: float = 100.0,
        cooling_rate: float = 0.9995,
        overlap_penalty: float = 1000.0,
    ) -> Netlist:
        """
        模拟退火布局优化，同时最小化线长和组件重叠。
        Simulated Annealing placement optimization minimizing wirelength and
        component overlap simultaneously.

        Args:
            max_iterations: 最大迭代次数 / Maximum number of iterations
            initial_temperature: 初始温度 / Initial temperature
            cooling_rate: 冷却系数（每步乘以该系数）/ Cooling rate per iteration
            overlap_penalty: 重叠惩罚系数 / Penalty coefficient for overlaps

        Returns:
            优化后的网表副本 / Optimized copy of the netlist.
        """
        current = deepcopy(self.netlist)
        # Start from a grid placement to have a reasonable initial solution
        current = self.grid_placement()

        movable = [c.name for c in current.components.values() if not c.fixed]
        if not movable:
            return current

        best = deepcopy(current)
        best_cost = self._cost(best, overlap_penalty)
        current_cost = best_cost

        temperature = initial_temperature

        for _ in range(max_iterations):
            # Randomly pick a component and perturb its position
            name = self._rng.choice(movable)
            comp = current.components[name]
            old_x, old_y = comp.x, comp.y

            # Displacement scaled by temperature
            dx = self._rng.uniform(-temperature / 10.0, temperature / 10.0)
            dy = self._rng.uniform(-temperature / 10.0, temperature / 10.0)
            comp.x = max(0.0, min(comp.x + dx, current.die_width - comp.width))
            comp.y = max(0.0, min(comp.y + dy, current.die_height - comp.height))

            new_cost = self._cost(current, overlap_penalty)
            delta = new_cost - current_cost

            if delta < 0 or self._rng.random() < math.exp(-delta / max(temperature, 1e-9)):
                current_cost = new_cost
                if new_cost < best_cost:
                    best_cost = new_cost
                    best = deepcopy(current)
            else:
                comp.x, comp.y = old_x, old_y

            temperature *= cooling_rate

        return best

    # ------------------------------------------------------------------
    # 内部辅助方法 / Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _cost(netlist: Netlist, overlap_penalty: float) -> float:
        """计算总代价 = 线长 + 重叠惩罚 / Compute total cost = wirelength + overlap penalty."""
        return netlist.total_wirelength() + overlap_penalty * netlist.total_overlap_area()

    def _candidate_positions(self, netlist: Netlist, n_samples: int = 20) -> List[Tuple[float, float]]:
        """生成候选位置集合 / Generate a set of candidate positions."""
        positions: List[Tuple[float, float]] = []
        step_x = netlist.die_width / math.sqrt(n_samples)
        step_y = netlist.die_height / math.sqrt(n_samples)
        x = 0.0
        while x < netlist.die_width:
            y = 0.0
            while y < netlist.die_height:
                positions.append((x, y))
                y += step_y
            x += step_x
        return positions
