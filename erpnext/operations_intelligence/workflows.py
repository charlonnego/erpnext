"""Safe document workflows for Joe&dave Operations Intelligence.

Sales/purchase invoices and Payment Entries are created through standard ERPNext
forms. Inventory CSV imports are validated and saved as draft Stock Reconciliations;
this module never submits accounting or stock documents automatically.
"""
from __future__ import annotations

import json
import math

import frappe
from frappe import _
from frappe.utils import getdate, nowtime, today


MAX_IMPORT_ROWS = 2000


def _company() -> str:
    company = frappe.defaults.get_user_default("Company")
    if not company:
        frappe.throw(_("Set a default Company in your user defaults first."))
    return company


def _require_create(doctype: str) -> None:
    if not frappe.has_permission(doctype, ptype="create"):
        frappe.throw(_("You do not have permission to create {0}.").format(doctype), frappe.PermissionError)


def _parse_rows(rows) -> list[dict]:
    if isinstance(rows, str):
        try:
            rows = json.loads(rows)
        except (TypeError, ValueError):
            frappe.throw(_("Import rows must be valid JSON."))
    if not isinstance(rows, list) or not rows:
        frappe.throw(_("The import file has no inventory rows."))
    if len(rows) > MAX_IMPORT_ROWS:
        frappe.throw(_("Import is limited to {0} rows per batch. Split the file and import it in batches.").format(MAX_IMPORT_ROWS))
    normalized = []
    seen = set()
    for index, row in enumerate(rows, start=2):
        if not isinstance(row, dict):
            frappe.throw(_("Row {0} is not a valid record.").format(index))
        item_code = str(row.get("item_code") or "").strip()
        warehouse = str(row.get("warehouse") or "").strip()
        if not item_code or not warehouse:
            frappe.throw(_("Row {0}: item_code and warehouse are required.").format(index))
        key = (item_code, warehouse)
        if key in seen:
            frappe.throw(_("Row {0}: duplicate item_code and warehouse combination {1} / {2}.").format(index, item_code, warehouse))
        seen.add(key)
        if row.get("qty") in (None, ""):
            frappe.throw(_("Row {0}: qty is required.").format(index))
        try:
            qty = float(str(row.get("qty")).strip())
            valuation_rate = float(str(row.get("valuation_rate")).strip()) if row.get("valuation_rate") not in (None, "") else None
        except (TypeError, ValueError):
            frappe.throw(_("Row {0}: qty and valuation_rate must be numeric.").format(index))
        if not math.isfinite(qty) or (valuation_rate is not None and not math.isfinite(valuation_rate)):
            frappe.throw(_("Row {0}: qty and valuation_rate must be finite numbers.").format(index))
        if qty < 0:
            frappe.throw(_("Row {0}: qty cannot be negative for a physical stock count.").format(index))
        if valuation_rate is not None and valuation_rate < 0:
            frappe.throw(_("Row {0}: valuation_rate cannot be negative.").format(index))
        normalized.append({
            "row_number": index,
            "item_code": item_code,
            "warehouse": warehouse,
            "qty": qty,
            "valuation_rate": valuation_rate,
        })
    return normalized


@frappe.whitelist()
def preview_inventory_import(rows) -> dict:
    """Validate CSV-parsed inventory rows without writing any stock documents."""
    _require_create("Stock Reconciliation")
    company = _company()
    normalized = _parse_rows(rows)
    warehouse_names = {
        row.name for row in frappe.get_list(
            "Warehouse",
            filters={"company": company, "is_group": 0, "disabled": 0},
            fields=["name"],
            limit_page_length=5000,
        )
    }
    errors = []
    valid_rows = []
    for row in normalized:
        if row["warehouse"] not in warehouse_names:
            errors.append({
                "row": row["row_number"],
                "message": _("Warehouse {0} does not belong to your default company or is not an active leaf warehouse.").format(row["warehouse"]),
            })
            continue
        item_rows = frappe.get_list(
            "Item",
            filters={"name": row["item_code"], "disabled": 0, "is_stock_item": 1},
            fields=["name", "stock_uom", "has_serial_no", "has_batch_no"],
            limit_page_length=1,
        )
        if not item_rows:
            errors.append({
                "row": row["row_number"],
                "message": _("Item {0} is missing, disabled, non-stock, or not visible to you.").format(row["item_code"]),
            })
            continue
        if item_rows[0].get("has_serial_no") or item_rows[0].get("has_batch_no"):
            errors.append({
                "row": row["row_number"],
                "message": _("Item {0} uses serial or batch tracking. This CSV workflow currently accepts standard stock items only; import serial/batch details through the native ERPNext stock workflow.").format(row["item_code"]),
            })
            continue
        row["stock_uom"] = item_rows[0].get("stock_uom")
        valid_rows.append(row)
    return {
        "company": company,
        "row_count": len(normalized),
        "valid_count": len(valid_rows),
        "errors": errors,
        "valid_rows": valid_rows,
        "can_create_draft": bool(valid_rows) and not errors,
        "writes_performed": False,
        "note": _("Import creates a draft Stock Reconciliation only. Review the valuation and quantities, then submit through ERPNext when authorized."),
    }


@frappe.whitelist()
def create_inventory_reconciliation_draft(rows, posting_date=None, purpose="Stock Reconciliation") -> dict:
    """Create a draft Stock Reconciliation after repeating server-side validation."""
    _require_create("Stock Reconciliation")
    if purpose not in ("Opening Stock", "Stock Reconciliation"):
        frappe.throw(_("Purpose must be Opening Stock or Stock Reconciliation."))
    preview = preview_inventory_import(rows)
    if not preview["can_create_draft"]:
        frappe.throw(_("Resolve all inventory import errors before creating the reconciliation draft."))
    if purpose == "Opening Stock":
        missing_rates = [row["item_code"] for row in preview["valid_rows"] if row.get("valuation_rate") is None]
        if missing_rates:
            frappe.throw(_("Opening Stock requires a valuation_rate for every row. Missing rate for: {0}").format(", ".join(missing_rates[:20])))
    company = preview["company"]
    posting_date = getdate(posting_date or today())
    doc = frappe.new_doc("Stock Reconciliation")
    doc.company = company
    doc.purpose = purpose
    doc.posting_date = posting_date
    doc.posting_time = nowtime()
    for row in preview["valid_rows"]:
        child = {
            "item_code": row["item_code"],
            "warehouse": row["warehouse"],
            "qty": row["qty"],
        }
        if row.get("valuation_rate") is not None:
            child["valuation_rate"] = row["valuation_rate"]
        doc.append("items", child)
    doc.insert()
    return {
        "name": doc.name,
        "doctype": doc.doctype,
        "docstatus": doc.docstatus,
        "company": company,
        "purpose": purpose,
        "row_count": len(doc.items),
        "posting_date": str(doc.posting_date),
        "submitted": False,
        "message": _("Draft Stock Reconciliation {0} created. Review it before submitting.").format(doc.name),
    }
