frappe.pages["operations-intelligence"].on_page_load = function (wrapper) {
	const page = frappe.ui.make_app_page({
		parent: wrapper,
		title: __("Joe&dave Operations Intelligence"),
		single_column: true,
	});

	page.body = $(`<div class="operations-intelligence-page">
		<div class="oi-intro">
			<div>
				<h3>${__("Business at a glance")}</h3>
				<p class="text-muted">${__("A read-only overview of submitted accounting records visible to your account.")}</p>
			</div>
		</div>
		<div class="oi-status text-muted small mb-3" role="status" aria-live="polite"></div>
		<div class="oi-kpi-grid"></div>
		<section class="oi-actions">
			<div class="oi-actions-heading">
				<h4>${__("Action centre")}</h4>
				<p class="text-muted small">${__("Overdue invoices that may need follow-up. Only records visible to your account are shown.")}</p>
			</div>
			<div class="oi-action-list"></div>
		</section>
		<section class="oi-actions oi-engine-section">
			<div class="oi-actions-heading">
				<h4>${__("Engine findings")}</h4>
				<p class="text-muted small">${__("Deterministic alerts calculated from live ERPNext records visible to your account. No sample values or automatic accounting changes.")}</p>
			</div>
			<div class="oi-engine-list"></div>
		</section>
		<section class="oi-actions oi-stock-section">
			<div class="oi-actions-heading">
				<h4>${__("Inventory signals")}</h4>
				<p class="text-muted small">${__("Stock at or below the item's configured reorder level, by warehouse. Initial scan is limited to 500 visible stock-bin records.")}</p>
			</div>
			<div class="oi-stock-list"></div>
		</section>
		<div class="oi-definitions text-muted small"></div>
	</div>`).appendTo(page.main);

	page.from_date = page.add_field({
		fieldname: "from_date",
		label: __("From Date"),
		fieldtype: "Date",
		default: frappe.datetime.month_start(),
		change: () => load_overview(),
	});
	page.to_date = page.add_field({
		fieldname: "to_date",
		label: __("To Date"),
		fieldtype: "Date",
		default: frappe.datetime.get_today(),
		change: () => load_overview(),
	});
	page.set_primary_action(__("Refresh"), refresh_dashboard, "refresh");
	page.add_inner_button(__("Sales Invoice"), () => {
		frappe.new_doc("Sales Invoice", { company: frappe.defaults.get_user_default("Company") });
	}, __("Create"));
	page.add_inner_button(__("Purchase Invoice"), () => {
		frappe.new_doc("Purchase Invoice", { company: frappe.defaults.get_user_default("Company") });
	}, __("Create"));
	page.add_inner_button(__("Customer Receipt"), () => {
		frappe.new_doc("Payment Entry", {
			company: frappe.defaults.get_user_default("Company"),
			payment_type: "Receive",
		});
	}, __("Create"));
	page.add_inner_button(__("Supplier Payment"), () => {
		frappe.new_doc("Payment Entry", {
			company: frappe.defaults.get_user_default("Company"),
			payment_type: "Pay",
		});
	}, __("Create"));
	page.add_inner_button(__("Import Inventory CSV"), open_inventory_import, __("Inventory"));

	function parse_inventory_csv(text) {
		const records = [];
		let row = [], field = "", quoted = false;
		for (let i = 0; i < text.length; i++) {
			const char = text[i];
			if (char === '"' && quoted && text[i + 1] === '"') {
				field += '"'; i++;
			} else if (char === '"') {
				quoted = !quoted;
			} else if (char === "," && !quoted) {
				row.push(field); field = "";
			} else if ((char === "\\n" || char === "\\r") && !quoted) {
				if (char === "\\r" && text[i + 1] === "\\n") i++;
				row.push(field); field = "";
				if (row.some((value) => String(value).trim() !== "")) records.push(row);
				row = [];
			} else {
				field += char;
			}
		}
		if (quoted) throw new Error(__("CSV contains an unclosed quoted field."));
		row.push(field);
		if (row.some((value) => String(value).trim() !== "")) records.push(row);
		if (records.length < 2) throw new Error(__("CSV must contain a header and at least one inventory row."));
		const headers = records.shift().map((value) => String(value).trim().toLowerCase());
		const required = ["item_code", "warehouse", "qty"];
		const missing = required.filter((name) => !headers.includes(name));
		if (missing.length) throw new Error(__("Missing required columns: {0}").format(missing.join(", ")));
		return records.map((values) => {
			const record = {};
			headers.forEach((header, index) => { record[header] = String(values[index] ?? "").trim(); });
			return {
				item_code: record.item_code,
				warehouse: record.warehouse,
				qty: record.qty,
				valuation_rate: record.valuation_rate || null,
			};
		});
	}

	function open_inventory_import() {
		let parsed_rows = null;
		let validated = false;
		const dialog = new frappe.ui.Dialog({
			title: __("Import Existing Inventory"),
			 size: "large",
			fields: [{
				fieldtype: "HTML",
				fieldname: "inventory_upload",
			}],
			primary_action_label: __("Validate CSV"),
			primary_action: () => {
				if (!validated) {
					const file = dialog.$wrapper.find("input[name='inventory_csv']")[0]?.files?.[0];
					if (!file) {
						frappe.msgprint(__("Choose an inventory CSV file first."));
						return;
					}
					const reader = new FileReader();
					reader.onload = () => {
						try {
							parsed_rows = parse_inventory_csv(String(reader.result || ""));
						} catch (error) {
							dialog.$wrapper.find(".oi-import-results").text(error.message);
							return;
						}
						dialog.$wrapper.find(".oi-import-results").text(__("Validating {0} rows against your company items and warehouses…").format(parsed_rows.length));
							frappe.call({
								method: "erpnext.operations_intelligence.workflows.preview_inventory_import",
								args: { rows: JSON.stringify(parsed_rows) },
							}).then((response) => {
								const result = response.message;
								if (!result) throw new Error(__("The server returned no validation result."));
								if (result.errors?.length) {
									const messages = result.errors.map((error) => __("Row {0}: {1}").format(error.row, error.message));
									dialog.$wrapper.find(".oi-import-results").text(messages.join("\\n"));
									validated = false;
									return;
								}
								if (!result.can_create_draft) {
									dialog.$wrapper.find(".oi-import-results").text(__("No valid rows to import."));
									return;
								}
								validated = true;
								dialog.$wrapper.find(".oi-import-results").text(__("{0} rows validated for {1}. No stock records have been changed. Click Create Draft to prepare a Stock Reconciliation for review.").format(result.valid_count, result.company));
								dialog.set_primary_action(__("Create Draft"), () => {
									frappe.call({
										method: "erpnext.operations_intelligence.workflows.create_inventory_reconciliation_draft",
										args: { rows: JSON.stringify(parsed_rows) },
										freeze: true,
										freeze_message: __("Creating draft Stock Reconciliation…"),
									}).then((created_response) => {
										const created = created_response.message;
										dialog.hide();
										frappe.show_alert({ message: created.message, indicator: "green" });
										frappe.set_route("Form", "Stock Reconciliation", created.name);
									});
								});
							}).catch((error) => {
								dialog.$wrapper.find(".oi-import-results").text(error.message || __("Validation failed. No changes were made."));
							});
					};
					reader.onerror = () => dialog.$wrapper.find(".oi-import-results").text(__("Could not read the selected CSV file."));
					reader.readAsText(file);
					return;
				}
			},
		});
		dialog.fields_dict.inventory_upload.$wrapper.html(
			'<div class="oi-import-instructions">' +
			'<p>' + __("Upload a CSV with columns item_code, warehouse, qty, and optional valuation_rate.") + '</p>' +
			'<p class="text-muted small">' + __("Use ERPNext item codes and leaf warehouse names exactly. Quantities are physical counted quantities, not changes to add. Duplicate item/warehouse rows are rejected.") + '</p>' +
			'<p class="text-muted small">' + __("The engine validates the file, then creates a draft Stock Reconciliation. It never submits the stock adjustment automatically.") + '</p>' +
			'<input type="file" name="inventory_csv" accept=".csv,text/csv" class="form-control" />' +
			'<pre class="oi-import-results text-muted" role="status" style="white-space:pre-wrap;margin-top:16px"></pre>' +
			'</div>'
		);
		dialog.show();
	}

	const metric_labels = {
		sales_value: __("Sales invoiced"),
		purchase_value: __("Purchases invoiced"),
		outstanding_receivables: __("Outstanding receivables"),
		outstanding_payables: __("Outstanding payables"),
		overdue_sales_invoice_count: __("Overdue sales invoices"),
	};

	function render_metrics(data) {
		const $grid = page.body.find(".oi-kpi-grid").empty();
		Object.entries(metric_labels).forEach(([key, label]) => {
			const value = data.metrics[key] || 0;
			const formatted = key === "overdue_sales_invoice_count"
				? cint(value).toLocaleString()
				: format_currency(value, data.currency);
			const $card = $(`<section class="oi-kpi-card">
				<div class="oi-kpi-label"></div>
				<div class="oi-kpi-value"></div>
				<div class="oi-kpi-period"></div>
			</section>`);
			$card.find(".oi-kpi-label").text(label);
			$card.find(".oi-kpi-value").text(formatted);
			$card.find(".oi-kpi-period").text(
				key === "overdue_sales_invoice_count"
					? __("Invoices with an unpaid balance past due")
					: key === "outstanding_receivables" || key === "outstanding_payables"
						? __("Current balance")
						: `${data.from_date} – ${data.to_date}`
			);
			$grid.append($card);
		});
		page.body.find(".oi-definitions").text(
			__("Figures are calculated from submitted invoices. Sales and purchases are invoice totals, not a cash-flow or profit calculation. Outstanding balances are current balances.")
		);
		page.body.find(".oi-status").text(
			`${__("Company")}: ${data.company} · ${__("Updated")}: ${frappe.datetime.now_datetime()}`
		);
	}


	function load_action_items() {
		const $list = page.body.find(".oi-action-list").empty();
		$list.append($("<div class='text-muted small'>").text(__("Loading overdue invoices…")));
		frappe.call({
			method: "erpnext.operations_intelligence.metrics.get_action_items",
			args: { limit: 10 },
			freeze: false,
		}).then((response) => {
			$list.empty();
			const data = response.message;
			if (!data || !data.items || !data.items.length) {
				$list.append($("<div class='oi-action-empty text-muted'>").text(__("No overdue invoices found in records visible to you.")));
				return;
			}
			data.items.forEach((item) => {
				const $row = $("<button type='button' class='oi-action-row'>");
				const $main = $("<span class='oi-action-main'>");
				$main.append($("<span class='oi-action-title'>").text(item.name || __("Invoice")));
				$main.append($("<span class='oi-action-party text-muted'>").text(item.party || item.kind || ""));
				const $detail = $("<span class='oi-action-detail'>");
				$detail.append($("<span class='oi-action-due'>").text(`${__("Due")} ${item.due_date || __("Unknown")}`));
				$detail.append($("<span class='oi-action-amount'>").text(format_currency(item.outstanding_amount || 0, data.currency)));
				$row.append($main, $detail);
				$row.on("click", () => frappe.set_route("Form", item.doctype, item.name));
				$list.append($row);
			});
		}).catch(() => {
			$list.empty().append($("<div class='text-muted small'>").text(__("Could not load overdue invoices. Check your accounting permissions and try again.")));
		});
	}


	function load_low_stock_items() {
		const $list = page.body.find(".oi-stock-list").empty();
		$list.append($("<div class='text-muted small'>").text(__("Checking stock levels…")));
		frappe.call({
			method: "erpnext.operations_intelligence.metrics.get_low_stock_items",
			args: { limit: 10 },
			freeze: false,
		}).then((response) => {
			$list.empty();
			const data = response.message;
			if (!data || !data.items || !data.items.length) {
				$list.append($("<div class='oi-action-empty text-muted'>").text(__("No items at or below a configured reorder level were found in visible stock records.")));
				return;
			}
			data.items.forEach((item) => {
				const $row = $("<button type='button' class='oi-action-row oi-stock-row'>");
				const $main = $("<span class='oi-action-main'>");
				$main.append($("<span class='oi-action-title'>").text(item.item_name || item.item_code));
				$main.append($("<span class='oi-action-party text-muted'>").text(`${item.item_code} · ${item.warehouse}`));
				const $detail = $("<span class='oi-action-detail'>");
				$detail.append($("<span class='oi-action-amount'>").text(`${__("Available")}: ${flt(item.actual_qty)} ${item.stock_uom || ""}`));
				$detail.append($("<span class='oi-action-due'>").text(`${__("Reorder level")}: ${flt(item.reorder_level)} ${item.stock_uom || ""}`));
				$row.append($main, $detail);
				$row.on("click", () => frappe.set_route("Form", "Item", item.item_code));
				$list.append($row);
			});
		}).catch(() => {
			$list.empty().append($("<div class='text-muted small'>").text(__("Could not load inventory signals. Check Stock and Item permissions, then try again.")));
		});
	}

	function load_engine_insights() {
		const $list = page.body.find(".oi-engine-list").empty();
		$list.append($("<div class='text-muted small'>").text(__("Running rules against live records…")));
		frappe.call({
			method: "erpnext.operations_intelligence.engine.get_engine_snapshot",
			args: {
				from_date: page.from_date.get_value(),
				to_date: page.to_date.get_value(),
			},
			freeze: false,
		}).then((response) => {
			$list.empty();
			const snapshot = response.message;
			if (!snapshot || snapshot.mode !== "live_read_only" || !Array.isArray(snapshot.alerts)) {
				$list.append($("<div class='oi-action-empty text-muted'>").text(__("The engine returned an invalid response. No figures have been substituted.")));
				return;
			}
			snapshot.alerts.forEach((alert) => {
				const $row = $("<div class='oi-engine-row'>");
				const $main = $("<div class='oi-engine-main'>");
				const $title = $("<div class='oi-action-title'>").text(alert.title || __("Operational finding"));
				const $detail = $("<div class='oi-engine-detail text-muted small'>").text(alert.detail || "");
				$main.append($title, $detail);
				const severity = ["high", "medium", "info"].includes(alert.severity) ? alert.severity : "info";
				const $severity = $("<span class='oi-engine-severity'>").addClass("oi-severity-" + severity).text(__(severity));
				$row.append($main, $severity);
				$list.append($row);
			});
			page.body.find(".oi-status").text(
				`${__("Company")}: ${snapshot.company} · ${__("Live data")} · ${__("As of")}: ${snapshot.as_of_date}`
			);
		}).catch(() => {
			$list.empty().append($("<div class='oi-action-empty text-muted'>").text(__("Live engine unavailable. Confirm this page is running inside a configured ERPNext site; sample figures are never shown as a fallback.")));
		});
	}

	function refresh_dashboard() {
		load_overview();
		load_action_items();
		load_low_stock_items();
		load_engine_insights();
	}

	function load_overview() {
		const from_date = page.from_date.get_value();
		const to_date = page.to_date.get_value();
		if (from_date && to_date && from_date > to_date) {
			frappe.msgprint(__("From Date cannot be after To Date."));
			return;
		}
		page.body.find(".oi-status").text(__("Loading business metrics…"));
		page.body.find(".oi-kpi-grid").empty().append(
			$("<div class='text-muted'>").text(__("Loading…"))
		);
		frappe.call({
			method: "erpnext.operations_intelligence.metrics.get_overview",
			args: { from_date, to_date },
			freeze: false,
		}).then((response) => {
			if (response.message) {
				render_metrics(response.message);
			}
		}).catch(() => {
			page.body.find(".oi-status").text(__("Could not load Joe&dave Operations Intelligence. Check your default Company and accounting permissions, then try again."));
			page.body.find(".oi-kpi-grid").empty();
		});
	}

	if (!document.getElementById("operations-intelligence-styles")) {
		$("<style id='operations-intelligence-styles'>").text(`
			.operations-intelligence-page { padding: 8px 0 28px; }
			.operations-intelligence-page .oi-intro { display:flex; justify-content:space-between; align-items:flex-start; margin: 8px 0 20px; }
			.operations-intelligence-page .oi-intro h3 { margin: 0 0 6px; font-size: 20px; font-weight: 650; }
			.operations-intelligence-page .oi-kpi-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(205px,1fr)); gap:14px; margin: 16px 0 22px; }
			.operations-intelligence-page .oi-kpi-card { min-width:0; padding:18px; border:1px solid var(--border-color); border-radius:12px; background:var(--card-bg, var(--fg-color)); box-shadow:0 2px 8px rgba(0,0,0,.035); }
			.operations-intelligence-page .oi-kpi-label { color:var(--text-muted); font-size:13px; margin-bottom:12px; }
			.operations-intelligence-page .oi-kpi-value { color:var(--heading-color); font-size:clamp(20px,2.2vw,28px); line-height:1.2; font-weight:650; overflow-wrap:anywhere; }
			.operations-intelligence-page .oi-kpi-period { color:var(--text-muted); font-size:12px; margin-top:10px; }
			.operations-intelligence-page .oi-actions { margin: 22px 0; }
			.operations-intelligence-page .oi-actions-heading h4 { margin: 0 0 5px; font-size: 16px; font-weight: 650; }
			.operations-intelligence-page .oi-actions-heading p { margin-bottom: 12px; }
			.operations-intelligence-page .oi-action-list { border:1px solid var(--border-color); border-radius:10px; overflow:hidden; }
			.operations-intelligence-page .oi-action-row { width:100%; display:flex; justify-content:space-between; align-items:center; gap:16px; text-align:left; padding:13px 16px; border:0; border-bottom:1px solid var(--border-color); background:var(--card-bg, var(--fg-color)); cursor:pointer; }
			.operations-intelligence-page .oi-action-row:last-child { border-bottom:0; }
			.operations-intelligence-page .oi-stock-row .oi-action-amount { color:var(--orange-600, var(--text-color)); }
			.operations-intelligence-page .oi-action-row:hover { background:var(--subtle-fg); }
			.operations-intelligence-page .oi-action-main, .operations-intelligence-page .oi-action-detail { display:flex; flex-direction:column; gap:4px; min-width:0; }
			.operations-intelligence-page .oi-action-title { font-weight:600; overflow-wrap:anywhere; }
			.operations-intelligence-page .oi-action-party, .operations-intelligence-page .oi-action-due { font-size:12px; }
			.operations-intelligence-page .oi-action-detail { text-align:right; align-items:flex-end; }
			.operations-intelligence-page .oi-action-amount { font-weight:650; white-space:nowrap; }
			.operations-intelligence-page .oi-action-empty { padding:18px; }
			.operations-intelligence-page .oi-engine-list { border:1px solid var(--border-color); border-radius:10px; overflow:hidden; }
			.operations-intelligence-page .oi-engine-row { display:flex; justify-content:space-between; align-items:flex-start; gap:14px; padding:15px 16px; border-bottom:1px solid var(--border-color); background:var(--card-bg, var(--fg-color)); }
			.operations-intelligence-page .oi-engine-row:last-child { border-bottom:0; }
			.operations-intelligence-page .oi-engine-main { display:flex; flex-direction:column; gap:5px; min-width:0; }
			.operations-intelligence-page .oi-engine-detail { line-height:1.5; }
			.operations-intelligence-page .oi-engine-severity { flex:none; border-radius:999px; padding:4px 9px; font-size:11px; text-transform:uppercase; letter-spacing:.5px; background:var(--subtle-fg); }
			.operations-intelligence-page .oi-severity-high { color:var(--red-600, #c83b3b); }
			.operations-intelligence-page .oi-severity-medium { color:var(--orange-600, #b96b00); }
			.operations-intelligence-page .oi-severity-info { color:var(--text-muted); }
			.operations-intelligence-page .oi-definitions { padding:14px 16px; border-radius:8px; background:var(--subtle-fg); line-height:1.6; }
			@media(max-width:480px) { .operations-intelligence-page .oi-kpi-grid { grid-template-columns:1fr; } }
		`).appendTo("head");
	}
	refresh_dashboard();
};

