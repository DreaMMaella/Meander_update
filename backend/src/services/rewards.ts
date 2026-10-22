import pool from '../config/database';
import { grantCosmetics } from './cosmetics';

// ============================================================================
//  НАГРАДЫ ЗА АКТИВНОСТЬ
//
//  Оформления выдаются не за покупки, а за то, что человек реально делает в
//  приложении. Метрики считаются ТОЛЬКО из серверных фактов: стрик считает
//  сервер по датам, игровой день берётся из `playtime_daily` (куда секунды
//  попадают через бюджет синка), отзывы — только одобренные и только на
//  чужих квестах, скачивания — только чужих. Клиент не сообщает ничего, из
//  чего что-то считается, поэтому накрутить выдачу нельзя.
//
//  Пороги специально медленные: награда должна означать «человек здесь уже
//  месяц», а не «человек сегодня не закрыл приложение».
// ============================================================================

export type RewardMetric = 'streak' | 'game_days' | 'reviews' | 'downloads';

export interface RewardRule {
    id: string;
    metric: RewardMetric;
    /** Сколько нужно, чтобы награда открылась. */
    threshold: number;
    title: string;
    hint: string;
    /** Предметы каталога; выдаются бессрочно. */
    cosmetics: string[];
}

/** Секунд в сутках достаточно, чтобы день засчитали как игровой. */
export const GAME_DAY_MIN_SECONDS = 600;

export const REWARD_RULES: readonly RewardRule[] = [
    // --- Стрик: заходов подряд -------------------------------------------
    {
        id: 'streak_7',
        metric: 'streak',
        threshold: 7,
        title: 'Неделя рядом',
        hint: '7 дней захода подряд',
        cosmetics: ['neon_pulse'],
    },
    {
        id: 'streak_30',
        metric: 'streak',
        threshold: 30,
        title: 'Месяц без пропусков',
        hint: '30 дней захода подряд',
        cosmetics: ['aurora_drift', 'frost_blue'],
    },
    {
        id: 'streak_100',
        metric: 'streak',
        threshold: 100,
        title: 'Сотый день',
        hint: '100 дней захода подряд',
        cosmetics: ['gold_laurel', 'royal_gold'],
    },

    // --- Игровые дни: не менее 10 минут в сутки --------------------------
    {
        id: 'game_days_10',
        metric: 'game_days',
        threshold: 10,
        title: 'Десять игровых дней',
        hint: '10 дней, где вы наиграли хотя бы 10 минут',
        cosmetics: ['fireflies'],
    },
    {
        id: 'game_days_50',
        metric: 'game_days',
        threshold: 50,
        title: 'Завсегдатай',
        hint: '50 игровых дней',
        cosmetics: ['midnight_surf', 'sunset_glow'],
    },
    {
        id: 'game_days_180',
        metric: 'game_days',
        threshold: 180,
        title: 'Полгода в пути',
        hint: '180 игровых дней',
        cosmetics: ['starfield', 'pulsar'],
    },

    // --- Отзывы: только одобренные и только на чужих квестах -------------
    {
        id: 'reviews_5',
        metric: 'reviews',
        threshold: 5,
        title: 'Голос сообщества',
        hint: '5 одобренных отзывов на чужих квестах',
        cosmetics: ['toxic_lime'],
    },
    {
        id: 'reviews_25',
        metric: 'reviews',
        threshold: 25,
        title: 'Разбор полётов',
        hint: '25 одобренных отзывов',
        cosmetics: ['glitch_ring', 'magenta_neon'],
    },

    // --- Скачивания: чужие квесты, свои не считаются ---------------------
    {
        id: 'downloads_15',
        metric: 'downloads',
        threshold: 15,
        title: 'Коллекционер',
        hint: '15 скачанных чужих квестов',
        cosmetics: ['holo_band'],
    },
    {
        id: 'downloads_60',
        metric: 'downloads',
        threshold: 60,
        title: 'Архив',
        hint: '60 скачанных чужих квестов',
        cosmetics: ['solar_corona', 'ember_orbit'],
    },
];

export interface RewardProgress {
    rule: RewardRule;
    current: number;
    done: boolean;
    /** Дата выдачи из журнала; null — награда ещё не получена. */
    grantedAt: string | null;
}

export type Metrics = Record<RewardMetric, number>;

const METRIC_IDS: RewardMetric[] = ['streak', 'game_days', 'reviews', 'downloads'];

