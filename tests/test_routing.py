"""Tests for chip_design.routing module."""

from __future__ import annotations

import pytest

from chip_design.netlist import Component, Net, Netlist
from chip_design.routing import CongestionMap, RoutingOptimizer, RoutingReport, RouteSegment


@pytest.fixture
def placed_netlist() -> Netlist:
    """A simple placed netlist for routing tests."""
    nl = Netlist("route_test", die_width=100.0, die_height=100.0)
    nl.add_component(Component("D1", "AND2", width=2, height=2, x=10, y=10))
    nl.add_component(Component("S1", "OR2", width=2, height=2, x=50, y=10))
    nl.add_component(Component("S2", "FF", width=3, height=3, x=10, y=60))
    nl.add_component(Component("S3", "BUF", width=1, height=1, x=70, y=70))
    nl.add_net(Net("N1", driver="D1", sinks=["S1", "S2"]))
    nl.add_net(Net("N2", driver="S1", sinks=["S3"]))
    return nl


class TestRouteSegment:
    def test_length_horizontal(self):
        seg = RouteSegment(x1=0, y1=5, x2=10, y2=5)
        assert seg.length == pytest.approx(10.0)

    def test_length_vertical(self):
        seg = RouteSegment(x1=3, y1=0, x2=3, y2=8)
        assert seg.length == pytest.approx(8.0)

    def test_length_diagonal(self):
        seg = RouteSegment(x1=0, y1=0, x2=3, y2=4)
        assert seg.length == pytest.approx(5.0)

    def test_repr(self):
        seg = RouteSegment(x1=0, y1=0, x2=10, y2=0, layer=1, net_name="N1")
        assert "N1" in repr(seg)


class TestCongestionMap:
    def test_max_congestion(self):
        density = [[0.0, 1.0], [2.0, 0.5]]
        cmap = CongestionMap(grid_rows=2, grid_cols=2, density=density, die_width=10, die_height=10)
        assert cmap.max_congestion() == pytest.approx(2.0)

    def test_average_congestion(self):
        density = [[1.0, 1.0], [1.0, 1.0]]
        cmap = CongestionMap(grid_rows=2, grid_cols=2, density=density, die_width=10, die_height=10)
        assert cmap.average_congestion() == pytest.approx(1.0)

    def test_hotspots_detected(self):
        density = [[0.0, 0.0], [0.0, 10.0]]
        cmap = CongestionMap(grid_rows=2, grid_cols=2, density=density, die_width=10, die_height=10)
        spots = cmap.hotspots(threshold=0.9)
        assert len(spots) == 1
        r, c, d = spots[0]
        assert d == pytest.approx(10.0)

    def test_no_hotspots_uniform(self):
        density = [[1.0, 1.0], [1.0, 1.0]]
        cmap = CongestionMap(grid_rows=2, grid_cols=2, density=density, die_width=10, die_height=10)
        spots = cmap.hotspots(threshold=0.99)
        # All cells are equal, all qualify as hotspots
        assert len(spots) == 4

    def test_summary_string(self):
        density = [[1.0, 2.0], [0.5, 0.5]]
        cmap = CongestionMap(grid_rows=2, grid_cols=2, density=density, die_width=10, die_height=10)
        assert "CongestionMap" in cmap.summary()


class TestRoutingOptimizer:
    def test_route_returns_report(self, placed_netlist):
        router = RoutingOptimizer(placed_netlist)
        report = router.route()
        assert isinstance(report, RoutingReport)

    def test_total_wirelength_positive(self, placed_netlist):
        router = RoutingOptimizer(placed_netlist)
        report = router.route()
        assert report.total_wirelength > 0.0

    def test_segments_generated(self, placed_netlist):
        router = RoutingOptimizer(placed_netlist)
        report = router.route()
        assert len(report.segments) > 0

    def test_congestion_map_generated(self, placed_netlist):
        router = RoutingOptimizer(placed_netlist, grid_rows=5, grid_cols=5)
        report = router.route()
        assert report.congestion_map is not None
        assert report.congestion_map.grid_rows == 5
        assert report.congestion_map.grid_cols == 5

    def test_no_violations_for_valid_netlist(self, placed_netlist):
        router = RoutingOptimizer(placed_netlist)
        report = router.route()
        assert len(report.violations) == 0

    def test_violation_for_missing_driver(self):
        nl = Netlist("bad", die_width=100, die_height=100)
        nl.add_component(Component("SINK", "AND2", x=10, y=10, width=2, height=2))
        nl.add_net(Net("GHOST_NET", driver="MISSING_DRIVER", sinks=["SINK"]))
        router = RoutingOptimizer(nl)
        report = router.route()
        assert "GHOST_NET" in report.violations

    def test_summary_string(self, placed_netlist):
        router = RoutingOptimizer(placed_netlist)
        report = router.route()
        assert "Routing Report" in report.summary()

    def test_layer_assignment(self, placed_netlist):
        router = RoutingOptimizer(placed_netlist, preferred_h_layer=1, preferred_v_layer=2)
        report = router.route()
        layers = {s.layer for s in report.segments}
        assert layers.issubset({1, 2})
