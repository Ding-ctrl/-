"""Tests for chip_design.netlist module."""

from __future__ import annotations

import pytest

from chip_design.netlist import Component, Net, Netlist


class TestComponent:
    def test_center(self):
        comp = Component("A", "AND2", width=4.0, height=6.0, x=10.0, y=20.0)
        assert comp.center() == (12.0, 23.0)

    def test_overlaps_true(self):
        a = Component("A", "AND2", width=4, height=4, x=0, y=0)
        b = Component("B", "OR2", width=4, height=4, x=2, y=2)
        assert a.overlaps(b)

    def test_overlaps_false_adjacent(self):
        a = Component("A", "AND2", width=4, height=4, x=0, y=0)
        b = Component("B", "OR2", width=4, height=4, x=4, y=0)
        assert not a.overlaps(b)

    def test_overlaps_false_far(self):
        a = Component("A", "AND2", width=2, height=2, x=0, y=0)
        b = Component("B", "OR2", width=2, height=2, x=10, y=10)
        assert not a.overlaps(b)

    def test_repr_contains_name(self):
        comp = Component("myCell", "FF")
        assert "myCell" in repr(comp)


class TestNet:
    def test_all_components(self):
        net = Net("N1", driver="D", sinks=["A", "B", "C"])
        assert net.all_components() == ["D", "A", "B", "C"]

    def test_hpwl_two_comps(self):
        nl = Netlist("t", die_width=100, die_height=100)
        nl.add_component(Component("D", "BUF", width=2, height=2, x=0, y=0))
        nl.add_component(Component("S", "AND2", width=2, height=2, x=10, y=10))
        net = Net("N", driver="D", sinks=["S"])
        nl.add_net(net)
        # centers: D=(1,1), S=(11,11)  -> HPWL = (11-1) + (11-1) = 20
        assert net.half_perimeter_wirelength(nl) == pytest.approx(20.0)

    def test_hpwl_single_comp(self):
        nl = Netlist("t", die_width=100, die_height=100)
        nl.add_component(Component("D", "BUF", width=2, height=2, x=0, y=0))
        net = Net("N", driver="D", sinks=[])
        assert net.half_perimeter_wirelength(nl) == 0.0


class TestNetlist:
    def test_add_and_retrieve_component(self):
        nl = Netlist("design")
        c = Component("C1", "AND2")
        nl.add_component(c)
        assert "C1" in nl.components
        assert nl.components["C1"] is c

    def test_add_and_retrieve_net(self):
        nl = Netlist("design")
        net = Net("N1", driver="D", sinks=["S"])
        nl.add_net(net)
        assert "N1" in nl.nets

    def test_total_wirelength(self, simple_netlist):
        wl = simple_netlist.total_wirelength()
        assert wl > 0

    def test_no_overlap_after_legal_placement(self):
        nl = Netlist("t", die_width=50, die_height=50)
        nl.add_component(Component("A", "AND2", width=5, height=5, x=0, y=0))
        nl.add_component(Component("B", "OR2", width=5, height=5, x=10, y=0))
        assert nl.total_overlap_area() == pytest.approx(0.0)

    def test_overlap_area_detected(self):
        nl = Netlist("t", die_width=50, die_height=50)
        nl.add_component(Component("A", "AND2", width=5, height=5, x=0, y=0))
        nl.add_component(Component("B", "OR2", width=5, height=5, x=2, y=2))
        assert nl.total_overlap_area() > 0

    def test_is_legal_valid(self):
        nl = Netlist("t", die_width=50, die_height=50)
        nl.add_component(Component("A", "AND2", width=5, height=5, x=0, y=0))
        nl.add_component(Component("B", "OR2", width=5, height=5, x=10, y=0))
        assert nl.is_legal()

    def test_is_legal_out_of_bounds(self):
        nl = Netlist("t", die_width=10, die_height=10)
        nl.add_component(Component("A", "AND2", width=5, height=5, x=8, y=8))
        assert not nl.is_legal()

    def test_summary_contains_design_name(self, simple_netlist):
        assert "test_design" in simple_netlist.summary()
