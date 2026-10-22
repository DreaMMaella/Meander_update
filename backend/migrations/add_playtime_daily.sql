-- Игровые сутки: сколько секунд наиграно в каждом квесте за каждый день.
--
-- `user_quest_playtime` хранит только накопленную сумму, поэтому из неё
-- не восстановить ни «был ли у человека игровой день» (нужно для наград),
-- ни дневной график для автора квеста.
CREATE TABLE IF NOT EXISTS playtime_daily (
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    quest_id UUID NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
    day DATE NOT NULL,
    seconds BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, quest_id, day)
);

-- График автора: «сколько играли по дням» за последние N дней.
CREATE INDEX IF NOT EXISTS idx_playtime_daily_quest_day ON playtime_daily(quest_id, day);
-- Проверка дня активности при выдаче наград.
CREATE INDEX IF NOT EXISTS idx_playtime_daily_user_day ON playtime_daily(user_id, day);

-- Серверная метка последнего синка. Клиент присылает дельты, и без сверки с
-- реально прошедшим временем один аккаунт накручивает ~840 часов в сутки,
-- долбя эндпоинт раз в пять минут по максимуму за раз.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS playtime_last_sync_at TIMESTAMPTZ;
