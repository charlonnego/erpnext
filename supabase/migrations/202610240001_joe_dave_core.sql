-- Joe&dave Operations Intelligence — standalone PostgreSQL core.
-- This is an independent application schema, not an ERPNext/Frappe extension.
-- Apply only to the dedicated Joe&dave Supabase project.

create extension if not exists pgcrypto;

create table if not exists public.jd_businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  legal_name text not null check (length(trim(legal_name)) between 2 and 160),
  display_name text not null check (length(trim(display_name)) between 2 and 100),
  currency_code char(3) not null default 'NGN',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.jd_customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.jd_businesses(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 180),
  email text,
  phone text,
  address text,
  tax_id text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, id)
);

create table if not exists public.jd_invoices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.jd_businesses(id) on delete cascade,
  customer_id uuid not null,
  invoice_number text not null,
  issue_date date not null default current_date,
  due_date date,
  currency_code char(3) not null default 'NGN',
  status text not null default 'draft' check (status in ('draft','issued','part_paid','paid','void')),
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  tax_total numeric(14,2) not null default 0 check (tax_total >= 0),
  total numeric(14,2) not null default 0 check (total >= 0),
  amount_paid numeric(14,2) not null default 0 check (amount_paid >= 0 and amount_paid <= total),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, invoice_number),
  unique (business_id, id),
  foreign key (business_id, customer_id) references public.jd_customers(business_id, id),
  check (due_date is null or due_date >= issue_date)
);

create table if not exists public.jd_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.jd_businesses(id) on delete cascade,
  invoice_id uuid not null,
  description text not null check (length(trim(description)) between 1 and 240),
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  line_subtotal numeric(14,2) generated always as (round(quantity * unit_price, 2)) stored,
  line_tax numeric(14,2) generated always as (round(quantity * unit_price * tax_rate / 100, 2)) stored,
  created_at timestamptz not null default now(),
  foreign key (business_id, invoice_id) references public.jd_invoices(business_id, id) on delete cascade
);

create table if not exists public.jd_receipts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.jd_businesses(id) on delete cascade,
  invoice_id uuid not null,
  receipt_number text not null,
  received_at timestamptz not null default now(),
  amount numeric(14,2) not null check (amount > 0),
  method text not null check (method in ('cash','bank_transfer','card','cheque','other')),
  reference text,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id, receipt_number),
  foreign key (business_id, invoice_id) references public.jd_invoices(business_id, id)
);

create table if not exists public.jd_inventory_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.jd_businesses(id) on delete cascade,
  sku text not null,
  name text not null check (length(trim(name)) between 1 and 180),
  unit text not null default 'pcs',
  quantity_on_hand numeric(14,3) not null default 0 check (quantity_on_hand >= 0),
  reorder_level numeric(14,3) not null default 0 check (reorder_level >= 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  warehouse text not null default 'Main',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, sku),
  unique (business_id, id)
);

create table if not exists public.jd_stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.jd_businesses(id) on delete cascade,
  item_id uuid not null,
  movement_type text not null check (movement_type in ('opening','purchase','sale','adjustment','return')),
  quantity_delta numeric(14,3) not null check (quantity_delta <> 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  source_reference text,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (business_id, item_id) references public.jd_inventory_items(business_id, id)
);

