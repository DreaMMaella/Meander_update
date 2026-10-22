-- Форумы: свои сообщества + обсуждение каждого опубликованного квеста.
--
-- Форум — это не новый вид контента, а полка, на которую ложатся уже существующие
-- посты (`author_posts`). Специальной таблицы «топик форума» нет намеренно: у
-- поста уже есть лайки, комментарии с ответами, картинки, опросы, просмотры,
-- интерес-скор, жалобы и модерация. Вторая система постов удвоила бы и весь этот
-- уход, и число мест, где одно и то же действие работает по-разному.
--
-- Поэтому миграция добавляет посту только две вещи: к какому форуму он относится
-- и заголовок топика.

-- 1. Форум.
CREATE TABLE IF NOT EXISTS forums (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    -- 'user' — человек собрал сообщество сам, 'quest' — форум-обсуждение квеста.
    kind TEXT NOT NULL DEFAULT 'user',
    -- Для kind='quest': один квест — один форум. UNIQUE и есть та гарантия,
    -- которая не даст завестись второму окну обсуждения того же квеста.
    quest_id UUID UNIQUE REFERENCES quests(id) ON DELETE CASCADE,
    creator_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    -- true — писать могут только участники; читать по-прежнему можно всем.
    is_restricted BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    removed_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (kind IN ('user', 'quest')),
    CHECK (kind <> 'quest' OR quest_id IS NOT NULL),
    CHECK (slug ~ '^[a-z0-9][a-z0-9_-]{2,39}$')
);

CREATE INDEX IF NOT EXISTS idx_forums_creator ON forums(creator_id);
CREATE INDEX IF NOT EXISTS idx_forums_kind_active ON forums(kind, is_active);

-- 2. Участник. Роль 'mod' даёт право удалять топики и банить в этом форуме;
-- создатель становится модером сразу при создании.
CREATE TABLE IF NOT EXISTS forum_members (
    forum_id UUID NOT NULL REFERENCES forums(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (forum_id, user_id),
    CHECK (role IN ('member', 'mod'))
);

-- Бан в рамках одного форума: забаненный в «своём» сабреддите человек не
-- исчезает из остального сообщества.
CREATE TABLE IF NOT EXISTS forum_bans (
    forum_id UUID NOT NULL REFERENCES forums(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    banned_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (forum_id, user_id)
);

-- 3. Пост ложится на полку. NULL — пост в общей ленте, как и раньше: ни один
-- существующий запрос не меняется, потому что колонка новая и пустая.
ALTER TABLE author_posts
    ADD COLUMN IF NOT EXISTS forum_id UUID REFERENCES forums(id) ON DELETE CASCADE;
ALTER TABLE author_posts
    ADD COLUMN IF NOT EXISTS title TEXT;

-- Лобби форума — это «топики этого форума, свежие сверху»; индекс ровно под это.
CREATE INDEX IF NOT EXISTS idx_author_posts_forum
    ON author_posts(forum_id, created_at DESC) WHERE forum_id IS NOT NULL;

-- 4. На форум можно пожаловаться как на место, где спамили, — иначе жаловаться
-- придётся на каждый пост по отдельности.
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_reported_type_check;
ALTER TABLE reports ADD CONSTRAINT reports_reported_type_check
    CHECK (reported_type = ANY (ARRAY[
        'quest', 'review', 'user', 'wall_post', 'wall_comment',
        'asset', 'music', 'forum'
    ]));

-- 5. Владение — см. пункт 5 в add_direct_messages.sql: таблицы, созданные
-- superuser, приложение не увидит ни в одном запросе.
DO $$
DECLARE
    app_role text;
    t text;
BEGIN
    SELECT r.rolname INTO app_role
      FROM pg_class c JOIN pg_roles r ON r.oid = c.relowner
     WHERE c.relname = 'profiles' AND c.relnamespace = 'public'::regnamespace;
    IF app_role IS NULL THEN
        RAISE NOTICE 'роль приложения не найдена — владение не менялось';
        RETURN;
    END IF;
    FOREACH t IN ARRAY ARRAY['forums', 'forum_members', 'forum_bans'] LOOP
        EXECUTE format('ALTER TABLE %I OWNER TO %I', t, app_role);
    END LOOP;
END $$;
