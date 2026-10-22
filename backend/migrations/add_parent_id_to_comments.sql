ALTER TABLE author_post_comments ADD COLUMN parent_id UUID REFERENCES author_post_comments(id) ON DELETE CASCADE;
