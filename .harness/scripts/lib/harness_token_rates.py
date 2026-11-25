#!/usr/bin/env python3
"""Token rates for the local telemetry collectors -- ONE implementation (C2, C7).

Rates come from .harness/control/token-pricing.json, never from code. The Codex
collector (codex_collect.py) and the Claude sampler (agentops-sampler.sh, and the
.ps1 twin which mirrors this logic natively) all cost tokens through here, so the
Cost dashboard compares every assistant on the same yardstick.

Rules (C13/C14): a model id is matched EXACTLY against the keys in `models`; an
absent key falls to `default`; a null rate means UNPRICED -> cost 0.0 and a basis
that says so. A plausible-looking invented cost is worse than a visible gap,
because nobody audits a number that looks fine. Until 13-11-2026 the Claude
sampler hardcoded $3/$15 for every model, which matched NO model in the table.

(Named `token_rates`, not `pricing`: the F2 rule `money` guards `*pricing*` paths
so an AI session cannot rewrite the RATES file; this module holds no rate.)
"""
from __future__ import annotations

import json
import os


def load_pricing(path: str) -> dict:
    """Unreadable rates are NOT fatal: tokens are the primary measurement and must
    still be collected. Cost degrades to unpriced, which is visible."""
    try:
        with open(path, "r", encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return {}


def rates_path(root: str) -> str:
    return os.path.join(root, ".harness", "control", "token-pricing.json")


def rates_for(pricing: dict, model: str) -> dict:
    models = pricing.get("models") or {}
    rates = models.get(model)
    if rates is None:
        rates = pricing.get("default") or {}
    return rates or {}


def estimate_cost(pricing: dict, model: str, new_input: int, cached_input: int, output: int):
    """-> (cost_usd, basis). basis is why the number is what it is:
    priced | priced_no_cache_rate | unpriced."""
    r = rates_for(pricing, model)
    r_in, r_out = r.get("input"), r.get("output")
    if r_in is None or r_out is None:
        return 0.0, "unpriced"
    r_cached = r.get("cached_input")
    basis = "priced"
    if r_cached is None:
        # No cache rate: charge cache reads at the full input rate and SAY SO -- but
        # only when there are cache reads to charge; a collector that does not count
        # them (the Claude sampler) is simply priced.
        r_cached = r_in
        if cached_input:
            basis = "priced_no_cache_rate"
    cost = (new_input * r_in + cached_input * r_cached + output * r_out) / 1_000_000.0
    return round(cost, 6), basis
