frappe.pages["operations-intelligence"].on_page_load = function (wrapper) {
	const page = frappe.ui.make_app_page({
		parent: wrapper,
		title: __("Operations Intelligence"),
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
	page.set_primary_action(__("Refresh"), load_overview, "refresh");

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
			page.body.find(".oi-status").text(__("Could not load Operations Intelligence. Check your default Company and accounting permissions, then try again."));
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
			.operations-intelligence-page .oi-definitions { padding:14px 16px; border-radius:8px; background:var(--subtle-fg); line-height:1.6; }
			@media(max-width:480px) { .operations-intelligence-page .oi-kpi-grid { grid-template-columns:1fr; } }
		`).appendTo("head");
	}
	load_overview();
};

frappe.pages["operations-intelligence"].refresh = function (wrapper) {
	if (wrapper.page && wrapper.page.from_date) {
		// The page's explicit Refresh action controls reloads; route refresh is safe to ignore.
	}
};