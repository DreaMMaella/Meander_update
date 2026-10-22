-- Migration: Add views and author_post_views
ALTER TABLE author_posts ADD COLUMN IF NOT EXISTS views_count INTEGER DEFAULT 0;

CREATE TABLE IF NOT EXISTS author_post_views (
    post_id UUID NOT NULL REFERENCES author_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