/**
 * Все четыре метрики одним запросом. Каждое подмножество — своя правда из
 * своей таблицы, поэтому расхождение (например, пустой `playtime_daily` у
 * аккаунта до миграции) даёт ноль, а не ошибку.
 */
export async function readMetrics(userId: string): Promise<Metrics> {
    const res = await pool.query(
        `WITH m_game AS (
             SELECT count(*)::int AS n
               FROM (SELECT day FROM playtime_daily
                      WHERE user_id = $1
                      GROUP BY day
                     HAVING sum(seconds) >= $2) d
         ),
         m_reviews AS (
             SELECT count(*)::int AS n
               FROM reviews r
               JOIN quests q ON q.id = r.quest_id
              WHERE r.author_id = $1
                AND r.status = 'approved'
                AND q.author_id <> $1
                AND length(trim(r.text_content)) >= 20
         ),
         m_downloads AS (
             SELECT count(*)::int AS n
               FROM quest_downloads d
               JOIN quests q ON q.id = d.quest_id
              WHERE d.user_id = $1 AND q.author_id <> $1
         )
         SELECT COALESCE(p.streak_count, 0)::int AS streak,
                g.n AS game_days,
                r.n AS reviews,
                dl.n AS downloads
           FROM profiles p
           CROSS JOIN m_game g
           CROSS JOIN m_reviews r
           CROSS JOIN m_downloads dl
          WHERE p.id = $1`,
        [userId, GAME_DAY_MIN_SECONDS]
    );
    const row = res.rows[0];
    if (!row) return { streak: 0, game_days: 0, reviews: 0, downloads: 0 };
    return {
        streak: Number(row.streak) || 0,
        game_days: Number(row.game_days) || 0,
        reviews: Number(row.reviews) || 0,
        downloads: Number(row.downloads) || 0,
    };
}

/**
 * Выдаёт всё, что уже открыто и ещё не выдано. Возвращает id правил, по
 * которым прошла реальная выдача — повторный вызов ничего не делает, пока
 * метрика не перешагнула новый порог.
 *
 * Порядок важен: сначала журнал (`ON CONFLICT DO NOTHING`), и только если
 * строка вставила — право на предмет. Иначе два параллельных вызова
 * выдали бы один и тот же скин дважды.
 */
export async function grantDueRewards(userId: string): Promise<string[]> {
    const [metrics, already] = await Promise.all([
        readMetrics(userId),
        pool.query(
            `SELECT rule_id FROM reward_grants WHERE user_id = $1`,
            [userId]
        ),
    ]);
    const held = new Set(already.rows.map((r: any) => r.rule_id as string));
    const pending = REWARD_RULES.filter(
        (r) => !held.has(r.id) && metrics[r.metric] >= r.threshold
    );
    if (pending.length === 0) return [];

    const awarded: string[] = [];
    for (const rule of pending) {
        const inserted = await pool.query(
            `INSERT INTO reward_grants (user_id, rule_id, cosmetic_ids)
             VALUES ($1, $2, $3)
             ON CONFLICT (user_id, rule_id) DO NOTHING
             RETURNING rule_id`,
            [userId, rule.id, rule.cosmetics]
        );
        if (inserted.rows.length === 0) continue;

        await grantCosmetics(userId, rule.cosmetics, {
            days: null,
            source: 'reward',
            reason: rule.id,
        });
        awarded.push(rule.id);
    }

    if (awarded.length > 0) {
        console.log(`🎁 Награды выданы ${userId}: ${awarded.join(', ')}`);
    }
    return awarded;
}

/**
 * Метрика как SQL-запрос на ВСЕХ пользователей: `user_id`+`value`. Порог —
 * параметр, `$1` во всех четырёх; у `game_days` добавляется `$2` — порог
 * игрового дня. Номеров «на вырост» здесь быть не может: node-postgres не
 * сообщает серверу типы параметров, Postgres выводит их из текста запроса, и
 * на неупомянутый `$3` отвечает 42P18 — вся лестница встала ровно на этом.
 */
