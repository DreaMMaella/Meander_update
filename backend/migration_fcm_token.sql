-- Safe migration: add fcm_token column to profiles
-- This is a nullable TEXT column, does NOT affect existing data or queries
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;