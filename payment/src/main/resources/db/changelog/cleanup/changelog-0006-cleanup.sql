--liquibase formatted sql

--changeset thanhngo:cleanup-remove-is-enabled

-- Step 1: đảm bảo không mất data
UPDATE payment_provider
SET enabled = COALESCE(enabled, is_enabled)
WHERE enabled IS NULL;

-- Step 2: drop cột legacy
ALTER TABLE payment_provider
DROP COLUMN IF EXISTS is_enabled;