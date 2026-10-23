"""Tests for safe inventory import and document workflow safeguards."""
from unittest.mock import patch

import frappe
from frappe.tests.utils import FrappeTestCase

from erpnext.operations_intelligence import workflows


class TestOperationsIntelligenceWorkflows(FrappeTestCase):
    def test_parse_inventory_rows_normalizes_optional_valuation(self):
        rows = workflows._parse_rows([
            {"item_code": "ITEM-001", "warehouse": "Main - EX", "qty": "12.5", "valuation_rate": ""},
        ])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["qty"], 12.5)
        self.assertIsNone(rows[0]["valuation_rate"])

    def test_parse_inventory_rows_requires_quantity(self):
        with self.assertRaises(frappe.ValidationError):
            workflows._parse_rows([
                {"item_code": "ITEM-001", "warehouse": "Main - EX", "qty": ""},
            ])

    def test_parse_inventory_rows_rejects_duplicate_item_warehouse(self):
        row = {"item_code": "ITEM-001", "warehouse": "Main - EX", "qty": "3"}
        with self.assertRaises(frappe.ValidationError):
            workflows._parse_rows([row, row])

    def test_parse_inventory_rows_rejects_negative_quantity(self):
        with self.assertRaises(frappe.ValidationError):
            workflows._parse_rows([
                {"item_code": "ITEM-001", "warehouse": "Main - EX", "qty": "-1"},
            ])

    def test_preview_rejects_warehouse_outside_default_company(self):
        rows = [{"item_code": "ITEM-001", "warehouse": "Other Co - EX", "qty": "3"}]
        with (
            patch("erpnext.operations_intelligence.workflows.frappe.has_permission", return_value=True),
            patch("erpnext.operations_intelligence.workflows.frappe.defaults.get_user_default", return_value="Example Co"),
            patch("erpnext.operations_intelligence.workflows.frappe.get_list", return_value=[]),
        ):
            result = workflows.preview_inventory_import(rows)
        self.assertFalse(result["can_create_draft"])
        self.assertEqual(result["valid_count"], 0)
        self.assertEqual(len(result["errors"]), 1)
        self.assertFalse(result["writes_performed"])
