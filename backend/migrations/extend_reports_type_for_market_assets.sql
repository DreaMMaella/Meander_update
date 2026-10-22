-- Жалобы на ресурсы и треки маркета.
-- Клиент hub'а отправляет reported_type='asset'/'music' (asset_details_screen.dart,
-- music_details_screen.dart, preset_details_screen.dart), но CHECK допускал только
-- пять типов из update_reports_type_check.sql — вставка падала бы на 23514, даже если
-- бы маршрутный allow-list её пропустил.
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_reported_type_check;
ALTER TABLE reports ADD CONSTRAINT reports_reported_type_check
    CHECK (reported_type IN ('quest', 'review', 'user', 'wall_post', 'wall_comment', 'asset', 'music'));
