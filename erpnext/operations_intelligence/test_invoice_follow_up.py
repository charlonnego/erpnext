"""Tests for invoice follow-up task creation and safety checks."""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import frappe
from frappe.tests.utils import FrappeTestCase

from erpnext.operations_intelligence.workflows import create_invoice_follow_up


class TestInvoiceFollowUp(FrappeTestCase):
    def test_creates_task_linked_to_invoice_and_assigned_to_current_user(self):
        invoice = MagicMock()
        invoice.company = "Example Co"
        invoice.docstatus = 1
        invoice.get.return_value = 125.0
        task = SimpleNamespace(name="TODO-0001", insert=MagicMock())
        with (
            patch("erpnext.operations_intelligence.workflows._company", return_value="Example Co"),
            patch("erpnext.operations_intelligence.workflows._require_create") as require_create,
            patch("erpnext.operations_intelligence.workflows.getdate", side_effect=lambda value: value),
            patch("erpnext.operations_intelligence.workflows.today", return_value="2026-10-24"),
            patch("erpnext.operations_intelligence.workflows.frappe.get_doc", return_value=invoice),
            patch("erpnext.operations_intelligence.workflows.frappe.new_doc", return_value=task),
            patch("erpnext.operations_intelligence.workflows.frappe.session.user", "staff@example.com"),
        ):
            result = create_invoice_follow_up(
                "Sales Invoice",
                "SINV-0001",
                "Call customer about payment date",
                "2026-10-26",
            )

        require_create.assert_called_once_with("ToDo")
        invoice.check_permission.assert_called_once_with("read")
        self.assertEqual(task.allocated_to, "staff@example.com")
        self.assertEqual(task.reference_type, "Sales Invoice")
        self.assertEqual(task.reference_name, "SINV-0001")
        self.assertEqual(task.status, "Open")
        self.assertEqual(task.priority, "Medium")
        self.assertEqual(result["name"], "TODO-0001")
        self.assertEqual(result["allocated_to"], "staff@example.com")
        task.insert.assert_called_once_with()

    def test_rejects_unsupported_reference_doctype(self):
        with self.assertRaises(frappe.ValidationError):
            create_invoice_follow_up("User", "Administrator", "Follow up")

    def test_rejects_empty_description(self):
        with (
            patch("erpnext.operations_intelligence.workflows._company", return_value="Example Co"),
            patch("erpnext.operations_intelligence.workflows._require_create"),
        ):
            with self.assertRaises(frappe.ValidationError):
                create_invoice_follow_up("Sales Invoice", "SINV-0001", "   ")

    def test_rejects_invoice_from_another_company(self):
        invoice = MagicMock()
        invoice.company = "Other Co"
        invoice.docstatus = 1
        invoice.get.return_value = 125.0
        with (
            patch("erpnext.operations_intelligence.workflows._company", return_value="Example Co"),
            patch("erpnext.operations_intelligence.workflows._require_create"),
            patch("erpnext.operations_intelligence.workflows.getdate", side_effect=lambda value: value),
            patch("erpnext.operations_intelligence.workflows.today", return_value="2026-10-24"),
            patch("erpnext.operations_intelligence.workflows.frappe.get_doc", return_value=invoice),
            patch("erpnext.operations_intelligence.workflows.frappe.new_doc") as new_doc,
        ):
            with self.assertRaises(frappe.PermissionError):
                create_invoice_follow_up(
                    "Sales Invoice",
                    "SINV-OTHER",
                    "Call customer",
                    "2026-10-26",
                )
        new_doc.assert_not_called()
