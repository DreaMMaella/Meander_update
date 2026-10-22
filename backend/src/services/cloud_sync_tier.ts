import pool from '../config/database';

/**
 * Meander Cloud — Tier configuration & auto-recompute service.
 *
 * Tiers (см. migration_cloud_sync.sql, CHECK constraint):
 *   none    — нет доступа к облаку
 *   starter — пользователь освоился, есть лёгкое хранилище
 *   free    — автор: опубликован хотя бы 1 модерированный квест
 *   creator — известный автор: ≥3 квестов / верификация / 50+ лайков / 50+ подписчиков
 *   pro     — выдаётся вручную (подписка, донат, промокод)
 *   admin   — безлимит
 *
 * Авто-пересчёт допускает только переходы между {none → starter → free → creator}.
 * pro / admin никогда не понижаются автоматически — только вручную через granted_reason.
 */

export type TierName =
    | 'none'
    | 'starter'
    | 'free'
    | 'creator'
    | 'pro'
    | 'admin';

export interface TierConfig {
    name: TierName;
    /** Лимит на user-квесты (общий размер на диске сервера, байты). */
    maxBytes: number;
    /** Сколько всего записей в облаке: user + market_ref. */
    maxQuests: number;
    /** Максимальный размер одного .mnd. */
    maxQuestBytes: number;
    /** Сколько market_ref-записей разрешено (дёшево, поэтому лимит щедрее). */
    maxRefs: number;
}

const MB = 1024 * 1024;
const GB = 1024 * MB;

export const TIERS: Record<TierName, TierConfig> = {
    none: {
        name: 'none',
        maxBytes: 0,
        maxQuests: 0,
        maxQuestBytes: 0,
        maxRefs: 0,
    },
    starter: {
        name: 'starter',
        maxBytes: 25 * MB,
        maxQuests: 3,
        maxQuestBytes: 5 * MB,
        maxRefs: 10,
    },
    free: {
        name: 'free',
        maxBytes: 100 * MB,
        maxQuests: 10,
        maxQuestBytes: 15 * MB,
        maxRefs: 50,
    },
    creator: {
        name: 'creator',
        maxBytes: 500 * MB,
        maxQuests: 50,
        maxQuestBytes: 30 * MB,
        maxRefs: 200,
    },
    pro: {
        name: 'pro',
        maxBytes: 2 * GB,
        maxQuests: 200,
        maxQuestBytes: 100 * MB,
        maxRefs: 2000,
    },
    admin: {
        name: 'admin',
        maxBytes: Number.MAX_SAFE_INTEGER,
        maxQuests: 1_000_000,
        maxQuestBytes: 1 * GB,
        maxRefs: 1_000_000,
    },
};

// ============================================================================
//  Метрики пользователя для расчёта auto-tier
// ============================================================================

interface UserMetrics {
    isVerified: boolean;
    isAdmin: boolean;
    isBlocked: boolean;
    accountAgeDays: number;
    publishedCount: number; // квестов со статусом 'published'
    totalLikes: number;
    followersCount: number;
    /** Любая «активность»: лайк/отзыв/публикация — нужно для starter. */
    hasAnyActivity: boolean;
}

