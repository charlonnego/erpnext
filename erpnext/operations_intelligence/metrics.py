"""Permission-aware KPI aggregation for Operations Intelligence."""

from __future__ import annotations

import frappe
from frappe import _
from frappe.utils import getdate, get_first_day, today


def _validated_period(from_date: str | None, to_date: str | None) -> tuple[str, str]:
	"""Resolve and validate the requested reporting period."""
	end_date = getdate(to_date or today())
	start_date = getdate(from_date or get_first_day(end_date))
	if start_date > end_date:
		frappe.throw(_("From Date cannot be after To Date."))
	return str(start_date), str(end_date)


def _sum_for_company(doctype: str, company: str, date_field: str, start_date: str, end_date: str, amount_field: str) -> float:
	"""Aggregate a submitted document using permission-aware get_list."""
	result = frappe.get_list(
		doctype,
		filters={
			"company": company,
			"docstatus": 1,
			date_field: ["between", [start_date, end_date]],
		},
		fields=[f"sum({amount_field}) as total"],
	)
	return float((result[0].get("total") if result else 0) or 0)


@frappe.whitelist()
def get_overview(from_date: str | None = None, to_date: str | None = None) -> dict:
	"""Return first-release operating KPIs for the current user's default company.

	All values are summaries of submitted ERPNext documents. This endpoint is
	read-only; it never creates or modifies accounting records.
	"""
	start_date, end_date = _validated_period(from_date, to_date)
	company = frappe.defaults.get_user_default("Company")
	if not company:
		frappe.throw(_("Set a default Company in your user defaults to view Operations Intelligence."))

	# get_list is intentional: it applies Frappe's document-level permissions.
	sales_value = _sum_for_company(
		"Sales Invoice", company, "posting_date", start_date, end_date, "base_grand_total"
	)
	purchase_value = _sum_for_company(
		"Purchase Invoice", company, "posting_date", start_date, end_date, "base_grand_total"
	)

	receivables = frappe.get_list(
		"Sales Invoice",
		filters={"company": company, "docstatus": 1, "outstanding_amount": [">", 0]},
		fields=["sum(outstanding_amount) as total"],
	)
	payables = frappe.get_list(
		"Purchase Invoice",
		filters={"company": company, "docstatus": 1, "outstanding_amount": [">", 0]},
		fields=["sum(outstanding_amount) as total"],
	)
	overdue = frappe.get_list(
		"Sales Invoice",
		filters={
			"company": company,
			"docstatus": 1,
			"outstanding_amount": [">", 0],
			"due_date": ["<", today()],
		},
		fields=["count(name) as total"],
	)

	return {
		"company": company,
		"from_date": start_date,
		"to_date": end_date,
		"currency": frappe.get_cached_value("Company", company, "default_currency"),
		"metrics": {
			"sales_value": sales_value,
			"purchase_value": purchase_value,
			"outstanding_receivables": float((receivables[0].get("total") if receivables else 0) or 0),
			"outstanding_payables": float((payables[0].get("total") if payables else 0) or 0),
			"overdue_sales_invoice_count": int((overdue[0].get("total") if overdue else 0) or 0),
		},
		"definitions": {
			"sales_value": "Sum of base grand total for submitted Sales Invoices posted within the selected period.",
			"purchase_value": "Sum of base grand total for submitted Purchase Invoices posted within the selected period.",
			"outstanding_receivables": "Current outstanding amount across submitted Sales Invoices visible to the user.",
			"outstanding_payables": "Current outstanding amount across submitted Purchase Invoices visible to the user.",
			"overdue_sales_invoice_count": "Count of submitted Sales Invoices with a positive outstanding amount and a due date before today.",
		},
	}


