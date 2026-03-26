"""Shared test fixtures for chip design tests."""

from __future__ import annotations

import pytest

from chip_design.netlist import Component, Net, Netlist


@pytest.fixture
def simple_netlist() -> Netlist:
    """
    A small netlist with 4 components and 3 nets arranged in a chain:
        C1 -> C2 -> C3 -> C4
    """
    nl = Netlist("test_design", die_width=100.0, die_height=100.0)

    nl.add_component(Component("C1", "AND2", width=2, height=2, x=5, y=5, delay_ps=10, power_mw=0.1))
    nl.add_component(Component("C2", "OR2", width=2, height=2, x=30, y=30, delay_ps=12, power_mw=0.12))
    nl.add_component(Component("C3", "FF", width=3, height=3, x=60, y=60, delay_ps=20, power_mw=0.5))
    nl.add_component(Component("C4", "BUF", width=1, height=1, x=80, y=80, delay_ps=5, power_mw=0.05))

    nl.add_net(Net("N1", driver="C1", sinks=["C2"]))
    nl.add_net(Net("N2", driver="C2", sinks=["C3"]))
    nl.add_net(Net("N3", driver="C3", sinks=["C4"]))

    return nl


@pytest.fixture
def multi_ff_netlist() -> Netlist:
    """A netlist with many flip-flops for testing clock gating suggestions."""
    nl = Netlist("ff_design", die_width=200.0, die_height=200.0)

    for i in range(8):
        nl.add_component(
            Component(
                f"FF{i}",
                "FF",
                width=3,
                height=3,
                x=float(i * 20),
                y=10.0,
                delay_ps=20,
                power_mw=0.5,
            )
        )

    for i in range(4):
        nl.add_component(
            Component(
                f"BUF{i}",
                "BUF",
                width=1,
                height=1,
                x=float(i * 20),
                y=50.0,
                delay_ps=5,
                power_mw=0.05,
            )
        )
        nl.add_net(Net(f"NB{i}", driver=f"BUF{i}", sinks=[f"FF{i}"]))

    return nl