async function loadUserMetrics(userId: string): Promise<UserMetrics | null> {
    const profileRes = await pool.query(
        `SELECT id, role, is_verified, is_blocked, created_at
           FROM profiles WHERE id = $1`,
        [userId],
    );
    if ((profileRes.rowCount ?? 0) === 0) return null;
    const p = profileRes.rows[0];

    const ageMs = Date.now() - new Date(p.created_at).getTime();
    const ageDays = Math.max(0, Math.floor(ageMs / (1000 * 60 * 60 * 24)));

    const aggRes = await pool.query(
        `SELECT
            COALESCE((
                SELECT COUNT(*) FROM quests
                 WHERE author_id = $1 AND status = 'published'
            ), 0)::int AS published_count,
            COALESCE((
                SELECT SUM(like_count) FROM quests
                 WHERE author_id = $1 AND status = 'published'
            ), 0)::bigint AS total_likes,
            COALESCE((
                SELECT COUNT(*) FROM user_followers
                 WHERE user_id = $1
            ), 0)::int AS followers_count,
            COALESCE((
                SELECT COUNT(*) FROM quest_votes
                 WHERE user_id = $1 LIMIT 1
            ), 0)::int AS any_vote,
            COALESCE((
                SELECT COUNT(*) FROM reviews
                 WHERE author_id = $1 LIMIT 1
            ), 0)::int AS any_review`,
        [userId],
    );
    const a = aggRes.rows[0];

    const publishedCount = Number(a.published_count) || 0;
    return {
        isVerified: p.is_verified === true,
        isAdmin: p.role === 'admin',
        isBlocked: p.is_blocked === true,
        accountAgeDays: ageDays,
        publishedCount,
        totalLikes: Number(a.total_likes) || 0,
        followersCount: Number(a.followers_count) || 0,
        hasAnyActivity:
            publishedCount > 0 ||
            Number(a.any_vote) > 0 ||
            Number(a.any_review) > 0,
    };
}

// ============================================================================
//  Расчёт auto-tier
// ============================================================================

function computeAutoTier(m: UserMetrics): TierName {
    if (m.isBlocked) return 'none';
    if (m.isAdmin) return 'admin';

    // creator: «известный автор»
    if (
        m.publishedCount >= 3 ||
        m.isVerified ||
        m.totalLikes >= 50 ||
        m.followersCount >= 50
    ) {
        return 'creator';
    }

    // free: «обычный автор»
    if (m.publishedCount >= 1) return 'free';

    // starter: «закрепился в платформе»
    if (m.accountAgeDays >= 7 && m.hasAnyActivity) return 'starter';

    return 'none';
}

// ============================================================================
//  Применение tier к квоте
// ============================================================================

/**
 * Пересчитать tier пользователя.
 * - Если текущий tier равен 'pro' или 'admin' с granted_reason != 'auto' —
 *   не понижаем (это «ручной» tier).
 * - Иначе вычисляем по метрикам и применяем.
 * Возвращает финальный tier.
 */
export async function recomputeTier(userId: string): Promise<TierName> {
    const cur = await pool.query(
        `SELECT tier, granted_reason FROM cloud_sync_quotas WHERE user_id = $1`,
        [userId],
    );

    // Если выдано вручную или подпиской — не трогаем
    if ((cur.rowCount ?? 0) > 0) {
        const row = cur.rows[0];
        const reason = (row.granted_reason || 'auto') as string;
        if (
            (row.tier === 'pro' || row.tier === 'admin') &&
            reason !== 'auto'
        ) {
            return row.tier as TierName;
        }
    }

    const metrics = await loadUserMetrics(userId);
    if (!metrics) return 'none';

    const target = computeAutoTier(metrics);
    await applyTier(userId, target, 'auto', null);
    return target;
}

/**
 * Принудительная выдача tier (admin / promo / subscription).
 */
export async function grantTier(
    userId: string,
    tier: TierName,
    reason: string,
    grantedBy: string | null = null,
    expiresAt: Date | null = null,
): Promise<void> {
    await applyTier(userId, tier, reason, grantedBy, expiresAt);
}

