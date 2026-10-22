ALTER TABLE profiles ADD COLUMN IF NOT EXISTS show_nsfw BOOLEAN DEFAULT FALSE;
ALTER TABLE quests ADD COLUMN IF NOT EXISTS is_nsfw BOOLEAN DEFAULT FALSE;

-- Update the market_quests view to include the is_nsfw flag
CREATE OR REPLACE VIEW market_quests AS
SELECT 
    q.id,
    q.title,
    q.description,
    q.genres,
    q.cover_url,
    q.author_id,
    q.status,
    q.like_count,
    q.dislike_count,
    q.downloads_count,
    q.created_at,
    q.updated_at,
    q.is_featured,
    q.is_nsfw,
    p.full_name as author_name,
    p.avatar_url as author_avatar_url,
    p.is_verified as author_is_verified
FROM quests q
LEFT JOIN profiles p ON q.author_id = p.id;
