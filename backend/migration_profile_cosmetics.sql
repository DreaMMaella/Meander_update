-- ============================================================================
--  Миграция: косметика профиля («оформление» как награда)
--  Версия: profile_cosmetics
--  Применить: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/migration_profile_cosmetics.sql
--
--  Всё аддитивно: ни один существующий столбец не меняется и не удаляется,
--  старые версии приложения продолжают видеть прежние banner_style/social_links.
-- ============================================================================

-- 1. Что НАДЕТО у пользователя.
--    Формат: { "banner": "aurora_drift", "avatar_frame": "prism_ring",
--              "name_style": null, "effect": "snowfall" }
--    id проверяются по каталогу на бэке (src/services/cosmetics.ts).
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS cosmetics JSONB DEFAULT NULL;

-- 2. Чем пользователь ВЛАДЕЕТ. Строка = одно право на один предмет.
--    Бессрочная выдача — expires_at IS NULL; промокоды и конкурсы пишут source.
CREATE TABLE IF NOT EXISTS user_cosmetics (
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    cosmetic_id TEXT NOT NULL,
    slot        TEXT NOT NULL CHECK (slot IN ('banner','avatar_frame','name_style','effect')),
    tier        TEXT NOT NULL CHECK (tier IN ('common','rare','epic','legendary')),
    source      TEXT NOT NULL DEFAULT 'admin_grant',
    reason      TEXT,
    granted_by  UUID REFERENCES profiles(id) ON DELETE SET NULL,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ,
    PRIMARY KEY (user_id, cosmetic_id)
);

CREATE INDEX IF NOT EXISTS idx_user_cosmetics_user    ON user_cosmetics(user_id);
CREATE INDEX IF NOT EXISTS idx_user_cosmetics_expires ON user_cosmetics(expires_at)
    WHERE expires_at IS NOT NULL;

-- 3. Промокод теперь может выдавать не только премиум, но и оформление.
--    Массив id из каталога; пусто = как раньше, только дни рекламы.
ALTER TABLE promo_codes
    ADD COLUMN IF NOT EXISTS cosmetic_ids TEXT[] NOT NULL DEFAULT '{}';

-- 4. view `market_quests` НЕ трогаем. На проде он определён явным списком
--    колонок (в нём нет quests.ai_keywords и quests.ai_analyzed_at — это
--    сделано специально), поэтому `CREATE OR REPLACE VIEW ... SELECT q.*`
--    переписал бы состав колонок витрины. Стиль ника автора выборки из
--    витрины получают отдельным `LEFT JOIN profiles` в src/routes/quests.ts.
--
--    Проверить живое определение перед деплоем:
--    `SELECT pg_get_viewdef('market_quests', true)`
