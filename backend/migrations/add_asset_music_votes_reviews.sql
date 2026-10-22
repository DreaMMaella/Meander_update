-- Migration: Add votes and reviews for market_assets and music_tracks
-- Safe, additive, idempotent. Run: psql "$DATABASE_URL" -f backend/migrations/add_asset_music_votes_reviews.sql

-- Asset votes
CREATE TABLE IF NOT EXISTS asset_votes (
    asset_id UUID NOT NULL REFERENCES market_assets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    is_like BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (asset_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_asset_votes_asset ON asset_votes(asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_votes_user ON asset_votes(user_id);

-- Music votes
CREATE TABLE IF NOT EXISTS music_votes (
    music_id UUID NOT NULL REFERENCES music_tracks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    is_like BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (music_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_music_votes_music ON music_votes(music_id);
CREATE INDEX IF NOT EXISTS idx_music_votes_user ON music_votes(user_id);

-- Asset reviews (reuse review_status enum from quests)
CREATE TABLE IF NOT EXISTS asset_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL REFERENCES market_assets(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    text_content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    status review_status DEFAULT 'approved'
);
CREATE INDEX IF NOT EXISTS idx_asset_reviews_asset ON asset_reviews(asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_reviews_author ON asset_reviews(author_id);
CREATE INDEX IF NOT EXISTS idx_asset_reviews_created ON asset_reviews(created_at DESC);

-- Music reviews
CREATE TABLE IF NOT EXISTS music_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    music_id UUID NOT NULL REFERENCES music_tracks(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    text_content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    status review_status DEFAULT 'approved'
);
CREATE INDEX IF NOT EXISTS idx_music_reviews_music ON music_reviews(music_id);
CREATE INDEX IF NOT EXISTS idx_music_reviews_author ON music_reviews(author_id);
CREATE INDEX IF NOT EXISTS idx_music_reviews_created ON music_reviews(created_at DESC);

-- Optional: add like counters for faster queries (computed if not exist)
ALTER TABLE market_assets ADD COLUMN IF NOT EXISTS like_count INTEGER DEFAULT 0;
ALTER TABLE market_assets ADD COLUMN IF NOT EXISTS dislike_count INTEGER DEFAULT 0;
ALTER TABLE music_tracks ADD COLUMN IF NOT EXISTS like_count INTEGER DEFAULT 0;
ALTER TABLE music_tracks ADD COLUMN IF NOT EXISTS dislike_count INTEGER DEFAULT 0;
