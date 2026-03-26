"""Tests for chip_design.timing module."""

from __future__ import annotations

import pytest

from chip_design.netlist import Component, Net, Netlist
from chip_design.timing import TimingAnalyzer, TimingReport


class TestTimingAnalyzer:
    def test_analyze_returns_report(self, simple_netlist):
        analyzer = TimingAnalyzer(simple_netlist, clock_period_ps=500.0)
        report = analyzer.analyze()
        assert isinstance(report, TimingReport)

    def test_report_has_paths(self, simple_netlist):
        analyzer = TimingAnalyzer(simple_netlist, clock_period_ps=500.0)
        report = analyzer.analyze()
        assert len(report.all_paths) > 0

    def test_timing_met_with_large_period(self, simple_netlist):
        # With a very large clock period, all paths should meet timing
        analyzer = TimingAnalyzer(simple_netlist, clock_period_ps=100_000.0)
        report = analyzer.analyze()
        assert report.timing_met()
        assert report.wns_ps > 0.0

    def test_timing_violated_with_tiny_period(self, simple_netlist):
        # With an impossibly tight clock period, timing should fail
        analyzer = TimingAnalyzer(simple_netlist, clock_period_ps=1.0)
        report = analyzer.analyze()
        assert not report.timing_met()
        assert report.wns_ps < 0.0

    def test_wns_is_minimum_slack(self, simple_netlist):
        analyzer = TimingAnalyzer(simple_netlist, clock_period_ps=500.0)
        report = analyzer.analyze()
        min_slack = min(p.slack_ps for p in report.all_paths)
        assert report.wns_ps == pytest.approx(min_slack)

    def test_tns_is_sum_of_negative_slacks(self, simple_netlist):
        analyzer = TimingAnalyzer(simple_netlist, clock_period_ps=50.0)
        report = analyzer.analyze()
        expected_tns = sum(p.slack_ps for p in report.all_paths if p.slack_ps < 0.0)
        assert report.tns_ps == pytest.approx(expected_tns)

    def test_critical_paths_marked(self, simple_netlist):
        analyzer = TimingAnalyzer(simple_netlist, clock_period_ps=1.0)
        report = analyzer.analyze()
        for path in report.critical_paths:
            assert path.is_critical
            assert path.slack_ps < 0.0

    def test_path_delay_positive(self, simple_netlist):
        analyzer = TimingAnalyzer(simple_netlist, clock_period_ps=1000.0)
        report = analyzer.analyze()
        for path in report.all_paths:
            assert path.total_delay_ps >= 0.0

    def test_empty_netlist(self):
        nl = Netlist("empty")
        analyzer = TimingAnalyzer(nl, clock_period_ps=1000.0)
        report = analyzer.analyze()
        assert len(report.all_paths) == 0
        assert report.timing_met()

    def test_summary_contains_status(self, simple_netlist):
        analyzer = TimingAnalyzer(simple_netlist, clock_period_ps=100_000.0)
        report = analyzer.analyze()
        summary = report.summary()
        assert "PASS" in summary or "FAIL" in summary

    def test_single_component_no_net(self):
        nl = Netlist("solo")
        nl.add_component(Component("C1", "AND2", delay_ps=15))
        analyzer = TimingAnalyzer(nl, clock_period_ps=1000.0)
        report = analyzer.analyze()
        # A single isolated component forms no multi-hop path; timing is trivially met
        assert len(report.all_paths) == 0
        assert report.timing_met()
