"""Working-capital visibility built from submitted ERPNext invoices.

This is an operational schedule, not a bank balance or cash-flow forecast.
All aggregates are permission-aware and use the company's base currency.
"""
from __future__ import annotations

import frappe
from frappe import _
from frappe.utils import add_days, getdate, today


def _company():
    company = frappe.defaults.get_user_default("Company")
    if not company:
        frappe.throw(_("Set a default Company in your user defaults to view Operations Intelligence."))
    return company


def _aggregate(doctype: str, company: str, start_date: str | None = None, end_date: str | None = None) -> dict:
    filters = {
        "company": company,
        "docstatus": 1,
        "outstanding_amount": [">", 0],
    }
    if start_date and end_date:
        filters["due_date"] = ["between", [start_date, end_date]]
    elif start_date:
        filters["due_date"] = [">=", start_date]
    elif end_date:
        filters["due_date"] = ["<=", end_date]
    rows = frappe.get_list(
        doctype,
        filters=filters,
        fields=["sum(base_outstanding_amount) as amount", "count(name) as invoice_count"],
    )
    row = rows[0] if rows else {}
    return {
        "amount": float(row.get("amount") or 0),
        "invoice_count": int(row.get("invoice_count") or 0),
    }


@frappe.whitelist()
def get_working_capital_snapshot() -> dict:
    """Summarise overdue exposure and invoices falling due within 30 days.

    The function is read-only. It deliberately does not infer bank balances,
    payment probability, profit, or available cash from invoice records.
    """
    company = _company()
    as_of = getdate(today())
    d1 = str(add_days(as_of, -1))
    d30 = str(add_days(as_of, -30))
    d60 = str(add_days(as_of, -60))
    d90 = str(add_days(as_of, -90))
    today_str = str(as_of)
    day7 = str(add_days(as_of, 7))
    day30 = str(add_days(as_of, 30))

    result = {"company": company, "as_of_date": today_str, "currency": frappe.get_cached_value("Company", company, "default_currency")}
    for doctype, key in (("Sales Invoice", "receivables"), ("Purchase Invoice", "payables")):
        result[key] = {
            "total_open": _aggregate(doctype, company),
            "overdue_1_30": _aggregate(doctype, company, d30, d1),
            "overdue_31_60": _aggregate(doctype, company, d60, str(add_days(as_of, -31))),
            "overdue_61_90": _aggregate(doctype, company, d90, str(add_days(as_of, -61))),
            "overdue_over_90": _aggregate(doctype, company, end_date=str(add_days(as_of, -91))),
            "due_today_to_7": _aggregate(doctype, company, today_str, day7),
            "due_8_to_30": _aggregate(doctype, company, str(add_days(as_of, 8)), day30),
        }

    result["scheduled_net_due_30_days"] = (
        result["receivables"]["due_today_to_7"]["amount"]
        + result["receivables"]["due_8_to_30"]["amount"]
        - result["payables"]["due_today_to_7"]["amount"]
        - result["payables"]["due_8_to_30"]["amount"]
    )
    result["interpretation"] = (
        "Scheduled net due is receivable invoices minus payable invoices with due dates in the next 30 days. "
        "It is not a cash balance or a cash-flow forecast; actual payment timing and bank balances may differ."
    )
    return result
