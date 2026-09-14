#!/usr/bin/env python3
"""Regression tests for Grok weekly-limit parsing.

The billing endpoint omits creditUsagePercent at the start of a new weekly
window (usage is zero). The collector used to treat that as a failed probe
and keep the previous period's 92% in the panel.
"""

import datetime as dt
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
grok = SourceFileLoader("omarchy_agent_usage_grok", str(ROOT / "omarchy-agent-usage-grok")).load_module()

# Captured from cli-chat-proxy /billing?format=credits on 2026-08-31 after
# the weekly window rolled (TUI showed 0%; the panel still showed 92%).
POST_RESET_CONFIG = {
  "currentPeriod": {
    "type": "USAGE_PERIOD_TYPE_WEEKLY",
    "start": "2026-08-31T19:34:47.098104+00:00",
    "end": "2026-09-07T19:34:47.098104+00:00",
  },
  "onDemandCap": {"val": 0},
  "onDemandUsed": {"val": 0},
  "isUnifiedBillingUser": True,
  "prepaidBalance": {"val": 0},
  "billingPeriodStart": "2026-08-31T19:34:47.098104+00:00",
  "billingPeriodEnd": "2026-09-07T19:34:47.098104+00:00",
}


class LimitsFromBillingConfig(unittest.TestCase):
  def test_omitted_percent_after_weekly_reset_is_zero(self):
    limits = grok.limits_from_billing_config(POST_RESET_CONFIG)
    self.assertEqual(len(limits), 1)
    self.assertEqual(limits[0]["percent"], 0.0)
    self.assertEqual(limits[0]["title"], "Weekly")
    self.assertTrue(limits[0]["resetsAt"].startswith("2026-09-07T19:34:47"))

  def test_api_percent_is_on_0_to_100_scale(self):
    config = {
      "creditUsagePercent": 92,
      "currentPeriod": {
        "type": "USAGE_PERIOD_TYPE_WEEKLY",
        "end": "2026-08-31T19:34:47.098104Z",
      },
    }
    limits = grok.limits_from_billing_config(config)
    self.assertEqual(limits[0]["percent"], 0.92)
    self.assertTrue(limits[0]["resetsAt"].startswith("2026-08-31T19:34:47"))

  def test_one_percent_is_not_treated_as_a_fraction(self):
    # Live payload after the 2026-08-31 reset: creditUsagePercent is 1.0,
    # meaning 1%, which the TUI rounds to 0%. The old n>1 heuristic mapped
    # 1.0 onto 100%.
    config = dict(POST_RESET_CONFIG)
    config["creditUsagePercent"] = 1.0
    config["productUsage"] = [{"product": "GrokBuild", "usagePercent": 1.0}]
    self.assertEqual(grok.limits_from_billing_config(config)[0]["percent"], 0.01)

  def test_explicit_zero_is_zero(self):
    config = {
      "creditUsagePercent": 0,
      "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "end": "2026-09-07T19:34:47Z"},
    }
    self.assertEqual(grok.limits_from_billing_config(config)[0]["percent"], 0.0)

  def test_empty_config_has_no_limits(self):
    self.assertEqual(grok.limits_from_billing_config({}), [])


class UsableCachedLimits(unittest.TestCase):
  def test_drops_windows_that_have_already_reset(self):
    cached = [{
      "label": "Weekly (7-day)",
      "percent": 0.92,
      "resetsAt": "2026-08-31T19:34:47.098104Z",
      "title": "Weekly",
    }]
    now = dt.datetime(2026, 8, 31, 20, 30, tzinfo=dt.timezone.utc)
    self.assertEqual(grok.usable_cached_limits(cached, now=now), [])

  def test_keeps_windows_that_have_not_reset(self):
    cached = [{
      "label": "Weekly (7-day)",
      "percent": 0.41,
      "resetsAt": "2026-09-07T19:34:47.098104Z",
      "title": "Weekly",
    }]
    now = dt.datetime(2026, 8, 31, 20, 30, tzinfo=dt.timezone.utc)
    kept = grok.usable_cached_limits(cached, now=now)
    self.assertEqual(len(kept), 1)
    self.assertEqual(kept[0]["percent"], 0.41)


if __name__ == "__main__":
  unittest.main()
