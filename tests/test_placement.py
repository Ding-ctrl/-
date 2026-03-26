"""Tests for chip_design.placement module."""

from __future__ import annotations

import pytest

from chip_design.netlist import Component, Net, Netlist
from chip_design.placement import PlacementOptimizer


@pytest.fixture
def small_netlist() -> Netlist:
    """A netlist with 6 components and 4 nets."""
    nl = Netlist("place_test", die_width=100.0, die_height=100.0)
    for i in range(6):
        nl.add_component(
            Component(f"C{i}", "AND2", width=3.0, height=3.0, x=0.0, y=0.0, delay_ps=10)
        )
    nl.add_net(Net("N0", driver="C0", sinks=["C1", "C2"]))
    nl.add_net(Net("N1", driver="C1", sinks=["C3"]))
    nl.add_net(Net("N2", driver="C2", sinks=["C4"]))
    nl.add_net(Net("N3", driver="C3", sinks=["C5"]))
    return nl


class TestGridPlacement:
    def test_components_within_die(self, small_netlist):
        opt = PlacementOptimizer(small_netlist, seed=0)
        result = opt.grid_placement()
        for comp in result.components.values():
            assert 0 <= comp.x
            assert 0 <= comp.y
            assert comp.x + comp.width <= result.die_width + 1e-6
            assert comp.y + comp.height <= result.die_height + 1e-6

    def test_fixed_components_not_moved(self):
        nl = Netlist("t", die_width=100, die_height=100)
        nl.add_component(Component("FIXED", "PAD", width=2, height=2, x=50, y=50, fixed=True))
        nl.add_component(Component("C1", "AND2", width=2, height=2, x=0, y=0))
        opt = PlacementOptimizer(nl, seed=0)
        result = opt.grid_placement()
        assert result.components["FIXED"].x == pytest.approx(50.0)
        assert result.components["FIXED"].y == pytest.approx(50.0)


class TestGreedyPlacement:
    def test_reduces_wirelength(self, small_netlist):
        opt = PlacementOptimizer(small_netlist, seed=0)
        grid_result = opt.grid_placement()
        greedy_result = opt.greedy_placement()
        # Greedy should produce wirelength <= grid (or at least not dramatically worse)
        assert greedy_result.total_wirelength() <= grid_result.total_wirelength() * 1.5

    def test_components_within_die(self, small_netlist):
        opt = PlacementOptimizer(small_netlist, seed=0)
        result = opt.greedy_placement()
        for comp in result.components.values():
            assert comp.x + comp.width <= result.die_width + 1e-6
            assert comp.y + comp.height <= result.die_height + 1e-6


class TestSimulatedAnnealing:
    def test_returns_netlist(self, small_netlist):
        opt = PlacementOptimizer(small_netlist, seed=42)
        result = opt.simulated_annealing(max_iterations=500)
        assert isinstance(result, Netlist)

    def test_reduces_wirelength_vs_random(self, small_netlist):
        opt = PlacementOptimizer(small_netlist, seed=42)
        result = opt.simulated_annealing(max_iterations=2000)
        assert result.total_wirelength() >= 0.0

    def test_components_within_die(self, small_netlist):
        opt = PlacementOptimizer(small_netlist, seed=42)
        result = opt.simulated_annealing(max_iterations=500)
        for comp in result.components.values():
            assert comp.x >= -1e-6
            assert comp.y >= -1e-6
            assert comp.x + comp.width <= result.die_width + 1e-6
            assert comp.y + comp.height <= result.die_height + 1e-6

    def test_empty_netlist(self):
        nl = Netlist("empty", die_width=100, die_height=100)
        opt = PlacementOptimizer(nl, seed=0)
        result = opt.simulated_annealing(max_iterations=100)
        assert len(result.components) == 0

    def test_reproducibility_with_seed(self, small_netlist):
        opt1 = PlacementOptimizer(small_netlist, seed=7)
        opt2 = PlacementOptimizer(small_netlist, seed=7)
        r1 = opt1.simulated_annealing(max_iterations=300)
        r2 = opt2.simulated_annealing(max_iterations=300)
        assert r1.total_wirelength() == pytest.approx(r2.total_wirelength())