const QUALIFIED_SQL: Record<RewardMetric, string> = {
    streak: `SELECT id AS user_id, COALESCE(streak_count, 0) AS value
               FROM profiles WHERE COALESCE(streak_count, 0) >= $1`,
    game_days: `SELECT user_id, count(*) AS value
                  FROM (SELECT user_id, day FROM playtime_daily
                         GROUP BY user_id, day
                        HAVING sum(seconds) >= $2) d
                 GROUP BY user_id
                HAVING count(*) >= $1`,
    reviews: `SELECT r.author_id AS user_id, count(*) AS value
                FROM reviews r
                JOIN quests q ON q.id = r.quest_id
               WHERE r.status = 'approved'
                 AND q.author_id <> r.author_id
                 AND length(trim(r.text_content)) >= 20
               GROUP BY r.author_id
              HAVING count(*) >= $1`,
    downloads: `SELECT d.user_id, count(*) AS value
                  FROM quest_downloads d
                  JOIN quests q ON q.id = d.quest_id
                 WHERE d.user_id IS NOT NULL AND q.author_id <> d.user_id
                 GROUP BY d.user_id
                HAVING count(*) >= $1`,
};

/**
 * Общая выдача: журнал первым, предметы — только тем, у кого строка в журнал
 * реально вставилась. Одна выборка на правило вместо обхода всех пользователей:
 * на проде это тысячи строк в `profiles`, а правил — единицы.
 */
async function grantRuleToQualifyingUsers(rule: RewardRule): Promise<number> {
    const metricParams: unknown[] = [rule.threshold];
    if (rule.metric === 'game_days') metricParams.push(GAME_DAY_MIN_SECONDS);

    const qualified = await pool.query(QUALIFIED_SQL[rule.metric], metricParams);
    if (qualified.rows.length === 0) return 0;

    const inserted = await pool.query(
        `INSERT INTO reward_grants (user_id, rule_id, cosmetic_ids)
         SELECT u, $2::text, $3::text[]
           FROM unnest($1::uuid[]) AS t(u)
         ON CONFLICT (user_id, rule_id) DO NOTHING
         RETURNING user_id`,
        [qualified.rows.map((r: any) => r.user_id as string), rule.id, rule.cosmetics]
    );

    for (const row of inserted.rows) {
        await grantCosmetics(row.user_id as string, rule.cosmetics, {
            days: null,
            source: 'reward',
            reason: rule.id,
        });
    }
    return inserted.rowCount ?? 0;
}

/**
 * Полный обход лестницы. Зовётся по таймеру; возвращает число выдач, чтобы в
 * логах было видно, что механизм жив.
 */
export async function sweepRewardLadder(): Promise<number> {
    let total = 0;
    for (const rule of REWARD_RULES) {
        try {
            total += await grantRuleToQualifyingUsers(rule);
        } catch (e) {
            // Правило не должно ронять остальные: у него могли кончиться
            // права на доступ к таблице, а награды ждут остальных людей.
            console.error(`reward rule ${rule.id} failed:`, e);
        }
    }
    if (total > 0) console.log(`🎁 Наград выдано: ${total}`);
    return total;
}

/** Прогресс по всем правилам — то, что видит экран «Награды». */
export async function rewardProgress(userId: string): Promise<RewardProgress[]> {
    const [metrics, granted] = await Promise.all([
        readMetrics(userId),
        pool.query(
            `SELECT rule_id, granted_at FROM reward_grants WHERE user_id = $1`,
            [userId]
        ),
    ]);
    const byRule = new Map(
        granted.rows.map((r: any) => [r.rule_id as string, new Date(r.granted_at).toISOString()])
    );

    return REWARD_RULES.map((rule) => ({
        rule,
        current: metrics[rule.metric],
        done: metrics[rule.metric] >= rule.threshold,
        grantedAt: byRule.get(rule.id) ?? null,
    }));
}

/** Периодический обход лестницы. Первый запуск — сразу после старта сервера. */
export const startRewardSweep = (intervalMs: number = 10 * 60 * 1000) => {
    const run = async () => {
        try {
            await sweepRewardLadder();
        } catch (e) {
            console.error('Error in reward sweep:', e);
        }
    };
    console.log(`🎁 Reward sweep started (every ${intervalMs / 60000} min)`);
    void run();
    setInterval(run, intervalMs);
};

export const METRIC_LABELS: Record<RewardMetric, string> = {
    streak: 'дней подряд',
    game_days: 'игровых дней',
    reviews: 'отзывов',
    downloads: 'квестов',
};

/** Только для логов/тестов: список известных метрик. */
export const ALL_METRICS = METRIC_IDS;
