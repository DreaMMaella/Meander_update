-- Safe migration for GitHub sync settings storage.
-- Run in a transaction on production.

BEGIN;

CREATE TABLE IF NOT EXISTS profile_sync_settings (
    user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    github_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    github_owner VARCHAR(100),
    github_repo VARCHAR(150),
    github_branch VARCHAR(100) NOT NULL DEFAULT 'main',
    github_root_path VARCHAR(200) NOT NULL DEFAULT 'meander-sync',
    github_token_ciphertext TEXT,
    github_token_iv VARCHAR(64),
    github_token_tag VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT profile_sync_settings_owner_len CHECK (github_owner IS NULL OR char_length(github_owner) <= 100),
    CONSTRAINT profile_sync_settings_repo_len CHECK (github_repo IS NULL OR char_length(github_repo) <= 150),
    CONSTRAINT profile_sync_settings_branch_len CHECK (char_length(github_branch) <= 100),
    CONSTRAINT profile_sync_settings_root_len CHECK (char_length(github_root_path) <= 200)
);

CREATE INDEX IF NOT EXISTS idx_profile_sync_settings_updated_at
    ON profile_sync_settings (updated_at DESC);

COMMIT;
