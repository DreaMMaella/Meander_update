-- Migration: Add Yandex auth support (safe, additive, no link by email)
-- Does NOT touch existing google_id/email constraints.
-- Run: psql "$DATABASE_URL" -f backend/migrations/add_yandex_auth.sql

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS yandex_id TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS yandex_login TEXT;

-- Partial unique index: allows many NULLs, prevents duplicate yandex_id
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_yandex_id
  ON profiles (yandex_id) WHERE yandex_id IS NOT NULL;
