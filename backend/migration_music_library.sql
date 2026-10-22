-- Music library: internal tracks for quests
DO $$ BEGIN
    CREATE TYPE music_status AS ENUM ('in_review', 'published', 'rejected');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS music_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    performer TEXT NOT NULL,
    description TEXT,
    genre TEXT,
    genres TEXT[] DEFAULT '{}',
    file_url TEXT NOT NULL,
    cover_url TEXT,
    license TEXT NOT NULL DEFAULT 'CC-BY',
    duration_seconds INTEGER DEFAULT 0,
    file_hash TEXT,
    file_size_bytes BIGINT DEFAULT 0,
    status music_status DEFAULT 'in_review',
    author_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_music_tracks_status ON music_tracks(status);
CREATE INDEX IF NOT EXISTS idx_music_tracks_genre ON music_tracks(genre);
CREATE INDEX IF NOT EXISTS idx_music_tracks_created ON music_tracks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_music_tracks_author ON music_tracks(author_id);
