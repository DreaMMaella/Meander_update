-- Очистка AI-кэша от обрезанных ответов (после фикса max_tokens).
-- Запустить ОДИН РАЗ на проде после деплоя нового кода:
--   psql $DATABASE_URL -f migration_clear_ai_cache.sql

-- Удаляем все обрезанные summary
DELETE FROM ai_quest_summaries;

-- Удаляем кэш описаний, ключевых слов и переводов (могут быть обрезаны)
DELETE FROM ai_cache
WHERE cache_key LIKE 'fix-text:%'
   OR cache_key LIKE 'keywords:%'
   OR cache_key LIKE 'translate:%'
   OR cache_key LIKE 'description:%';

-- Показать сколько осталось записей
SELECT
    (SELECT COUNT(*) FROM ai_cache) AS ai_cache_left,
    (SELECT COUNT(*) FROM ai_quest_summaries) AS summaries_left;