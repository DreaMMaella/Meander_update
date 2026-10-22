-- Язык квеста (#331).
--
-- Автор выбирает язык в настройках квеста, он лежит в `config.json` как
-- `language`. Сервер хранит его отдельной колонкой, чтобы маркет мог первыми
-- показывать квесты на языке игрока, не распаковывая архивы.
--
-- ВНИМАНИЕ ПРОД: витрина `market_quests` определена явным списком колонок
-- (без quests.ai_*), поэтому новой колонки в ней просто нет — её нужно
-- пересоздать. Postgres разрешает `CREATE OR REPLACE VIEW` только добавлять
-- колонки в конец списка, поэтому `q.language` стоит последним.
--
-- ПОРЯДОК ВЫКАТКИ: сначала этот файл, потом перезапуск бэкенда. Публикация
-- (POST /quests) пишет новую колонку, и без неё загрузка квеста упала бы
-- 500-й. Файл идемпотентен, повторить можно.
--
--   sudo -u postgres psql -d meander_db -v ON_ERROR_STOP=1 \
--     -f backend/migration_quest_language.sql
--
-- Проверка после применения (должно быть ровно одна строка `language|text`):
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'quests' AND column_name = 'language';

-- 1. Колонка. `NULL` — автор не указал язык; клиент считает такой квест
--    русским (язык оригинала интерфейса), поэтому DEFAULT не нужен.
ALTER TABLE quests
    ADD COLUMN IF NOT EXISTS language TEXT;

-- 2. Витрина: тот же список колонок, что живёт на проде, плюс `language`.
CREATE OR REPLACE VIEW market_quests AS
SELECT
    q.id,
    q.download_url,
    q.preview_image_url,
    q.title,
    q.description,
    q.downloads_count,
    q.version,
    q.created_at,
    q.updated_at,
    q.status,
    q.author_id,
    q.moderator_comment,
    q.category,
    q.file_hash,
    q.is_featured,
    q.like_count,
    q.dislike_count,
    q.quest_size_bytes,
    q.node_count,
    q.estimated_playtime,
    q.github_release_id,
    q.genres,
    q.is_demo,
    q.is_nsfw,
    p.full_name AS author_name,
    p.is_verified AS author_is_verified,
    (SELECT AVG(r.rating) FROM ratings r WHERE r.quest_id = q.id) AS average_rating,
    q.language
FROM quests q
LEFT JOIN profiles p ON q.author_id = p.id;

-- Витрину пересоздал суперюзер — вернём владельца приложению, иначе бэкенд
-- потеряет права на неё при следующей ротации.
ALTER VIEW market_quests OWNER TO meander_user;

-- 3. Откат:
--    ALTER TABLE quests DROP COLUMN IF EXISTS language;
--    (витру пересоздать без `q.language` тем же явным списком)
