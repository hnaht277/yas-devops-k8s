--liquibase formatted sql

--changeset thanhngo:payment-provider-compat-is-enabled
-- Keep backward compatibility for legacy data changelogs that still insert into is_enabled.
ALTER TABLE IF EXISTS payment_provider
ADD COLUMN IF NOT EXISTS is_enabled boolean;

UPDATE payment_provider
SET is_enabled = enabled
WHERE is_enabled IS NULL
  AND enabled IS NOT NULL;
