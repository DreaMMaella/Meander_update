import pool from '../config/database';

/**
 * Сервисный аккаунт команды. Системный чат — обычный диалог с ним, поэтому
 * ленте переписок, окну чата и счётчикам непрочитанного не нужна ветка
 * «а для системного по-другому». Id зафиксирован в миграции
 * `add_direct_messages.sql`.
 */
export const SYSTEM_USER_ID = '00000000-0000-0000-0000-000000000001';

/**
 * Правила доступа. Числа подобраны так, чтобы пустой аккаунт (то, чем
 * пользуются спам-боты) не прошёл, а человек, который просто зашёл поиграть,
 * прошёл после первого же вечера. Правки — здесь, а не в роутах.
 */
export const DM_RULES = {
    minAccountAgeDaysForNewThread: 3,
    minPlaytimeHoursForNewThread: 1,
    maxNewThreadsPerDay: 20,
    maxMessagesPerDay: 200,
    messageCooldownSec: 60,
    maxBodyChars: 2000,
};

/** Порог «человек в сообществе есть»: любой пункт достаточен. */
const STANDING = {
    followers: 5,
    published: 1,
    reviews: 3,
    streakDays: 5,
    playtimeHours: 3,
};

export interface Tenure {
    role: string;
    accountAgeDays: number;
    playtimeHours: number;
    followers: number;
    published: number;
    reviews: number;
    streak: number;
    isBlocked: boolean;
}

/**
 * Всё, по чему мы решаем «можно ли», одним запросом: два разных роута,
 * посчитавших стаж по-разному, — это дыра, а не опечатка.
 */
export const getTenure = async (userId: string): Promise<Tenure | null> => {
    const res = await pool.query(
        `SELECT
            p.role,
            p.is_blocked,
            EXTRACT(EPOCH FROM (NOW() - p.created_at)) / 86400 AS account_age_days,
            COALESCE(p.total_playtime_seconds, 0) / 3600.0 AS playtime_hours,
            p.streak_count,
            (SELECT COUNT(*)::int FROM user_followers f WHERE f.user_id = p.id) AS followers,
            (SELECT COUNT(*)::int FROM quests q
              WHERE q.author_id = p.id AND q.status = 'published') AS published,
            (SELECT COUNT(*)::int FROM reviews r WHERE r.author_id = p.id) AS reviews
           FROM profiles p WHERE p.id = $1`,
        [userId]
    );
    const r = res.rows[0];
    if (!r) return null;
    return {
        role: r.role || 'user',
        accountAgeDays: Number(r.account_age_days) || 0,
        playtimeHours: Number(r.playtime_hours) || 0,
        followers: r.followers || 0,
        published: r.published || 0,
        reviews: r.reviews || 0,
        streak: r.streak_count || 0,
        isBlocked: !!r.is_blocked,
    };
};

export const isStaff = (tenure: Tenure): boolean =>
    tenure.role === 'admin' || tenure.role === 'moderator';

export const hasCommunityStanding = (tenure: Tenure): boolean =>
    tenure.followers >= STANDING.followers
    || tenure.published >= STANDING.published
    || tenure.reviews >= STANDING.reviews
    || tenure.streak >= STANDING.streakDays
    || tenure.playtimeHours >= STANDING.playtimeHours;

/**
 * Правила форумов. Порог «завести своё сообщество» отделён от порога «начать
 * переписку»: форум видно всем и он живёт долго, поэтому тут важнее возраст
 * аккаунта, а не то, сколько человек наиграл.
 */
export const FORUM_RULES = {
    minAccountAgeDaysToCreate: 7,
    maxCreatedByDay: 2,
    maxNameChars: 60,
    maxDescriptionChars: 600,
    maxTitleChars: 200,
    maxBodyChars: 8000,
};

/** karma → пауза между постами и комментариями. Одна формула на стену и форумы. */
export interface KarmaLimits {
    karma: number;
    postCooldownMin: number;
    commentCooldownSec: number;
}

