-- Generic asset market: button presets, backgrounds, sfx, fonts, etc.
DO $$ BEGIN
    CREATE TYPE asset_kind AS ENUM ('button_preset', 'background', 'image', 'sfx', 'font', 'music');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE asset_status AS ENUM ('in_review', 'published', 'rejected');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS market_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind asset_kind NOT NULL,
    title TEXT NOT NULL,
    author_name TEXT, -- denormalized performer/author for display if needed
    description TEXT,
    genre TEXT,
    genres TEXT[] DEFAULT '{}',
    file_url TEXT NOT NULL,
    cover_url TEXT,
    preview_url TEXT,
    license TEXT NOT NULL DEFAULT 'CC-BY',
    file_hash TEXT,
    file_size_bytes BIGINT DEFAULT 0,
    status asset_status DEFAULT 'in_review',
    author_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_market_assets_kind ON market_assets(kind);
CREATE INDEX IF NOT EXISTS idx_market_assets_status ON market_assets(status);
CREATE INDEX IF NOT EXISTS idx_market_assets_created ON market_assets(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_market_assets_author ON market_assets(author_id);
