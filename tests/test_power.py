"""Tests for chip_design.power module."""

from __future__ import annotations

import pytest

from chip_design.netlist import Component, Net, Netlist
from chip_design.power import PowerBreakdown, PowerOptimizationSuggestion, PowerOptimizer


class TestPowerAnalysis:
    def test_analyze_returns_breakdown(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist, activity_factor=0.2)
        bd = opt.analyze()
        assert isinstance(bd, PowerBreakdown)

    def test_total_power_positive(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist, activity_factor=0.2)
        bd = opt.analyze()
        assert bd.total_mw > 0.0

    def test_total_equals_dynamic_plus_leakage(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist, activity_factor=0.2)
        bd = opt.analyze()
        assert bd.total_mw == pytest.approx(bd.dynamic_mw + bd.leakage_mw)

    def test_zero_activity_zero_dynamic(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist, activity_factor=0.0)
        bd = opt.analyze()
        assert bd.dynamic_mw == pytest.approx(0.0)

    def test_top_consumers_sorted_descending(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist, activity_factor=0.5)
        bd = opt.analyze(top_n=10)
        powers = [p for _, p in bd.top_consumers]
        assert powers == sorted(powers, reverse=True)

    def test_top_consumers_limited_by_top_n(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist, activity_factor=0.2)
        bd = opt.analyze(top_n=2)
        assert len(bd.top_consumers) <= 2

    def test_summary_contains_total(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist)
        bd = opt.analyze()
        assert "Total" in bd.summary()

    def test_activity_factor_clamped(self):
        nl = Netlist("t")
        nl.add_component(Component("C1", "AND2", power_mw=1.0))
        opt_over = PowerOptimizer(nl, activity_factor=2.0)
        opt_under = PowerOptimizer(nl, activity_factor=-1.0)
        assert opt_over.activity_factor == pytest.approx(1.0)
        assert opt_under.activity_factor == pytest.approx(0.0)


class TestPowerSuggestions:
    def test_multi_vt_suggestions_for_buffers(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist, activity_factor=0.5)
        suggestions = opt.suggest_optimizations()
        multi_vt = [s for s in suggestions if s.suggestion_type == "multi_vt"]
        # BUF C4 should trigger a multi_vt suggestion
        assert len(multi_vt) > 0

    def test_clock_gating_suggestion_for_many_ffs(self, multi_ff_netlist):
        opt = PowerOptimizer(multi_ff_netlist, activity_factor=0.5)
        suggestions = opt.suggest_optimizations()
        cg = [s for s in suggestions if s.suggestion_type == "clock_gating"]
        assert len(cg) > 0

    def test_no_clock_gating_for_few_ffs(self):
        nl = Netlist("few_ffs")
        nl.add_component(Component("FF0", "FF", power_mw=0.5))
        nl.add_component(Component("FF1", "FF", power_mw=0.5))
        opt = PowerOptimizer(nl, activity_factor=0.5)
        suggestions = opt.suggest_optimizations()
        cg = [s for s in suggestions if s.suggestion_type == "clock_gating"]
        assert len(cg) == 0

    def test_buffer_removal_suggestion(self):
        nl = Netlist("buf_test")
        nl.add_component(Component("BUF0", "BUF", power_mw=0.1))
        nl.add_component(Component("SINK", "AND2"))
        nl.add_net(Net("NB", driver="BUF0", sinks=["SINK"]))
        opt = PowerOptimizer(nl, activity_factor=0.5)
        suggestions = opt.suggest_optimizations()
        br = [s for s in suggestions if s.suggestion_type == "buffer_removal"]
        assert len(br) > 0

    def test_suggestion_saving_positive(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist, activity_factor=0.5)
        suggestions = opt.suggest_optimizations()
        for s in suggestions:
            assert s.estimated_saving_mw >= 0.0

    def test_suggestion_repr(self, simple_netlist):
        opt = PowerOptimizer(simple_netlist)
        suggestions = opt.suggest_optimizations()
        for s in suggestions:
            assert isinstance(repr(s), str)
