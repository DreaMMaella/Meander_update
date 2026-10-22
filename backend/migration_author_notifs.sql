BEGIN;

-- Add settings for author notifications
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS author_notifs_mode VARCHAR(10) DEFAULT 'all' CHECK (author_notifs_mode IN ('all', 'none')),
ADD COLUMN IF NOT EXISTS author_notifs_exceptions UUID[] DEFAULT '{}';

COMMIT;
