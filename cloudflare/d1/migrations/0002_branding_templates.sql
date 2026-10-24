-- Branding, document templates and analytics-ready fields for Joe&dave D1.
-- Apply once to an existing 0001 schema. Logo uploads are limited by the API.
ALTER TABLE jd_businesses ADD COLUMN business_address TEXT;
ALTER TABLE jd_businesses ADD COLUMN business_phone TEXT;
ALTER TABLE jd_businesses ADD COLUMN business_email TEXT;
ALTER TABLE jd_businesses ADD COLUMN tax_id TEXT;
ALTER TABLE jd_businesses ADD COLUMN logo_data_url TEXT;
ALTER TABLE jd_businesses ADD COLUMN invoice_template TEXT NOT NULL DEFAULT 'modern';
ALTER TABLE jd_businesses ADD COLUMN receipt_template TEXT NOT NULL DEFAULT 'classic';
ALTER TABLE jd_businesses ADD COLUMN brand_color TEXT NOT NULL DEFAULT '#245b3a';
