-- Личные сообщения и системный чат.
--
-- Диалог — пара людей, а не «подписка на переписку»: уникальность по
-- (user_a, user_b) с user_a < user_b значит, что у двух аккаунтов физически не
-- может завестись два окна переписки, и непрочитанное считается один раз.
--
-- Системный чат — тот же диалог, только вторым участником числится сервисный
-- аккаунт Meander. Отдельной таблицы для новостей нет: лента диалогов, экран
-- чата, счётчики и realtime-комната user_<id> тогда работают для обоих случаев
-- без веток «а для системного — по-другому».

-- 1. Сервисный аккаунт. Id фиксированный: он зашит в код как SYSTEM_USER_ID, и
-- по нему система отличает свои сообщения от человеческих.
INSERT INTO profiles (id, full_name, email, role, bio, is_verified)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Meander',
    'system@meander.local',
    'user',
    'Официальный аккаунт команды. Сюда приходят новости и системные уведомления.',
    TRUE
)
ON CONFLICT (id) DO NOTHING;

-- 2. Диалог.
CREATE TABLE IF NOT EXISTS dm_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    user_b UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    last_message_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (user_a < user_b),
    UNIQUE (user_a, user_b)
);

-- Один участник мог удалить переписку у себя, оставив её у другого, и читает
-- он её не с того же места, что собеседник.
CREATE TABLE IF NOT EXISTS dm_thread_state (
    thread_id UUID NOT NULL REFERENCES dm_threads(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hidden_at TIMESTAMPTZ,
    muted_at TIMESTAMPTZ,
    PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE IF NOT EXISTS dm_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID NOT NULL REFERENCES dm_threads(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    -- Для системного треда: 'news' — рассылка команды, остальное — type
    -- уведомления (quest_like, review_reply, …). Клиент по нему рисует иконку и
    -- делает глубокий переход; в человеческом диалоге kind всегда 'text'.
    kind TEXT NOT NULL DEFAULT 'text',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- Лента диалогов сортируется по последнему сообщению, окно чата листает историю
-- назад — обоим нужен индекс, оканчивающийся на created_at DESC.
CREATE INDEX IF NOT EXISTS idx_dm_threads_last ON dm_threads(last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_dm_threads_user_a ON dm_threads(user_a, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_dm_threads_user_b ON dm_threads(user_b, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_dm_messages_thread_created
    ON dm_messages(thread_id, created_at DESC);

-- 3. Блокировка. Одна таблица закрывает и «не писать мне», и «не показывать
-- его в сообществе»: без неё настройка приватности ЛС была бы вежливой
-- просьбой, а не механизмом.
CREATE TABLE IF NOT EXISTS user_blocks (
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, blocked_id),
    CHECK (user_id <> blocked_id)
);

-- Индекс для проверки «заблокирован ли я у него» на каждом входящем.
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked_id);

-- 4. Настройка «кто может писать» живёт в профиле, а не в колонках: режимов
-- может быть больше, чем перечислимо в CHECK, и менять состав не мигрируя —
-- нормальное состояние для этой функции.
ALTER TABLE profiles
    ADD COLUMN IF NOT EXISTS dm_privacy JSONB NOT NULL DEFAULT
        '{"mode":"everyone","min_playtime_hours":0,"min_account_age_days":0}'::jsonb;

-- 5. Владение. Миграции исполняет superuser `postgres`, а приложение ходит в
-- базу своей ролью — без этого шака новые таблицы отвечали ей 42501 permission
-- denied (проверено на проде: каталог форумов падал ровно так). Роль берётся от
-- уже существующей таблицы, чтобы файл не зависел от имени в конкретном стенде.
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
    FOREACH t IN ARRAY ARRAY['dm_threads', 'dm_thread_state', 'dm_messages', 'user_blocks'] LOOP
        EXECUTE format('ALTER TABLE %I OWNER TO %I', t, app_role);
    END LOOP;
END $$;
