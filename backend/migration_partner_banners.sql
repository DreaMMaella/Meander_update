-- ============================================================================
--  PARTNER BANNERS — миграция
-- ============================================================================
-- Хранит партнёрские/рекламные баннеры для маркета. Раньше были захардкожены
-- во Flutter-коде (apps/main_app/lib/features/market/widgets/partner_banner.dart).
--
--  Поля:
--    id          — стабильный текстовый идентификатор (например 'onlysq_ai').
--    title       — заголовок.
--    subtitle    — короткое описание.
--    cta_text    — текст CTA-кнопки.
--    url         — ссылка для перехода.
--    image_url   — опциональная фоновая картинка (hero/compact).
--    icon        — кодовое имя иконки (см. _iconFromCode в Dart).
--    tint_color  — hex-цвет без или с '#'.
--    slots       — массив слотов: 'market.top', 'market.mid', 'market.bottom',
--                  'market.sidebar', 'market.header', 'market.quest_card.footer'.
--    pinned      — постоянный партнёр (всегда в ротации).
--    is_active   — выключатель без удаления.
--    sort_order  — порядок (меньше — выше).
-- ============================================================================

CREATE TABLE IF NOT EXISTS partner_banners (
    id           TEXT PRIMARY KEY,
    title        TEXT NOT NULL,
    subtitle     TEXT NOT NULL,
    cta_text     TEXT NOT NULL,
    url          TEXT NOT NULL,
    image_url    TEXT,
    icon         TEXT NOT NULL DEFAULT 'campaign',
    tint_color   TEXT NOT NULL DEFAULT '#6750A4',
    slots        TEXT[] NOT NULL DEFAULT '{}',
    pinned       BOOLEAN NOT NULL DEFAULT FALSE,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order   INT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    updated_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_partner_banners_active
    ON partner_banners (is_active, sort_order);

-- ============================================================================
--  SEED — текущие баннеры из Dart-кода (для бесшовного перехода).
-- ============================================================================
INSERT INTO partner_banners (id, title, subtitle, cta_text, url, icon, tint_color, slots, pinned, sort_order) VALUES
('onlysq_ai',
 'OnlySQ — бесплатный AI API',
 'Партнёр Meander: предоставляет AI-инструменты в редакторе.',
 'Узнать больше',
 'https://onlysq.ru',
 'auto_awesome',
 '#7C4DFF',
 ARRAY['market.top','market.mid','market.bottom','market.sidebar'],
 TRUE,
 0),
('mindteam_ai_bot',
 'Tech',
 'Telegram-бот, который генерирует квесты для Meander.',
 'Открыть в TG',
 'https://t.me/mindteamai_bot',
 'smart_toy',
 '#00BFA5',
 ARRAY['market.top','market.mid','market.bottom','market.sidebar'],
 TRUE,
 1),
('meander_tg',
 'Официальный TG Meander',
 'Новости, релизы и анонсы квестов в Telegram.',
 'Подписаться',
 'https://t.me/meanderRU',
 'send',
 '#229ED9',
 ARRAY['market.top','market.mid','market.bottom','market.sidebar'],
 FALSE,
 10),
('meander_youtube',
 'Канал Meander на YouTube',
 'Гайды, обзоры и релизы новых квестов.',
 'Смотреть',
 'https://www.youtube.com/@meanderRU',
 'video_library',
 '#E53935',
 ARRAY['market.top','market.sidebar','market.mid'],
 FALSE,
 11),
('boosty_support',
 'Поддержи серверы Meander',
 'Boosty — помогает держать инфраструктуру.',
 'Поддержать',
 'https://boosty.to/iilluminat/posts/8e4bc65c-f106-4560-b158-973d6e8a65f6',
 'volunteer_activism',
 '#FF7043',
 ARRAY['market.bottom','market.mid','market.sidebar'],
 FALSE,
 12),
('tg_forum',
 'Форум в Telegram',
 'Задавай вопросы и обсуждай свои квесты.',
 'Открыть',
 'https://t.me/mndForum',
 'forum',
 '#2AABEE',
 ARRAY['market.mid','market.bottom'],
 FALSE,
 13),
('wiki_meander',
 'WikiMeander в TG',
 'Новости, идеи и обсуждения сообщества.',
 'Подписаться',
 'https://t.me/WikiMeander',
 'chat_bubble',
 '#1E88E5',
 ARRAY['market.top','market.sidebar'],
 FALSE,
 14)
ON CONFLICT (id) DO NOTHING;