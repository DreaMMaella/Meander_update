-- Удаляет ИИ-инфраструктуру: таблицы кэша/токенов, служебные колонки и триггеры.
-- Код клиента и бэкенда эти поля больше не читает и не пишет (модерация теперь
-- правила в src/services/content_rules.ts).
--
-- ВНИМАНИЕ: удаление необратимо. Перед применением — свежий дамп:
--   pg_dump "$DATABASE_URL" -Fc -f ~/backup_before_drop_ai.sql
-- Выполнять: psql "$DATABASE_URL" -f migration_drop_ai_features.sql
-- Файл лежит НЕ в migrations/ — он не применяется автоматически и остаётся до твоего решения.
-- После: вернуть владельца таблиц, если миграция меняла права
-- (ALTER TABLE ... OWNER TO meander_user).

DROP TRIGGER IF EXISTS trg_create_ai_token_bucket ON profiles;
DROP FUNCTION IF EXISTS create_ai_token_bucket();

DROP TRIGGER IF EXISTS trg_invalidate_ai_summary ON quests;
DROP FUNCTION IF EXISTS invalidate_ai_summary_on_version_change();

DROP INDEX IF EXISTS idx_quests_ai_keywords;
DROP INDEX IF EXISTS idx_ai_cache_key;
DROP INDEX IF EXISTS idx_ai_cache_expires;

DROP TABLE IF EXISTS ai_token_buckets;
DROP TABLE IF EXISTS ai_cache;
DROP TABLE IF EXISTS ai_quest_summaries;

ALTER TABLE quests  DROP COLUMN IF EXISTS ai_keywords;
ALTER TABLE quests  DROP COLUMN IF EXISTS ai_analyzed_at;
ALTER TABLE reports DROP COLUMN IF EXISTS ai_severity;
ALTER TABLE reports DROP COLUMN IF EXISTS ai_suggested_action;
ALTER TABLE reports DROP COLUMN IF EXISTS ai_confidence;