export const getKarmaAndLimits = async (userId: string): Promise<KarmaLimits> => {
    const profile = await pool.query('SELECT role, is_verified FROM profiles WHERE id = $1', [userId]);
    if (profile.rows.length === 0) return { karma: 0, postCooldownMin: 30, commentCooldownSec: 10 };

    const { role, is_verified: verified } = profile.rows[0];
    if (role === 'admin' || verified) return { karma: 9999, postCooldownMin: 0, commentCooldownSec: 0 };

    const followersResult = await pool.query('SELECT COUNT(*) as count FROM user_followers WHERE user_id = $1', [userId]);
    const likesResult = await pool.query('SELECT COALESCE(SUM(like_count), 0) as count FROM quests WHERE author_id = $1', [userId]);

    const karma = (parseInt(followersResult.rows[0].count, 10) || 0) * 2
        + (parseInt(likesResult.rows[0].count, 10) || 0);

    let postCooldownMin = 30;
    if (karma >= 50) postCooldownMin = 1;
    else if (karma >= 10) postCooldownMin = 10;

    const commentCooldownSec = karma >= 5 ? 0 : 10;

    return { karma, postCooldownMin, commentCooldownSec };
};

/** Форум имеет право завести тот, у кого уже есть чем заниматься в сообществе. */
export const canCreateForum = (tenure: Tenure): boolean =>
    isStaff(tenure)
    || tenure.accountAgeDays >= FORUM_RULES.minAccountAgeDaysToCreate
    || tenure.published >= STANDING.published;

export const getForumsCreatedByDay = async (userId: string): Promise<number> => {
    const res = await pool.query(
        `SELECT COUNT(*)::int AS n FROM forums
          WHERE creator_id = $1 AND created_at > date_trunc('day', NOW())`,
        [userId]
    );
    return res.rows[0]?.n || 0;
};

export interface DmPrivacy {
    mode: 'everyone' | 'standing' | 'following' | 'nobody';
    minPlaytimeHours: number;
    minAccountAgeDays: number;
}

const PRIVACY_MODES = ['everyone', 'standing', 'following', 'nobody'] as const;

/**
 * Настройка живёт в JSONB, и JSONB — это то, что туда записал клиент неделю
 * назад из другой версии приложения: режим сверяем со списком, числа
 * приводим, а не доверяем форме.
 */
export const getDmPrivacy = async (userId: string): Promise<DmPrivacy> => {
    const res = await pool.query(
        `SELECT dm_privacy FROM profiles WHERE id = $1 AND id <> $2`,
        [userId, SYSTEM_USER_ID]
    );
    const raw = res.rows[0]?.dm_privacy || {};
    const mode = (PRIVACY_MODES as readonly string[]).includes(raw.mode)
        ? raw.mode as DmPrivacy['mode']
        : 'everyone';
    const num = (v: unknown, max: number) => {
        const n = Number(v);
        return Number.isFinite(n) && n > 0 ? Math.min(n, max) : 0;
    };
    return {
        mode,
        minPlaytimeHours: num(raw.min_playtime_hours, 1000),
        minAccountAgeDays: num(raw.min_account_age_days, 3650),
    };
};

const isBlockedEitherWay = async (a: string, b: string): Promise<boolean> => {
    const res = await pool.query(
        `SELECT 1 FROM user_blocks
          WHERE (user_id = $1 AND blocked_id = $2)
             OR (user_id = $2 AND blocked_id = $1)
          LIMIT 1`,
        [a, b]
    );
    return res.rows.length > 0;
};

const isFollowing = async (followedId: string, followerId: string): Promise<boolean> => {
    const res = await pool.query(
        `SELECT 1 FROM user_followers WHERE user_id = $1 AND follower_id = $2 LIMIT 1`,
        [followedId, followerId]
    );
    return res.rows.length > 0;
};

export interface Gate {
    ok: boolean;
    status: number;
    error?: string;
}

const deny = (status: number, error: string): Gate => ({ ok: false, status, error });

/**
 * Ответил ли собеседник в этом диалоге. Пока он молчит, диалог — моё решение,
 * и пороги остаются в силе: иначе спам-бот мог бы открыть тред, дописать в
 * пустоту и считать ограничения снятыми.
 */
export const hasPeerReply = async (threadId: string, me: string): Promise<boolean> => {
    const res = await pool.query(
        `SELECT 1 FROM dm_messages
          WHERE thread_id = $1 AND sender_id <> $2 AND deleted_at IS NULL
          LIMIT 1`,
        [threadId, me]
    );
    return res.rows.length > 0;
};

/**
 * Может ли `senderId` написать `recipientId`. Проверяется в этом порядке, и
 * порядок важен: блок и «закрыто» — отказ без обсуждения, а все пороги
 * отменяются, когда переписку поддержал получатель.
 */
