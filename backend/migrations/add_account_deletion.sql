-- Удаление аккаунта по требованию владельца (App Store 5.1.1(v)).
-- Полностью аддитивно: новые колонки + новая таблица, ничего не переопределяем.
--
-- Семантика:
--   deletion_purge_at  — момент, после которого аккаунт подлежит физическому
--                        удалению. NULL = удаления не запрашивали. Отменить
--                        можно до этого момента (POST /auth/account/restore).
--   deletion_reason    — необязательная причина от пользователя, только для
--                        статистики отказов.
--   account_deletion_audit — журнал запросов и их исхода. user_id живёт в
--                        записи, пока аккаунт можно отменить; при исходе
--                        'purged' обнуляется — в журнале не остаётся ни PII,
--                        ни идентификатора удалённого человека.

ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS deletion_purge_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deletion_reason TEXT;

CREATE TABLE IF NOT EXISTS account_deletion_audit (
    id              BIGSERIAL PRIMARY KEY,
    user_id         UUID,
    requested_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    purge_at        TIMESTAMPTZ NOT NULL,
    acknowledged    BOOLEAN NOT NULL DEFAULT false,
    reason          TEXT,
    resolved_at     TIMESTAMPTZ,
    outcome         TEXT,          -- 'purged' | 'cancelled'
    rows_affected   JSONB
);

CREATE INDEX IF NOT EXISTS idx_profiles_deletion_purge_at
    ON profiles (deletion_purge_at)
    WHERE deletion_purge_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_account_deletion_audit_open
    ON account_deletion_audit (purge_at)
    WHERE resolved_at IS NULL;

-- Миграцию гонят из-под postgres, а приложение живёт под meander_user: без этого
-- INSERT в журнал упадёт на правах (и на sequence, и на таблице).
ALTER TABLE account_deletion_audit OWNER TO meander_user;
ALTER SEQUENCE account_deletion_audit_id_seq OWNER TO meander_user;