async function applyTier(
    userId: string,
    tier: TierName,
    reason: string,
    grantedBy: string | null,
    expiresAt: Date | null = null,
): Promise<void> {
    const cfg = TIERS[tier];
    const grantedAt = new Date();

    const beforeRes = await pool.query(
        `SELECT tier FROM cloud_sync_quotas WHERE user_id = $1`,
        [userId],
    );
    const before = (beforeRes.rowCount ?? 0) > 0 ? (beforeRes.rows[0].tier as TierName) : null;

    await pool.query(
        `INSERT INTO cloud_sync_quotas (
            user_id, tier, max_bytes, max_quests, max_quest_bytes, max_refs,
            granted_reason, granted_by, granted_at, expires_at, updated_at
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, now())
         ON CONFLICT (user_id) DO UPDATE SET
            tier            = EXCLUDED.tier,
            max_bytes       = EXCLUDED.max_bytes,
            max_quests      = EXCLUDED.max_quests,
            max_quest_bytes = EXCLUDED.max_quest_bytes,
            max_refs        = EXCLUDED.max_refs,
            granted_reason  = EXCLUDED.granted_reason,
            granted_by      = EXCLUDED.granted_by,
            granted_at      = EXCLUDED.granted_at,
            expires_at      = EXCLUDED.expires_at,
            updated_at      = now()`,
        [
            userId,
            cfg.name,
            cfg.maxBytes,
            cfg.maxQuests,
            cfg.maxQuestBytes,
            cfg.maxRefs,
            reason,
            grantedBy,
            grantedAt,
            expiresAt,
        ],
    );

    // Аудит
    if (before !== tier) {
        try {
            await pool.query(
                `INSERT INTO cloud_sync_audit (user_id, action, detail)
                 VALUES ($1, 'tier_change', $2::jsonb)`,
                [
                    userId,
                    JSON.stringify({ from: before, to: tier, reason }),
                ],
            );
        } catch (_) {
            // best-effort
        }
    }

    // Триггер уже пересчитает used_*, но если строки в quests не было — гарантия:
    await pool.query(
        `SELECT recompute_cloud_sync_usage($1::uuid)`,
        [userId],
    );
}

// ============================================================================
//  Подсказки пользователю «как получить больше места»
// ============================================================================

export interface UpgradeHint {
    target: TierName;
    text: string;
    progress?: number; // 0..1
}

export async function buildUpgradeHints(
    userId: string,
    currentTier: TierName,
): Promise<UpgradeHint[]> {
    const metrics = await loadUserMetrics(userId);
    if (!metrics) return [];

    const hints: UpgradeHint[] = [];

    if (currentTier === 'none') {
        if (metrics.accountAgeDays < 7) {
            hints.push({
                target: 'starter',
                text: `Аккаунту ${metrics.accountAgeDays} дн. — через ${7 - metrics.accountAgeDays} дн. получите 25 МБ.`,
                progress: metrics.accountAgeDays / 7,
            });
        }
        if (!metrics.hasAnyActivity) {
            hints.push({
                target: 'starter',
                text: 'Поставьте лайк, оставьте отзыв или опубликуйте квест.',
            });
        }
        hints.push({
            target: 'free',
            text: 'Опубликуйте свой первый квест — 100 МБ.',
        });
    }

    if (currentTier === 'starter' || currentTier === 'none') {
        if (metrics.publishedCount === 0) {
            hints.push({
                target: 'free',
                text: 'Опубликуйте 1 квест — получите 100 МБ.',
            });
        }
    }

    if (currentTier === 'free' || currentTier === 'starter') {
        const need = Math.max(0, 3 - metrics.publishedCount);
        if (need > 0) {
            hints.push({
                target: 'creator',
                text: `Опубликуйте ещё ${need} квест(а) — 500 МБ.`,
                progress: metrics.publishedCount / 3,
            });
        }
        const needLikes = Math.max(0, 50 - metrics.totalLikes);
        if (needLikes > 0) {
            hints.push({
                target: 'creator',
                text: `Соберите ещё ${needLikes} лайков на квестах — 500 МБ.`,
                progress: Math.min(1, metrics.totalLikes / 50),
            });
        }
        const needFollowers = Math.max(0, 50 - metrics.followersCount);
        if (needFollowers > 0) {
            hints.push({
                target: 'creator',
                text: `Наберите ещё ${needFollowers} подписчиков — 500 МБ.`,
                progress: Math.min(1, metrics.followersCount / 50),
            });
        }
        if (!metrics.isVerified) {
            hints.push({
                target: 'creator',
                text: 'Пройдите верификацию профиля — 500 МБ.',
            });
        }
    }

    if (currentTier === 'creator') {
        hints.push({
            target: 'pro',
            text: 'Pro доступен через подписку или промокод — 2 ГБ.',
        });
    }

    return hints;
}