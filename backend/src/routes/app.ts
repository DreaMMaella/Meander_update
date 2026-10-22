import { Router, Request, Response } from 'express';
import pool from '../config/database';

const router = Router();

// ============================================================================
//  PARTNER BANNERS
// ============================================================================
// Публичный список активных партнёрских/рекламных баннеров для маркета.
// Кэшируется на 5 минут. Источник: таблица partner_banners.
//
// Формат ответа — массив объектов с полями, которые ждёт фронт
// (apps/main_app/lib/features/market/widgets/partner_banner.dart).
// ============================================================================
router.get('/partner-banners', async (_req: Request, res: Response) => {
  try {
    const result = await pool.query(
      `SELECT id, title, subtitle, cta_text, url, image_url,
              icon, tint_color, slots, pinned, sort_order
         FROM partner_banners
        WHERE is_active = TRUE
        ORDER BY sort_order ASC, created_at ASC`
    );

    const banners = result.rows.map((row) => ({
      id: row.id,
      title: row.title,
      subtitle: row.subtitle,
      ctaText: row.cta_text,
      url: row.url,
      imageUrl: row.image_url || null,
      icon: row.icon || 'campaign',
      tintColor: row.tint_color || '#6750A4',
      slots: Array.isArray(row.slots) ? row.slots : [],
      pinned: !!row.pinned,
    }));

    // Кэш на 5 минут на CDN/прокси, 1 минута в браузере.
    res.set('Cache-Control', 'public, max-age=60, s-maxage=300');
    res.json(banners);
  } catch (err) {
    console.error('Partner banners fetch error:', err);
    // Возвращаем пустой массив — фронт сам подставит fallback.
    res.status(200).json([]);
  }
});

router.get('/version/check', async (req: Request, res: Response) => {
  try {
    const buildNumber = parseInt(req.query.build_number as string, 10);
    const platform = (req.query.platform as string) || 'all';

    if (isNaN(buildNumber)) {
      return res.status(400).json({ error: 'build_number is required' });
    }

    const result = await pool.query(
      `SELECT version, build_number, is_critical, download_url, changelog
       FROM app_versions
       WHERE platform IN ($1, 'all')
         AND is_active = true
         AND build_number > $2
       ORDER BY build_number DESC
       LIMIT 1`,
      [platform, buildNumber]
    );

    if (result.rows.length === 0) {
      return res.json({ hasUpdate: false });
    }

    const row = result.rows[0];
    res.json({
      hasUpdate: true,
      isCritical: row.is_critical,
      latestVersion: row.version,
      latestBuild: row.build_number,
      downloadUrl: row.download_url || '',
      changelog: row.changelog || '',
    });
  } catch (err) {
    console.error('Version check error:', err);
    res.status(500).json({ hasUpdate: false });
  }
});

export default router;
