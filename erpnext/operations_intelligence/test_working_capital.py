"""Tests for the permission-aware working-capital summary."""
from unittest.mock import patch

import frappe
from frappe.tests.utils import FrappeTestCase

from erpnext.operations_intelligence.working_capital import _aggregate, get_working_capital_snapshot


class TestWorkingCapital(FrappeTestCase):
    def test_aggregate_uses_submitted_open_invoices_and_base_currency(self):
        with patch(
            "erpnext.operations_intelligence.working_capital.frappe.get_list",
            return_value=[{"amount": 250.5, "invoice_count": 3}],
        ) as get_list:
            result = _aggregate("Sales Invoice", "Example Co", "2026-10-01", "2026-10-31")
        self.assertEqual(result, {"amount": 250.5, "invoice_count": 3})
        self.assertEqual(get_list.call_args.kwargs["filters"], {
            "company": "Example Co",
            "docstatus": 1,
            "outstanding_amount": [">", 0],
            "due_date": ["between", ["2026-10-01", "2026-10-31"]],
        })
        self.assertIn("sum(base_outstanding_amount) as amount", get_list.call_args.kwargs["fields"])

    def test_aggregate_empty_result_is_zero(self):
        with patch("erpnext.operations_intelligence.working_capital.frappe.get_list", return_value=[]):
            self.assertEqual(_aggregate("Purchase Invoice", "Example Co"), {"amount": 0.0, "invoice_count": 0})

    def test_snapshot_explains_that_schedule_is_not_cash_forecast(self):
        with (
            patch("erpnext.operations_intelligence.working_capital.frappe.defaults.get_user_default", return_value="Example Co"),
            patch("erpnext.operations_intelligence.working_capital.frappe.get_cached_value", return_value="NGN"),
            patch("erpnext.operations_intelligence.working_capital.frappe.utils.today", return_value="2026-10-24"),
            patch("erpnext.operations_intelligence.working_capital.today", return_value="2026-10-24"),
            patch("erpnext.operations_intelligence.working_capital.frappe.get_list", return_value=[{"amount": 100, "invoice_count": 1}]),
        ):
            result = get_working_capital_snapshot()
        self.assertEqual(result["currency"], "NGN")
        self.assertEqual(result["scheduled_net_due_30_days"], 0)
        self.assertIn("not a cash balance", result["interpretation"])
