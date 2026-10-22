-- Свой аватар вместо картинки из соцсети.
--
-- `avatar_custom` нужен потому, что вход через Яндекс/Telegram каждый раз
-- приносит картинку провайдера и перезаписывает `avatar_url` — без флага
-- свой аватар слетал бы при следующем логине.

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_custom BOOLEAN NOT NULL DEFAULT FALSE;

-- История смен: из неё считается лимит «не чаще N раз в сутки», а причину
-- отказа видно без логов. Отказ тоже строка: иначе накрутчик не отличим от
-- человека, которому ИИ не ответил.
CREATE TABLE IF NOT EXISTS avatar_changes (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    avatar_url TEXT,
    verdict TEXT NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_avatar_changes_user_created
    ON avatar_changes(user_id, created_at DESC);
