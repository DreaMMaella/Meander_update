-- Migration: Add Telegram auth support (safe, additive, no link by email)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS telegram_id TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS telegram_username TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_telegram_id ON profiles (telegram_id) WHERE telegram_id IS NOT NULL;
