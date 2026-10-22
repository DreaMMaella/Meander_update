-- ============================================================================
--  Миграция профилей: банеры (стиль шапки) и соцсети.
--  Версия: profile_v2
--  Применить: psql ... -f backend/migration_profile_v2.sql
-- ============================================================================

-- 1. Стиль шапки профиля (баннер за аватаром).
--    Формат JSON: { "type": "preset", "id": "ocean" }
--    Список допустимых id хранится на бэке (см. ALLOWED_BANNER_IDS в profiles.ts).
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS banner_style JSONB DEFAULT NULL;

-- 2. Ссылки на соцсети.
--    Формат JSON: [{ "platform": "telegram", "url": "https://t.me/..." }, ...]
--    Whitelist платформ — на бэке (telegram, youtube, vk, instagram, twitter,
--    github, boosty, discord, website).
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS social_links JSONB DEFAULT '[]'::jsonb;

-- 3. Защита: социалки всегда массив (даже если кто-то прислал null).
UPDATE profiles
   SET social_links = '[]'::jsonb
 WHERE social_links IS NULL;

-- 4. Лёгкие индексы (не обязательные, но удобны для будущих запросов).
CREATE INDEX IF NOT EXISTS idx_profiles_banner_style_gin
    ON profiles USING gin (banner_style);
CREATE INDEX IF NOT EXISTS idx_profiles_social_links_gin
    ON profiles USING gin (social_links);