-- Migration: Add Apple (Sign in with Apple) auth support — safe, additive, no link by email
-- Does NOT touch existing google_id/email constraints.
-- Run: psql "$DATABASE_URL" -f backend/migrations/add_apple_auth.sql

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS apple_id TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS apple_email_relayed BOOLEAN;

-- Partial unique index: allows many NULLs, prevents duplicate apple_id
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_apple_id
  ON profiles (apple_id) WHERE apple_id IS NOT NULL;
