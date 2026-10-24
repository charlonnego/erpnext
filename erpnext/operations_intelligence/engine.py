"""Deterministic operational insights derived from live ERPNext records.

This module intentionally contains no sample fixtures, model-generated numbers, or
write operations. It composes the permission-aware read APIs in metrics.py and
returns explainable alerts grounded in the current user's company records.
"""
from __future__ import annotations

import frappe
from frappe import _

from erpnext.operations_intelligence.working_capital import get_working_capital_snapshot

from erpnext.operations_intelligence.metrics import (
    get_action_items,
    get_low_stock_items,
    get_overview,
)


@frappe.whitelist()
def get_engine_snapshot(from_date: str | None = None, to_date: str | None = None) -> dict:
    """Build a read-only operational snapshot from real, permission-visible ERPNext data."""
    overview = get_overview(from_date=from_date, to_date=to_date)
    action_result = get_action_items(limit=25)
    stock_result = get_low_stock_items(limit=25)
    working_capital = get_working_capital_snapshot()

    metrics = overview["metrics"]
    alerts: list[dict] = []

    overdue_invoices = action_result.get("items", [])
    overdue_receivables = [
        row for row in overdue_invoices if row.get("kind") == "Receivable"
    ]
    overdue_payables = [
        row for row in overdue_invoices if row.get("kind") == "Payable"
    ]

    if overdue_receivables:
        amount = sum(float(row.get("outstanding_amount") or 0) for row in overdue_receivables)
        alerts.append({
            "key": "overdue_receivables",
            "severity": "high",
            "title": _("Overdue customer invoices need review"),
            "detail": _("Up to {0} overdue customer invoices are listed, totaling {1} in company currency.").format(
                len(overdue_receivables), frappe.utils.fmt_money(amount, currency=overview.get("currency"))
            ),
            "count": len(overdue_receivables),
            "amount": amount,
            "currency": overview.get("currency"),
            "source": "Sales Invoice",
        })

    if overdue_payables:
        amount = sum(float(row.get("outstanding_amount") or 0) for row in overdue_payables)
        alerts.append({
            "key": "overdue_payables",
            "severity": "medium",
            "title": _("Overdue supplier invoices need review"),
            "detail": _("Up to {0} overdue supplier invoices are listed, totaling {1} in company currency.").format(
                len(overdue_payables), frappe.utils.fmt_money(amount, currency=overview.get("currency"))
            ),
            "count": len(overdue_payables),
            "amount": amount,
            "currency": overview.get("currency"),
            "source": "Purchase Invoice",
        })

    low_stock = stock_result.get("items", [])
    if low_stock:
        alerts.append({
            "key": "low_stock",
            "severity": "high" if any(
                float(row.get("actual_qty") or 0) <= 0 for row in low_stock
            ) else "medium",
            "title": _("Stock is at or below configured reorder levels"),
            "detail": _("{0} visible item/warehouse combinations meet the configured reorder rule.").format(
                len(low_stock)
            ),
            "count": len(low_stock),
            "source": "Bin and Item reorder levels",
        })

    scheduled_net = float(working_capital.get("scheduled_net_due_30_days") or 0)
    overdue_supplier_90 = working_capital.get("payables", {}).get("overdue_over_90", {})
    overdue_customer_90 = working_capital.get("receivables", {}).get("overdue_over_90", {})
    if scheduled_net < 0:
        alerts.append({
            "key": "near_term_payment_pressure",
            "severity": "high",
            "title": _("Supplier invoices due in 30 days exceed customer invoices due"),
            "detail": _("Scheduled net due is {0} in the negative. Review expected collections, supplier terms and the actual bank position before making payment decisions.").format(
                frappe.utils.fmt_money(abs(scheduled_net), currency=overview.get("currency"))
            ),
            "amount": scheduled_net,
            "currency": overview.get("currency"),
            "source": "Submitted invoices due in the next 30 days",
        })
    if int(overdue_customer_90.get("invoice_count") or 0) or int(overdue_supplier_90.get("invoice_count") or 0):
        alerts.append({
            "key": "aged_debt_over_90_days",
            "severity": "high",
            "title": _("Invoice balances overdue by more than 90 days"),
            "detail": _("Customer invoices: {0}; supplier invoices: {1}. Review disputed balances, collection ownership and approved payment plans.").format(
                int(overdue_customer_90.get("invoice_count") or 0),
                int(overdue_supplier_90.get("invoice_count") or 0),
            ),
            "count": int(overdue_customer_90.get("invoice_count") or 0) + int(overdue_supplier_90.get("invoice_count") or 0),
            "source": "Submitted Sales and Purchase Invoices",
        })

    if not alerts:
        alerts.append({
            "key": "no_current_alerts",
            "severity": "info",
            "title": _("No current alerts from the enabled rules"),
            "detail": _("No overdue invoices or low-stock records were found in the records visible to your account. This is not a guarantee that every business risk has been detected."),
            "count": 0,
            "source": "Current read-only rules",
        })

    return {
        "engine": "joe_dave_operations_intelligence",
        "mode": "live_read_only",
        "company": overview["company"],
        "currency": overview.get("currency"),
        "period": {
            "from_date": overview["from_date"],
            "to_date": overview["to_date"],
        },
        "metrics": metrics,
        "alerts": alerts,
        "action_items": overdue_invoices,
        "low_stock_items": low_stock,
        "working_capital": working_capital,
        "as_of_date": frappe.utils.today(),
        "data_source": "ERPNext records visible to the current user",
        "write_operations_performed": False,
    }
