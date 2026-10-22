-- AI Features Migration
-- Run: psql $DATABASE_URL -f migration_ai_features.sql

-- 1. Token buckets for rate limiting
CREATE TABLE IF NOT EXISTS ai_token_buckets (
    user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    tokens_remaining INTEGER DEFAULT 100 NOT NULL,
    max_tokens INTEGER DEFAULT 100 NOT NULL,
    last_refill TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. AI cache for expensive operations
CREATE TABLE IF NOT EXISTS ai_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cache_key TEXT NOT NULL UNIQUE,
    result JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_ai_cache_key ON ai_cache(cache_key);
CREATE INDEX IF NOT EXISTS idx_ai_cache_expires ON ai_cache(expires_at);

-- 3. Quest summaries cache (tied to quest version)
CREATE TABLE IF NOT EXISTS ai_quest_summaries (
    quest_id UUID PRIMARY KEY REFERENCES quests(id) ON DELETE CASCADE,
    summary TEXT NOT NULL,
    quest_version TEXT NOT NULL,
    generated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. AI keywords for semantic search
ALTER TABLE quests ADD COLUMN IF NOT EXISTS ai_keywords TEXT[];
ALTER TABLE quests ADD COLUMN IF NOT EXISTS ai_analyzed_at TIMESTAMPTZ;

-- 5. AI moderation fields for reports
ALTER TABLE reports ADD COLUMN IF NOT EXISTS ai_severity TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS ai_suggested_action TEXT;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS ai_confidence FLOAT;

-- 6. GIN index for keyword search
CREATE INDEX IF NOT EXISTS idx_quests_ai_keywords ON quests USING GIN(ai_keywords);

-- 7. Auto-create token bucket on new user
CREATE OR REPLACE FUNCTION create_ai_token_bucket()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO ai_token_buckets (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_create_ai_token_bucket ON profiles;
CREATE TRIGGER trg_create_ai_token_bucket
    AFTER INSERT ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION create_ai_token_bucket();

-- 8. Invalidate summaries when quest version changes
CREATE OR REPLACE FUNCTION invalidate_ai_summary_on_version_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.version IS DISTINCT FROM NEW.version THEN
        DELETE FROM ai_quest_summaries WHERE quest_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invalidate_ai_summary ON quests;
CREATE TRIGGER trg_invalidate_ai_summary
    AFTER UPDATE ON quests
    FOR EACH ROW
    EXECUTE FUNCTION invalidate_ai_summary_on_version_change();
