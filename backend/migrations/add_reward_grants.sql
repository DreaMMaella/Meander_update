-- Награды за активность: оформление профиля за стрик, игровые дни, отзывы и
-- скачанные чужие квесты.
--
-- Правила живут кодом в `src/services/rewards.ts`, в базе только журнал
-- выдач. Идемпотентность держится на первичном ключе: повторная выдача того
-- же правила физически невозможна, даже если sweep наложится на запрос
-- пользователя или два инстанса проснутся одновременно.
CREATE TABLE IF NOT EXISTS reward_grants (
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    rule_id TEXT NOT NULL,
    cosmetic_ids TEXT[] NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, rule_id)
);

-- «Мои награды»: у одного пользователя строк мало, но порядок нужен.
CREATE INDEX IF NOT EXISTS idx_reward_grants_user ON reward_grants(user_id, granted_at DESC);
