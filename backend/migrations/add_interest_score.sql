-- Migration: Add interest_score to author_posts
ALTER TABLE author_posts ADD COLUMN IF NOT EXISTS interest_score INTEGER DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_author_posts_interest_score ON author_posts (interest_score DESC);
