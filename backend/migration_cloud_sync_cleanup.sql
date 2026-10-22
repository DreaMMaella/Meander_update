-- ============================================================================
--  Meander Cloud — cleanup для неактивных пользователей
-- ============================================================================
--  Применять после migration_cloud_sync.sql. Идемпотентно.
-- ============================================================================

-- 1. Поле last_seen_at у профиля (если ещё нет)
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

-- При создании нового профиля считаем что юзер сейчас активен
UPDATE profiles
   SET last_seen_at = COALESCE(last_seen_at, created_at, now())
 WHERE last_seen_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_last_seen_at
    ON profiles(last_seen_at) WHERE last_seen_at IS NOT NULL;

-- 2. Статусы предупреждений в quotas (для отслеживания этапа cleanup)
ALTER TABLE cloud_sync_quotas
    ADD COLUMN IF NOT EXISTS cleanup_stage TEXT NOT NULL DEFAULT 'active'
    -- 'active'    — обычное состояние
    -- 'warning'   — отправлено предупреждение (≥83 дня без захода = за 7 дней до cleanup)
    -- 'archived'  — user-файлы удалены с диска (≥90 дней), записи в БД остались
    -- 'purged'    — всё удалено полностью (>365 дней + 0 квестов в маркете)
    ;

ALTER TABLE cloud_sync_quotas
    ADD COLUMN IF NOT EXISTS cleanup_at TIMESTAMPTZ;