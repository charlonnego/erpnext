"""Unit tests for Operations Intelligence KPI helpers."""

from unittest.mock import patch

import frappe
from frappe.tests.utils import FrappeTestCase

from erpnext.operations_intelligence.metrics import _sum_for_company, _validated_period


class TestOperationsIntelligenceMetrics(FrappeTestCase):
	def test_validated_period_uses_month_start_by_default(self):
		start_date, end_date = _validated_period(None, "2026-10-23")
		self.assertEqual(start_date, "2026-10-01")
		self.assertEqual(end_date, "2026-10-23")

	def test_validated_period_rejects_reversed_dates(self):
		with self.assertRaises(frappe.ValidationError):
			_validated_period("2026-10-24", "2026-10-23")

	def test_sum_uses_submitted_documents_and_date_range(self):
		with patch("erpnext.operations_intelligence.metrics.frappe.get_list", return_value=[{"total": 1250}]) as get_list:
			total = _sum_for_company(
				"Sales Invoice", "Example Co", "posting_date", "2026-10-01", "2026-10-23", "base_grand_total"
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
				"Sales Invoice", "Example Co", "posting_date", "2026-10-01", "2026-10-23", "base_grand_total"
			)
		self.assertEqual(total, 0.0)
