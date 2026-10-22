-- Просмотры страниц квеста — без них аналитика автора начинается с «непонятно,
-- вообще кто-то видел публикацию или нет».
--
-- Храним не лог событий, а счётчик на (квест, человек, сутки): строк ровно
-- столько же, сколько дней люди заглядывали, а из него считаются и дневной
-- график, и «разные посетители». `author_post_views` для постов хранит по
-- одной строке на пару (пост, человек) — там дневного ряда не построить.
CREATE TABLE IF NOT EXISTS quest_views (
    quest_id UUID NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    day DATE NOT NULL,
    views INTEGER NOT NULL DEFAULT 1,
    last_view_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (quest_id, user_id, day)
);

-- График «просмотры по дням» для одного квеста.
CREATE INDEX IF NOT EXISTS idx_quest_views_quest_day ON quest_views(quest_id, day);
