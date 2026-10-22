-- Добавляем общее время в самом приложении
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS total_playtime_seconds BIGINT DEFAULT 0;

-- Создаем таблицу для учета времени в конкретных квестах
CREATE TABLE IF NOT EXISTS user_quest_playtime (
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    quest_id UUID REFERENCES quests(id) ON DELETE CASCADE,
    playtime_seconds BIGINT DEFAULT 0,
    last_played_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, quest_id)
);
