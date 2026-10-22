-- Обновление ограничения для таблицы reports
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_reported_type_check;
ALTER TABLE reports ADD CONSTRAINT reports_reported_type_check CHECK (reported_type IN ('quest', 'review', 'user', 'wall_post', 'wall_comment'));
