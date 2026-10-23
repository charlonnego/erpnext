"""Tests for deterministic live-data operational insight generation."""
from unittest.mock import patch

from frappe.tests.utils import FrappeTestCase

from erpnext.operations_intelligence import engine


class TestOperationsIntelligenceEngine(FrappeTestCase):
    def test_snapshot_builds_alerts_only_from_returned_records(self):
        overview = {
            "company": "Real Company",
            "currency": "NGN",
            "from_date": "2026-10-01",
            "to_date": "2026-10-24",
            "metrics": {
                "sales_value": 1200.0,
                "purchase_value": 600.0,
                "outstanding_receivables": 500.0,
                "outstanding_payables": 200.0,
                "overdue_sales_invoice_count": 1,
            },
        }
        actions = {
            "items": [
                {"kind": "Receivable", "name": "SINV-001", "outstanding_amount": 500.0},
                {"kind": "Payable", "name": "PINV-001", "outstanding_amount": 200.0},
            ]
        }
        stock = {
            "items": [
                {"item_code": "ITEM-001", "actual_qty": 0, "reorder_level": 5},
            ]
        }
        with (
            patch.object(engine, "get_overview", return_value=overview),
            patch.object(engine, "get_action_items", return_value=actions),
            patch.object(engine, "get_low_stock_items", return_value=stock),
            patch("erpnext.operations_intelligence.engine.frappe.utils.today", return_value="2026-10-24"),
            patch("erpnext.operations_intelligence.engine.frappe.utils.fmt_money", side_effect=lambda value, **kwargs: str(value)),
        ):
            result = engine.get_engine_snapshot("2026-10-01", "2026-10-24")

        self.assertEqual(result["mode"], "live_read_only")
        self.assertEqual(result["company"], "Real Company")
        self.assertFalse(result["write_operations_performed"])
        self.assertEqual(
            {alert["key"] for alert in result["alerts"]},
            {"overdue_receivables", "overdue_payables", "low_stock"},
        )
        self.assertEqual(result["alerts"][0]["amount"], 500.0)
        self.assertEqual(result["alerts"][2]["severity"], "high")
        self.assertEqual(result["action_items"], actions["items"])
        self.assertEqual(result["low_stock_items"], stock["items"])

    def test_snapshot_does_not_invent_alerts_when_sources_are_empty(self):
        overview = {
            "company": "Real Company",
            "currency": "NGN",
            "from_date": "2026-10-01",
            "to_date": "2026-10-24",
            "metrics": {},
        }
        with (
            patch.object(engine, "get_overview", return_value=overview),
            patch.object(engine, "get_action_items", return_value={"items": []}),
            patch.object(engine, "get_low_stock_items", return_value={"items": []}),
            patch("erpnext.operations_intelligence.engine.frappe.utils.today", return_value="2026-10-24"),
        ):
            result = engine.get_engine_snapshot()

        self.assertEqual(len(result["alerts"]), 1)
        self.assertEqual(result["alerts"][0]["key"], "no_current_alerts")
        self.assertEqual(result["alerts"][0]["count"], 0)
