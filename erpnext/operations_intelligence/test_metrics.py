"""Unit tests for Operations Intelligence KPI helpers."""

from types import SimpleNamespace
from unittest.mock import patch

import frappe
from frappe.tests.utils import FrappeTestCase

from erpnext.operations_intelligence.metrics import (
	_sum_for_company,
	_validated_period,
	get_overview,
	get_action_items,
	get_low_stock_items,
)


class TestOperationsIntelligenceMetrics(FrappeTestCase):
	def test_validated_period_uses_month_start_by_default(self):
		start_date, end_date = _validated_period(None, "2026-10-23")
		self.assertEqual(start_date, "2026-10-01")
		self.assertEqual(end_date, "2026-10-23")

	def test_validated_period_rejects_reversed_dates(self):
		with self.assertRaises(frappe.ValidationError):
			_validated_period("2026-10-24", "2026-10-23")

	def test_sum_uses_submitted_documents_and_date_range(self):
		with patch(
			"erpnext.operations_intelligence.metrics.frappe.get_list",
			return_value=[{"total": 1250}],
		) as get_list:
			total = _sum_for_company(
				"Sales Invoice",
				"Example Co",
				"posting_date",
				"2026-10-01",
				"2026-10-23",
				"base_grand_total",
			)

		self.assertEqual(total, 1250.0)
		get_list.assert_called_once_with(
			"Sales Invoice",
			filters={
				"company": "Example Co",
				"docstatus": 1,
				"posting_date": ["between", ["2026-10-01", "2026-10-23"]],
			},
			fields=["sum(base_grand_total) as total"],
		)

	def test_sum_returns_zero_for_empty_result(self):
		with patch("erpnext.operations_intelligence.metrics.frappe.get_list", return_value=[]):
			total = _sum_for_company(
				"Sales Invoice",
				"Example Co",
				"posting_date",
				"2026-10-01",
				"2026-10-23",
				"base_grand_total",
			)
		self.assertEqual(total, 0.0)

	def test_overview_returns_metrics_and_definitions(self):
		list_results = [
			[{"total": 1250}],
			[{"total": 500}],
			[{"total": 250}],
			[{"total": 75}],
			[{"total": 2}],
		]
		with (
			patch("erpnext.operations_intelligence.metrics.frappe.defaults.get_user_default", return_value="Example Co"),
			patch("erpnext.operations_intelligence.metrics.frappe.get_list", side_effect=list_results) as get_list,
			patch("erpnext.operations_intelligence.metrics.frappe.get_cached_value", return_value="NGN"),
			patch("erpnext.operations_intelligence.metrics.today", return_value="2026-10-23"),
		):
			result = get_overview("2026-10-01", "2026-10-23")

		self.assertEqual(result["company"], "Example Co")
		self.assertEqual(result["currency"], "NGN")
		self.assertEqual(result["from_date"], "2026-10-01")
		self.assertEqual(result["to_date"], "2026-10-23")
		self.assertEqual(
			result["metrics"],
			{
				"sales_value": 1250.0,
				"purchase_value": 500.0,
				"outstanding_receivables": 250.0,
				"outstanding_payables": 75.0,
				"overdue_sales_invoice_count": 2,
			},
		)
		self.assertIn("sales_value", result["definitions"])
		self.assertEqual(get_list.call_count, 5)

	def test_overview_requires_default_company(self):
		with (
			patch("erpnext.operations_intelligence.metrics.frappe.defaults.get_user_default", return_value=None),
			patch("erpnext.operations_intelligence.metrics.frappe.get_list") as get_list,
		):
			with self.assertRaises(frappe.ValidationError):
				get_overview("2026-10-01", "2026-10-23")

		get_list.assert_not_called()


	def test_action_items_returns_overdue_records_in_due_date_order(self):
		sales = [
			{"name": "SINV-002", "customer": "Customer B", "due_date": "2026-10-10", "base_outstanding_amount": 100},
		]
		purchases = [
			{"name": "PINV-001", "supplier": "Supplier A", "due_date": "2026-10-05", "base_outstanding_amount": 50},
		]
		with (
			patch("erpnext.operations_intelligence.metrics.frappe.defaults.get_user_default", return_value="Example Co"),
			patch("erpnext.operations_intelligence.metrics.frappe.get_list", side_effect=[sales, purchases]) as get_list,
			patch("erpnext.operations_intelligence.metrics.frappe.get_cached_value", return_value="NGN"),
			patch("erpnext.operations_intelligence.metrics.today", return_value="2026-10-23"),
		):
			result = get_action_items("10")

		self.assertEqual(result["company"], "Example Co")
		self.assertEqual(result["currency"], "NGN")
		self.assertEqual([item["name"] for item in result["items"]], ["PINV-001", "SINV-002"])
		self.assertEqual(result["items"][0]["kind"], "Payable")
		self.assertEqual(result["items"][1]["outstanding_amount"], 100.0)
		self.assertGreater(result["items"][0]["days_overdue"], result["items"][1]["days_overdue"])
		self.assertIn("supplier", result["items"][0]["recommended_next_step"].lower())
		self.assertEqual(get_list.call_count, 2)
		self.assertEqual(get_list.call_args_list[0].kwargs["limit_page_length"], 10)

	def test_action_items_caps_limit_and_handles_invalid_limit(self):
		with (
			patch("erpnext.operations_intelligence.metrics.frappe.defaults.get_user_default", return_value="Example Co"),
			patch("erpnext.operations_intelligence.metrics.frappe.get_list", return_value=[]) as get_list,
			patch("erpnext.operations_intelligence.metrics.frappe.get_cached_value", return_value="NGN"),
			patch("erpnext.operations_intelligence.metrics.today", return_value="2026-10-23"),
		):
			result = get_action_items("not-a-number")

		self.assertEqual(result["items"], [])
		self.assertEqual(get_list.call_args_list[0].kwargs["limit_page_length"], 10)
		self.assertEqual(get_list.call_args_list[1].kwargs["limit_page_length"], 10)


	def test_low_stock_items_flags_bin_at_configured_reorder_level(self):
		bin_rows = [
			{"item_code": "ITEM-001", "warehouse": "Main - EX", "actual_qty": 3, "projected_qty": 2, "stock_uom": "Nos"},
		]
		item_doc = SimpleNamespace(
			item_name="Sample Item",
			stock_uom="Nos",
			get=lambda field, default=None: [
				SimpleNamespace(warehouse="Main - EX", warehouse_reorder_level=5, warehouse_reorder_qty=10)
			] if field == "reorder_levels" else default,
		)
		with (
			patch("erpnext.operations_intelligence.metrics.frappe.defaults.get_user_default", return_value="Example Co"),
			patch("erpnext.operations_intelligence.metrics.frappe.get_list", side_effect=[
				[{"name": "Main - EX"}],
				bin_rows,
				[{"name": "ITEM-001"}],
			]) as get_list,
			patch("erpnext.operations_intelligence.metrics.frappe.get_doc", return_value=item_doc),
			patch("erpnext.operations_intelligence.metrics.today", return_value="2026-10-24"),
		):
			result = get_low_stock_items(10)

		self.assertEqual(result["company"], "Example Co")
		self.assertEqual(len(result["items"]), 1)
		self.assertEqual(result["items"][0]["item_code"], "ITEM-001")
		self.assertEqual(result["items"][0]["reorder_level"], 5.0)
		self.assertEqual(result["items"][0]["actual_qty"], 3.0)
		self.assertEqual(get_list.call_count, 3)

	def test_low_stock_items_skips_items_without_reorder_level(self):
		bin_rows = [
			{"item_code": "ITEM-002", "warehouse": "Main - EX", "actual_qty": 0, "projected_qty": 0, "stock_uom": "Nos"},
		]
		item_doc = SimpleNamespace(
			item_name="No Reorder Item",
			stock_uom="Nos",
			get=lambda field, default=None: [] if field == "reorder_levels" else default,
		)
		with (
			patch("erpnext.operations_intelligence.metrics.frappe.defaults.get_user_default", return_value="Example Co"),
			patch("erpnext.operations_intelligence.metrics.frappe.get_list", side_effect=[
				[{"name": "Main - EX"}],
				bin_rows,
				[{"name": "ITEM-002"}],
			]),
			patch("erpnext.operations_intelligence.metrics.frappe.get_doc", return_value=item_doc),
			patch("erpnext.operations_intelligence.metrics.today", return_value="2026-10-24"),
		):
			result = get_low_stock_items()

		self.assertEqual(result["items"], [])
