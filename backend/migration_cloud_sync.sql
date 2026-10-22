-- ============================================================================
--  Meander Cloud Sync — миграция БД
-- ============================================================================
--  Применять после migration_sync_settings.sql.
--  Идемпотентно: можно повторно запускать.
-- ============================================================================

-- 1. Список облачных квестов пользователя
CREATE TABLE IF NOT EXISTS cloud_sync_quests (
    user_id          UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    quest_id         TEXT        NOT NULL,
    title            TEXT        NOT NULL,
    -- 'user'       = собственный .mnd, физически лежит на диске сервера
    -- 'market_ref' = ссылка на маркет-квест, байты не дублируем
    source           TEXT        NOT NULL DEFAULT 'user',
    size_bytes       BIGINT      NOT NULL DEFAULT 0,
    fingerprint      TEXT,                              -- sha256 содержимого (для user)
    storage_path     TEXT        NOT NULL DEFAULT '',   -- относительный путь на диске (для user)
    market_quest_id  UUID,                              -- ссылка на market.quests (для market_ref)
    market_version   TEXT,                              -- зафиксированная версия маркет-квеста
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ,                       -- soft delete
    PRIMARY KEY (user_id, quest_id),
    CONSTRAINT cloud_sync_source_chk CHECK (source IN ('user', 'market_ref')),
    CONSTRAINT cloud_sync_market_ref_chk CHECK (
        (source = 'user'      AND market_quest_id IS NULL)
     OR (source = 'market_ref' AND market_quest_id IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_cloud_sync_quests_user
    ON cloud_sync_quests(user_id) WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_cloud_sync_quests_market_ref
    ON cloud_sync_quests(market_quest_id) WHERE source = 'market_ref' AND deleted_at IS NULL;

-- 2. Квоты пользователей
CREATE TABLE IF NOT EXISTS cloud_sync_quotas (
    user_id          UUID        PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    -- 'none' | 'starter' | 'free' | 'creator' | 'pro' | 'admin'
    tier             TEXT        NOT NULL DEFAULT 'none',
    -- Реальный размер user-квестов (рефы не учитываем)
    used_bytes       BIGINT      NOT NULL DEFAULT 0,
    used_quests      INT         NOT NULL DEFAULT 0,    -- суммарно user + market_ref
    -- Лимиты текущего tier (продублированы для скорости)
    max_bytes        BIGINT      NOT NULL DEFAULT 0,
    max_quests       INT         NOT NULL DEFAULT 0,
    max_quest_bytes  BIGINT      NOT NULL DEFAULT 0,    -- макс размер 1 .mnd
    max_refs         INT         NOT NULL DEFAULT 0,    -- лимит market_ref (отдельно)
    granted_reason   TEXT,                              -- 'auto', 'manual', 'promo', 'subscription'
    granted_by       UUID        REFERENCES profiles(id),
    granted_at       TIMESTAMPTZ,
    expires_at       TIMESTAMPTZ,                       -- для подписочных tier
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT cloud_sync_quotas_tier_chk
        CHECK (tier IN ('none', 'starter', 'free', 'creator', 'pro', 'admin'))
);

CREATE INDEX IF NOT EXISTS idx_cloud_sync_quotas_tier
    ON cloud_sync_quotas(tier);

-- 3. Аудит-лог (опционально, для расследований злоупотреблений)
CREATE TABLE IF NOT EXISTS cloud_sync_audit (
    id               BIGSERIAL   PRIMARY KEY,
    user_id          UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    quest_id         TEXT,
    action           TEXT        NOT NULL,   -- 'upload', 'download', 'delete', 'ref_create', 'tier_change'
    bytes            BIGINT,
    detail           JSONB,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cloud_sync_audit_user_time
    ON cloud_sync_audit(user_id, created_at DESC);

-- ============================================================================
--  Триггер: при INSERT/UPDATE/DELETE в cloud_sync_quests пересчитываем квоты.
-- ============================================================================
CREATE OR REPLACE FUNCTION recompute_cloud_sync_usage(p_user UUID)
RETURNS VOID AS $$
DECLARE
    v_used_bytes  BIGINT;
    v_used_quests INT;
BEGIN
    SELECT
        COALESCE(SUM(CASE WHEN source = 'user' THEN size_bytes ELSE 0 END), 0),
        COUNT(*)
    INTO v_used_bytes, v_used_quests
    FROM cloud_sync_quests
    WHERE user_id = p_user AND deleted_at IS NULL;

    UPDATE cloud_sync_quotas
       SET used_bytes  = v_used_bytes,
           used_quests = v_used_quests,
           updated_at  = now()
     WHERE user_id = p_user;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_cloud_sync_quests_recompute()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM recompute_cloud_sync_usage(OLD.user_id);
        RETURN OLD;
    ELSE
        PERFORM recompute_cloud_sync_usage(NEW.user_id);
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS cloud_sync_quests_recompute_trg ON cloud_sync_quests;
CREATE TRIGGER cloud_sync_quests_recompute_trg
AFTER INSERT OR UPDATE OR DELETE ON cloud_sync_quests
FOR EACH ROW EXECUTE FUNCTION trg_cloud_sync_quests_recompute();

-- ============================================================================
--  Конец миграции
-- ============================================================================