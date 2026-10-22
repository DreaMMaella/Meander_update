import { Router, Response } from 'express';
import pool from '../config/database';
import authMiddleware, { AuthRequest } from '../middleware/auth';
import { validate as uuidValidate } from 'uuid';

const router = Router();

router.get('/', authMiddleware, async (req: AuthRequest, res: Response) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Unauthorized' });

  const archived = req.query.archived === 'true';
  const limit = Math.min(Math.max(parseInt((req.query.limit as string) || '50', 10), 1), 200);
  const offset = Math.max(parseInt((req.query.offset as string) || '0', 10), 0);

  try {
    const result = await pool.query(
      `SELECT
          n.id,
          n.user_id,
          n.actor_id,
          n.type,
          n.quest_id,
          n.review_id,
          n.payload,
          n.payload->>'postId' AS post_id,
          n.created_at,
          n.read_at,
          n.archived_at,
          a.full_name AS actor_name,
          a.avatar_url AS actor_avatar_url,
          a.cosmetics ->> 'name_style' AS actor_name_style, a.cosmetics AS actor_cosmetics,
          a.cosmetics ->> 'avatar_frame' AS actor_avatar_frame,
          q.title AS quest_title,
          q.preview_image_url AS quest_preview_image_url
       FROM notifications n
       LEFT JOIN profiles a ON a.id = n.actor_id
       LEFT JOIN quests q ON q.id = n.quest_id
       WHERE n.user_id = $1
         AND ${archived ? 'n.archived_at IS NOT NULL' : 'n.archived_at IS NULL'}
       ORDER BY n.created_at DESC
       LIMIT $2 OFFSET $3`,
      [userId, limit, offset],
    );

    res.json(result.rows);
  } catch (e) {
    console.error('Notifications fetch error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

router.get('/unread-count', authMiddleware, async (req: AuthRequest, res: Response) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Unauthorized' });

  try {
    const result = await pool.query(
      `SELECT COUNT(*)::int AS count
       FROM notifications
       WHERE user_id = $1
         AND archived_at IS NULL
         AND read_at IS NULL`,
      [userId],
    );
    res.json({ count: result.rows[0]?.count ?? 0 });
  } catch (e) {
    console.error('Unread count error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

router.post('/:id/read', authMiddleware, async (req: AuthRequest, res: Response) => {
  const userId = req.user?.id;
  const { id } = req.params;
  if (!userId) return res.status(401).json({ error: 'Unauthorized' });
  if (!uuidValidate(id)) return res.status(400).json({ error: 'Invalid ID format' });

  try {
    await pool.query(
      'UPDATE notifications SET read_at = COALESCE(read_at, NOW()) WHERE id = $1 AND user_id = $2',
      [id, userId],
    );
    res.json({ success: true });
  } catch (e) {
    console.error('Notification read error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

router.post('/:id/archive', authMiddleware, async (req: AuthRequest, res: Response) => {
  const userId = req.user?.id;
  const { id } = req.params;
  if (!userId) return res.status(401).json({ error: 'Unauthorized' });
  if (!uuidValidate(id)) return res.status(400).json({ error: 'Invalid ID format' });

  try {
    // «Просмотрено» и «в архиве» для клиента — одно событие: лента помечает
    // строку seen-ом именно архивацией (VisibilityDetector), а `/read` не
    // вызывает никто. Без штампа read_at tile всю жизнь рисует точку
    // непрочитанного — и в архиве, который в UI называется «прочитанные».
    await pool.query(
      'UPDATE notifications SET archived_at = NOW(), read_at = COALESCE(read_at, NOW()) WHERE id = $1 AND user_id = $2',
      [id, userId],
    );
    res.json({ success: true });
  } catch (e) {
    console.error('Notification archive error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

export default router;
