--liquibase formatted sql

--changeset thanhngo:payment-provider-sync-enabled
-- Copy legacy is_enabled values into enabled after seed data is applied.
UPDATE payment_provider
SET enabled = COALESCE(enabled, is_enabled)
WHERE enabled IS NULL;