create table if not exists public.jd_audit_events (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.jd_businesses(id) on delete cascade,
  actor_id uuid default auth.uid() references auth.users(id),
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Transactional business rules: totals, receipt allocation and stock ledger.
create or replace function public.jd_recalculate_invoice(p_business_id uuid, p_invoice_id uuid)
returns void
language plpgsql
set search_path = ''
as $
declare
  v_subtotal numeric(14,2);
  v_tax numeric(14,2);
  v_total numeric(14,2);
  v_paid numeric(14,2);
begin
  select coalesce(sum(l.line_subtotal),0), coalesce(sum(l.line_tax),0)
    into v_subtotal, v_tax
    from public.jd_invoice_lines l
   where l.business_id = p_business_id and l.invoice_id = p_invoice_id;
  v_total := v_subtotal + v_tax;
  select coalesce(sum(r.amount),0) into v_paid
    from public.jd_receipts r
   where r.business_id = p_business_id and r.invoice_id = p_invoice_id;
  if v_paid > v_total then
    raise exception 'Receipt total exceeds invoice total';
  end if;
  update public.jd_invoices
     set subtotal = v_subtotal, tax_total = v_tax, total = v_total,
         amount_paid = v_paid,
         status = case
           when status = 'void' then 'void'
           when v_total > 0 and v_paid >= v_total then 'paid'
           when v_paid > 0 then 'part_paid'
           else status
         end,
         updated_at = now()
   where business_id = p_business_id and id = p_invoice_id;
end;
$;

create or replace function public.jd_invoice_lines_after_change()
returns trigger language plpgsql set search_path = '' as $
begin
  if tg_op = 'DELETE' then
    perform public.jd_recalculate_invoice(old.business_id, old.invoice_id);
    return old;
  end if;
  perform public.jd_recalculate_invoice(new.business_id, new.invoice_id);
  if tg_op = 'UPDATE' and (old.business_id <> new.business_id or old.invoice_id <> new.invoice_id) then
    perform public.jd_recalculate_invoice(old.business_id, old.invoice_id);
  end if;
  return new;
end;
$;

drop trigger if exists jd_invoice_lines_recalculate on public.jd_invoice_lines;
create trigger jd_invoice_lines_recalculate
after insert or update or delete on public.jd_invoice_lines
for each row execute function public.jd_invoice_lines_after_change();

create or replace function public.jd_receipts_after_change()
returns trigger language plpgsql set search_path = '' as $
begin
  if tg_op = 'DELETE' then
    perform public.jd_recalculate_invoice(old.business_id, old.invoice_id);
    return old;
  end if;
  perform public.jd_recalculate_invoice(new.business_id, new.invoice_id);
  if tg_op = 'UPDATE' and (old.business_id <> new.business_id or old.invoice_id <> new.invoice_id) then
    perform public.jd_recalculate_invoice(old.business_id, old.invoice_id);
  end if;
  return new;
end;
$;

drop trigger if exists jd_receipts_recalculate on public.jd_receipts;
create trigger jd_receipts_recalculate
after insert or update or delete on public.jd_receipts
for each row execute function public.jd_receipts_after_change();

create or replace function public.jd_stock_movement_apply()
returns trigger language plpgsql set search_path = '' as $
begin
  update public.jd_inventory_items
     set quantity_on_hand = quantity_on_hand + new.quantity_delta,
         unit_cost = case when new.unit_cost > 0 then new.unit_cost else unit_cost end,
         updated_at = now()
   where business_id = new.business_id and id = new.item_id;
  if not found then
    raise exception 'Inventory item not found for this business';
  end if;
  return new;
end;
$;

drop trigger if exists jd_stock_movement_apply_trigger on public.jd_stock_movements;
create trigger jd_stock_movement_apply_trigger
after insert on public.jd_stock_movements
for each row execute function public.jd_stock_movement_apply();

create index if not exists jd_customers_business_name_idx on public.jd_customers(business_id, name);
create index if not exists jd_invoices_business_status_due_idx on public.jd_invoices(business_id, status, due_date);
create index if not exists jd_receipts_invoice_idx on public.jd_receipts(business_id, invoice_id, received_at);
create index if not exists jd_inventory_business_reorder_idx on public.jd_inventory_items(business_id, active, quantity_on_hand, reorder_level);
create index if not exists jd_audit_business_created_idx on public.jd_audit_events(business_id, created_at desc);

-- Every business table is owner-isolated. No anonymous data access.
alter table public.jd_businesses enable row level security;
alter table public.jd_customers enable row level security;
alter table public.jd_invoices enable row level security;
alter table public.jd_invoice_lines enable row level security;
alter table public.jd_receipts enable row level security;
alter table public.jd_inventory_items enable row level security;
alter table public.jd_stock_movements enable row level security;
alter table public.jd_audit_events enable row level security;

drop policy if exists jd_business_owner_all on public.jd_businesses;
create policy jd_business_owner_all on public.jd_businesses
  for all to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists jd_customers_owner_all on public.jd_customers;
create policy jd_customers_owner_all on public.jd_customers for all to authenticated
  using (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())));

drop policy if exists jd_invoices_owner_all on public.jd_invoices;
create policy jd_invoices_owner_all on public.jd_invoices for all to authenticated
  using (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())));

drop policy if exists jd_invoice_lines_owner_all on public.jd_invoice_lines;
create policy jd_invoice_lines_owner_all on public.jd_invoice_lines for all to authenticated
  using (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())));

drop policy if exists jd_receipts_owner_all on public.jd_receipts;
create policy jd_receipts_owner_all on public.jd_receipts for all to authenticated
  using (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())));

drop policy if exists jd_inventory_owner_all on public.jd_inventory_items;
create policy jd_inventory_owner_all on public.jd_inventory_items for all to authenticated
  using (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())));

drop policy if exists jd_stock_movements_owner_all on public.jd_stock_movements;
create policy jd_stock_movements_owner_all on public.jd_stock_movements for all to authenticated
  using (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())));

drop policy if exists jd_audit_events_owner_select on public.jd_audit_events;
create policy jd_audit_events_owner_select on public.jd_audit_events for select to authenticated
  using (exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())));
drop policy if exists jd_audit_events_owner_insert on public.jd_audit_events;
create policy jd_audit_events_owner_insert on public.jd_audit_events for insert to authenticated
  with check (actor_id = (select auth.uid()) and exists (select 1 from public.jd_businesses b where b.id = business_id and b.owner_id = (select auth.uid())));

grant select, insert, update, delete on public.jd_businesses, public.jd_customers, public.jd_invoices, public.jd_invoice_lines, public.jd_receipts, public.jd_inventory_items to authenticated;
grant select, insert on public.jd_stock_movements to authenticated;
grant select, insert on public.jd_audit_events to authenticated;
revoke all on public.jd_businesses, public.jd_customers, public.jd_invoices, public.jd_invoice_lines, public.jd_receipts, public.jd_inventory_items, public.jd_stock_movements, public.jd_audit_events from anon;

-- Owner-scoped summary. No fabricated/sample numbers.
create or replace view public.jd_business_summary with (security_invoker = true) as
select b.id as business_id,
       coalesce((select sum(i.total - i.amount_paid) from public.jd_invoices i where i.business_id = b.id and i.status in ('issued','part_paid') and i.total > i.amount_paid), 0)::numeric(14,2) as receivables,
       coalesce((select sum(i.total - i.amount_paid) from public.jd_invoices i where i.business_id = b.id and i.status in ('issued','part_paid') and i.due_date < current_date and i.total > i.amount_paid), 0)::numeric(14,2) as overdue_receivables,
       coalesce((select count(*) from public.jd_invoices i where i.business_id = b.id and i.status in ('issued','part_paid') and i.due_date < current_date and i.total > i.amount_paid), 0)::bigint as overdue_invoice_count,
       coalesce((select count(*) from public.jd_inventory_items s where s.business_id = b.id and s.active and s.quantity_on_hand <= s.reorder_level), 0)::bigint as low_stock_count
from public.jd_businesses b
where b.owner_id = (select auth.uid());

grant select on public.jd_business_summary to authenticated;
revoke all on public.jd_business_summary from anon;