@frappe.whitelist()
def get_action_items(limit: int = 10) -> dict:
	"""Return a small, read-only list of overdue invoices for follow-up.

	The underlying get_list calls enforce the current user's document permissions.
	Amounts use company/base currency so sales and purchase items are comparable.
	"""
	company = frappe.defaults.get_user_default("Company")
	if not company:
		frappe.throw(_("Set a default Company in your user defaults to view Operations Intelligence."))

	try:
		limit = max(1, min(int(limit), 25))
	except (TypeError, ValueError):
		limit = 10

	today_date = today()
	items = []
	for doctype, party_field, kind in (
		("Sales Invoice", "customer", "Receivable"),
		("Purchase Invoice", "supplier", "Payable"),
	):
		rows = frappe.get_list(
			doctype,
			filters={
				"company": company,
				"docstatus": 1,
				"outstanding_amount": [">", 0],
				"due_date": ["<", today_date],
			},
			fields=["name", party_field, "due_date", "base_outstanding_amount"],
			order_by="due_date asc",
			limit_page_length=limit,
		)
		for row in rows:
			items.append({
				"doctype": doctype,
				"name": row.get("name"),
				"party": row.get(party_field),
				"due_date": str(row.get("due_date")) if row.get("due_date") else "",
				"outstanding_amount": float(row.get("base_outstanding_amount") or 0),
				"kind": kind,
			})

	items.sort(key=lambda item: item["due_date"] or "9999-12-31")
	return {
		"company": company,
		"currency": frappe.get_cached_value("Company", company, "default_currency"),
		"items": items[:limit],
		"as_of_date": today_date,
	}

@frappe.whitelist()
def get_low_stock_items(limit: int = 10) -> dict:
	"""Return stock bins at/below configured Item reorder levels.

	Only stock bins and Items visible to the current user are considered. This
	is an advisory signal, not a reservation or replenishment calculation.
	"""
	company = frappe.defaults.get_user_default("Company")
	if not company:
		frappe.throw(_("Set a default Company in your user defaults to view Operations Intelligence."))

	try:
		limit = max(1, min(int(limit), 25))
	except (TypeError, ValueError):
		limit = 10

	# Bin is keyed by item and warehouse; company is owned by Warehouse,
	# not consistently available as a Bin field across supported ERPNext versions.
	warehouses = frappe.get_list(
		"Warehouse",
		filters={"company": company, "is_group": 0},
		fields=["name"],
		limit_page_length=5000,
	)
	warehouse_names = [row.get("name") for row in warehouses if row.get("name")]
	if not warehouse_names:
		return {"company": company, "items": [], "as_of_date": today()}

	bins = frappe.get_list(
		"Bin",
		filters={"warehouse": ["in", warehouse_names]},
		fields=["item_code", "warehouse", "actual_qty", "projected_qty", "stock_uom"],
		order_by="actual_qty asc",
		limit_page_length=500,
	)
	items_by_code = {}
	low_stock = []
	for bin_row in bins:
		item_code = bin_row.get("item_code")
		warehouse = bin_row.get("warehouse")
		if not item_code or not warehouse:
			continue
		if item_code not in items_by_code:
			if not frappe.get_list(
				"Item",
				filters={"name": item_code, "disabled": 0, "is_stock_item": 1},
				fields=["name"],
				limit_page_length=1,
			):
				items_by_code[item_code] = None
				continue
			item_doc = frappe.get_doc("Item", item_code)
			items_by_code[item_code] = {
				"name": item_doc.item_name,
				"stock_uom": item_doc.stock_uom,
				"reorder_levels": {
					row.warehouse: {
						"level": float(row.warehouse_reorder_level or 0),
						"qty": float(row.warehouse_reorder_qty or 0),
					}
					for row in item_doc.get("reorder_levels", [])
					if row.warehouse
				},
				"disabled": False,
			}
		item_info = items_by_code[item_code]
		if not item_info:
			continue
		reorder = item_info["reorder_levels"].get(warehouse)
		if not reorder:
			continue
		actual_qty = float(bin_row.get("actual_qty") or 0)
		if actual_qty <= reorder["level"]:
			low_stock.append({
				"item_code": item_code,
				"item_name": item_info["name"],
				"warehouse": warehouse,
				"actual_qty": actual_qty,
				"projected_qty": float(bin_row.get("projected_qty") or 0),
				"reorder_level": reorder["level"],
				"reorder_qty": reorder["qty"],
				"stock_uom": bin_row.get("stock_uom") or item_info["stock_uom"],
			})
	low_stock.sort(key=lambda item: (item["actual_qty"] - item["reorder_level"], item["item_code"], item["warehouse"]))
	return {"company": company, "items": low_stock[:limit], "as_of_date": today()}

