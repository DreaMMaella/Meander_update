-- Migration: Add media_urls, tags to author_posts and tables for polls

ALTER TABLE author_posts ADD COLUMN IF NOT EXISTS media_urls JSONB DEFAULT '[]'::jsonb;
ALTER TABLE author_posts ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_author_posts_tags ON author_posts USING GIN (tags);

CREATE TABLE IF NOT EXISTS author_post_polls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES author_posts(id) ON DELETE CASCADE,
    question VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS author_post_poll_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID NOT NULL REFERENCES author_post_polls(id) ON DELETE CASCADE,
    text VARCHAR(255) NOT NULL,
    order_index INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS author_post_poll_votes (
    poll_id UUID NOT NULL REFERENCES author_post_polls(id) ON DELETE CASCADE,
    option_id UUID NOT NULL REFERENCES author_post_poll_options(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (poll_id, user_id)
);
