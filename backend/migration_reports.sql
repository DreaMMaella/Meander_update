-- ============================================
-- МИГРАЦИЯ: Система жалоб и блокировки пользователей
-- ============================================
-- Этот скрипт безопасно добавляет:
-- 1. Поле is_blocked в таблицу profiles
-- 2. Таблицу reports для хранения жалоб
-- 
-- ВАЖНО: Скрипт использует IF NOT EXISTS, поэтому безопасен для повторного запуска
-- ============================================

-- 1. Добавляем поле is_blocked в таблицу profiles (если его еще нет)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'profiles' 
        AND column_name = 'is_blocked'
    ) THEN
        ALTER TABLE profiles 
        ADD COLUMN is_blocked BOOLEAN DEFAULT FALSE;
        
        -- Обновляем существующие записи, чтобы они не были заблокированы
        UPDATE profiles SET is_blocked = FALSE WHERE is_blocked IS NULL;
        
        RAISE NOTICE 'Поле is_blocked добавлено в таблицу profiles';
    ELSE
        RAISE NOTICE 'Поле is_blocked уже существует в таблице profiles';
    END IF;
END $$;

-- 2. Создаем таблицу reports (если ее еще нет)
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    reported_type TEXT NOT NULL CHECK (reported_type IN ('quest', 'review', 'user')),
    reported_id UUID NOT NULL,
    reason TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'dismissed')),
    resolved_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Создаем индексы для оптимизации запросов (если их еще нет)
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_reported ON reports(reported_type, reported_id);
CREATE INDEX IF NOT EXISTS idx_reports_reporter ON reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_reports_created ON reports(created_at DESC);

-- 4. Добавляем комментарии к таблице и полям для документации
COMMENT ON TABLE reports IS 'Таблица для хранения жалоб пользователей на квесты, отзывы и других пользователей';
COMMENT ON COLUMN reports.reported_type IS 'Тип объекта жалобы: quest, review или user';
COMMENT ON COLUMN reports.status IS 'Статус жалобы: pending (ожидает), resolved (обработана), dismissed (отклонена)';
COMMENT ON COLUMN profiles.is_blocked IS 'Флаг блокировки пользователя. Заблокированные пользователи не могут публиковать квесты и оставлять комментарии';

-- ============================================
-- МИГРАЦИЯ ЗАВЕРШЕНА
-- ============================================
-- Проверка:
-- SELECT column_name, data_type, column_default 
-- FROM information_schema.columns 
-- WHERE table_name = 'profiles' AND column_name = 'is_blocked';
--
-- SELECT COUNT(*) FROM reports;
-- ============================================