export const checkDmPermission = async (
    senderId: string,
    recipientId: string,
    peerReplied: boolean
): Promise<Gate> => {
    if (recipientId === SYSTEM_USER_ID) {
        return deny(403, 'Это аккаунт команды — он не читает личные сообщения.');
    }

    if (await isBlockedEitherWay(senderId, recipientId)) {
        return deny(403, 'Вы не можете писать друг другу.');
    }

    const [sender, recipient] = await Promise.all([
        getTenure(senderId),
        getTenure(recipientId),
    ]);
    if (!sender) return deny(401, 'Профиль не найден');
    if (!recipient) return deny(404, 'Получатель не найден');
    if (sender.isBlocked) return deny(403, 'Профиль заблокирован');
    if (recipient.isBlocked) return deny(403, 'Профиль получателя недоступен');

    const privacy = await getDmPrivacy(recipientId);
    // «Закрыть личку» — выбор человека, он действует и на старые переписки.
    if (privacy.mode === 'nobody') {
        return deny(403, 'Человек закрыл личные сообщения.');
    }

    // Остальное — про то, кому можно дописать первому. Как только собеседник
    // ответил, разговор стал его выбором, и посреди переписки человек не должен
    // натыкаться на «нельзя».
    if (!peerReplied) {
        if (privacy.mode === 'following' && !await isFollowing(recipientId, senderId)) {
            return deny(403, 'Получатель принимает сообщения только от тех, на кого подписан.');
        }
        if (privacy.mode === 'standing' && !hasCommunityStanding(sender)) {
            return deny(403, 'Получатель принимает сообщения только от участников с историей в сообществе.');
        }
        if (privacy.minAccountAgeDays > 0 && sender.accountAgeDays < privacy.minAccountAgeDays) {
            return deny(403, `Аккаунту должно быть не меньше ${privacy.minAccountAgeDays} дней.`);
        }
        if (privacy.minPlaytimeHours > 0 && sender.playtimeHours < privacy.minPlaytimeHours) {
            return deny(403, `Нужно наиграть не меньше ${privacy.minPlaytimeHours} ч.`);
        }

        // Новый диалог с незнакомым человеком — самое дешёвое место для рассылки.
        if (!isStaff(sender) && !hasCommunityStanding(sender)) {
            const oldEnough = sender.accountAgeDays >= DM_RULES.minAccountAgeDaysForNewThread;
            const playedEnough = sender.playtimeHours >= DM_RULES.minPlaytimeHoursForNewThread;
            if (!oldEnough && !playedEnough) {
                return deny(403,
                    `Начать переписку можно через ${DM_RULES.minAccountAgeDaysForNewThread} дня после регистрации `
                    + `или наиграв ${DM_RULES.minPlaytimeHoursForNewThread} ч в квестах.`);
            }
        }
    }

    return { ok: true, status: 200 };
};

/** Суточная активность отправителя: новые диалоги и всего сообщений. */
export const getDmUsageToday = async (userId: string): Promise<{ threads: number; messages: number }> => {
    const res = await pool.query(
        `SELECT
            (SELECT COUNT(DISTINCT m.thread_id)::int FROM dm_messages m
              JOIN dm_threads t ON t.id = m.thread_id
              WHERE m.sender_id = $1 AND m.created_at > date_trunc('day', NOW())
                AND t.user_a <> $2) AS threads,
            (SELECT COUNT(*)::int FROM dm_messages
              WHERE sender_id = $1 AND created_at > date_trunc('day', NOW())) AS messages`,
        [userId, SYSTEM_USER_ID]
    );
    const r = res.rows[0] || { threads: 0, messages: 0 };
    return { threads: r.threads || 0, messages: r.messages || 0 };
};

/**
 * Секунды, которые осталось подождать до следующего сообщения в тред.
 * Кулдаун нужен тому, кто пишет в пустоту; в разговорившемся диалоге задержка
 * выглядела бы как отказ, поэтому там её не считают.
 */
export const secondsUntilNextMessage = async (
    threadId: string,
    userId: string,
    tenure: Tenure
): Promise<number> => {
    if (isStaff(tenure) || hasCommunityStanding(tenure)) return 0;

    const res = await pool.query(
        `SELECT EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))::int AS waited
           FROM dm_messages
          WHERE thread_id = $1 AND sender_id = $2 AND deleted_at IS NULL`,
        [threadId, userId]
    );
    const waited = res.rows[0]?.waited;
    if (waited == null) return 0;
    return Math.max(0, DM_RULES.messageCooldownSec - waited);
};
