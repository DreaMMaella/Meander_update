import pool from '../config/database';
import { GAME_DAY_MIN_SECONDS } from './rewards';

// ============================================================================
//  АНАЛИТИКА ОДНОГО КВЕСТА
//
//  «Сколько скачали» из `quests.downloads_count` автору мало: оно не отвечает
//  ни на «почему не качают», ни на «что дала вчера ссылка в сообществе».
//  Поэтому здесь всё разложено по дням и по двум соседним окнам — текущему и
//  предыдущему той же длины, чтобы рост был числом, а не воспоминанием.
//
//  Сутки считаем в UTC: `playtime_daily` и `quest_views` пишутся по UTC-дате,
//  которую вычисляет сервер Node, и сравнивать её с сутками из `timestamptz`
//  в поясе сессии — значит получить два разных графика на одних данных.
//  Отсюда `AT TIME ZONE 'UTC'` в каждом разрезе по датам и границы окон в
//  формате `...T00:00:00Z`.
//
//  Отдельный график «лайки по дням» честно опирается на `quest_votes.created_at`,
//  а его сервер перезаписывает при смене голоса. То есть снятый сегодня лайк
//  уходит из вчерашней колонки. Это заметно, но переписывать таблицу ради
//  одного ряда не стоило.
// ============================================================================

const DAY_MS = 86_400_000;

/**
 * Область среза. Один и тот же текст запроса на двух областях — иначе «игрок»
 * или «просмотр» в сводке автора и в карточке квеста означали бы разное, и
 * разобрать это можно было бы только глазами.
 */
const BY_QUEST = 'quest_id = $1';
const BY_AUTHOR = 'quest_id IN (SELECT id FROM quests WHERE author_id = $1)';
export const MIN_DAYS = 7;
export const MAX_DAYS = 180;

/** UTC-дата сегодня минус `back` суток, в формате `YYYY-MM-DD`. */
export function isoDay(back: number): string {
    return new Date(Date.now() - back * DAY_MS).toISOString().split('T')[0];
}

/** `days` из запроса: только вразумительный диапазон — один человек не должен
 *  уметь попросить с сервера весь вывод. */
export function clampDays(raw: unknown, fallback = 30): number {
    const n = typeof raw === 'string' ? parseInt(raw, 10) : Number(raw ?? fallback);
    if (!Number.isFinite(n)) return fallback;
    return Math.min(MAX_DAYS, Math.max(MIN_DAYS, Math.round(n)));
}

export interface Windows {
    to: string;
    from: string;
    prevTo: string;
    prevFrom: string;
}

/** Текущее и предыдущее окно одной длины. */
export function windowsOf(days: number): Windows {
    return {
        to: isoDay(0),
        from: isoDay(days - 1),
        prevTo: isoDay(days),
        prevFrom: isoDay(days * 2 - 1),
    };
}

export interface QuestAnalyticsRow {
    day: string;
    views: number;
    viewers: number;
    downloads: number;
    likes: number;
    dislikes: number;
    ratings: number;
    /** Средняя оценка за день; null — в этот день не оценивали. */
    rating_avg: number | null;
    reviews: number;
    players: number;
    playtime_seconds: number;
}

export interface QuestAnalyticsWindow {
    views: number;
    viewers: number;
    downloads: number;
    downloaders: number;
    likes: number;
    dislikes: number;
    ratings: number;
    rating_avg: number;
    reviews: number;
    players: number;
    playtime_seconds: number;
}

export interface QuestAnalytics {
    quest: {
        id: string;
        title: string;
        status: string;
        created_at: string | null;
        downloads_count: number;
        like_count: number;
        dislike_count: number;
    };
    days: number;
    from: string;
    to: string;
    series: QuestAnalyticsRow[];
    window: QuestAnalyticsWindow;
    previous: QuestAnalyticsWindow;
    lifetime: {
        views: number;
        viewers: number;
        plays_total_seconds: number;
        players: number;
        reviews: number;
        reviews_approved: number;
        reviews_answered: number;
        last_viewed_day: string | null;
        last_downloaded_at: string | null;
        last_played_at: string | null;
    };
    rating_histogram: { rating: number; count: number }[];
}

/** node-postgres отдаёт BIGINT и COUNT строкой. */
function num(v: unknown): number {
    if (typeof v === 'number') return v;
    const n = parseFloat(String(v ?? ''));
    return Number.isFinite(n) ? n : 0;
}

/**
 * `date` из pg приходит объектом `Date`, собранным на полночь ЛОКАЛЬНОГО
 * пояса. `toISOString()` сдвинул бы такой день назад на величину отрицательного
 * смещения сервера, поэтому читаем те же локальные поля, из которых дата
 * собралась.
 */
function dayKey(raw: unknown): string {
    if (raw instanceof Date) {
        const m = String(raw.getMonth() + 1).padStart(2, '0');
        const d = String(raw.getDate()).padStart(2, '0');
        return `${raw.getFullYear()}-${m}-${d}`;
    }
    return String(raw).slice(0, 10);
}

function emptyRow(day: string): QuestAnalyticsRow {
    return {
        day,
        views: 0,
        viewers: 0,
        downloads: 0,
        likes: 0,
        dislikes: 0,
        ratings: 0,
        rating_avg: null,
        reviews: 0,
        players: 0,
        playtime_seconds: 0,
    };
}

/**
 * Итоги двух окон одним запросом на сигнал. Разделитель — `FILTER (WHERE ...
 * >= $4)` против `FILTER (WHERE ... < $4)`: distinct-счётчики так складываются
 * точно, а «вычесть текущее из широкого диапазона» съело бы людей, которые
 * были активны в обоих окнах.
 */
async function windowTotals(
    subjectId: string,
    w: Windows,
    scope: string = BY_QUEST
): Promise<{
    cur: QuestAnalyticsWindow;
    prev: QuestAnalyticsWindow;
}> {
    const fromTs = `${w.prevFrom}T00:00:00Z`;
    const toTs = `${w.to}T23:59:59.999Z`;
    const curFromTs = `${w.from}T00:00:00Z`;
    const tsParams = [subjectId, fromTs, toTs, curFromTs];

    const [views, downloads, votes, ratings, reviews, play] = await Promise.all([
        pool.query(
            `SELECT COALESCE(sum(views) FILTER (WHERE day >= $4::date),0) AS n,
                    COUNT(DISTINCT user_id) FILTER (WHERE day >= $4::date) AS u,
                    COALESCE(sum(views) FILTER (WHERE day < $4::date),0) AS pn,
                    COUNT(DISTINCT user_id) FILTER (WHERE day < $4::date) AS pu
               FROM quest_views
              WHERE ${scope} AND day BETWEEN $2::date AND $3::date`,
            [subjectId, w.prevFrom, w.to, w.from]
        ),
        pool.query(
            `SELECT COUNT(*) FILTER (WHERE downloaded_at >= $4::timestamptz) AS n,
                    COUNT(DISTINCT user_id) FILTER (WHERE downloaded_at >= $4::timestamptz) AS u,
                    COUNT(*) FILTER (WHERE downloaded_at < $4::timestamptz) AS pn,
                    COUNT(DISTINCT user_id) FILTER (WHERE downloaded_at < $4::timestamptz) AS pu
               FROM quest_downloads
              WHERE ${scope} AND downloaded_at >= $2::timestamptz AND downloaded_at <= $3::timestamptz`,
            tsParams
        ),
        pool.query(
            `SELECT COUNT(*) FILTER (WHERE is_like AND created_at >= $4::timestamptz) AS l,
                    COUNT(*) FILTER (WHERE NOT is_like AND created_at >= $4::timestamptz) AS d,
                    COUNT(*) FILTER (WHERE is_like AND created_at < $4::timestamptz) AS pl,
                    COUNT(*) FILTER (WHERE NOT is_like AND created_at < $4::timestamptz) AS pd
               FROM quest_votes
              WHERE ${scope} AND created_at >= $2::timestamptz AND created_at <= $3::timestamptz`,
            tsParams
        ),
        pool.query(
            `SELECT COUNT(*) FILTER (WHERE created_at >= $4::timestamptz) AS n,
                    COALESCE(avg(rating) FILTER (WHERE created_at >= $4::timestamptz),0) AS a,
                    COUNT(*) FILTER (WHERE created_at < $4::timestamptz) AS pn,
                    COALESCE(avg(rating) FILTER (WHERE created_at < $4::timestamptz),0) AS pa
               FROM ratings
              WHERE ${scope} AND created_at >= $2::timestamptz AND created_at <= $3::timestamptz`,
            tsParams
        ),
        pool.query(
            `SELECT COUNT(*) FILTER (WHERE status = 'approved' AND created_at >= $4::timestamptz) AS n,
                    COUNT(*) FILTER (WHERE status = 'approved' AND created_at < $4::timestamptz) AS pn
               FROM reviews
              WHERE ${scope} AND created_at >= $2::timestamptz AND created_at <= $3::timestamptz`,
            tsParams
        ),
        pool.query(
            `SELECT COALESCE(sum(seconds) FILTER (WHERE day >= $4::date),0) AS n,
                    COUNT(DISTINCT user_id) FILTER (WHERE day >= $4::date AND seconds >= $5) AS u,
                    COALESCE(sum(seconds) FILTER (WHERE day < $4::date),0) AS pn,
                    COUNT(DISTINCT user_id) FILTER (WHERE day < $4::date AND seconds >= $5) AS pu
               FROM playtime_daily
              WHERE ${scope} AND day BETWEEN $2::date AND $3::date`,
            [subjectId, w.prevFrom, w.to, w.from, GAME_DAY_MIN_SECONDS]
        ),
    ]);

    const v = views.rows[0] ?? {};
    const dl = downloads.rows[0] ?? {};
    const v2 = votes.rows[0] ?? {};
    const rt = ratings.rows[0] ?? {};
    const rv = reviews.rows[0] ?? {};
    const pl = play.rows[0] ?? {};

    return {
        cur: {
            views: num(v.n),
            viewers: num(v.u),
            downloads: num(dl.n),
            downloaders: num(dl.u),
            likes: num(v2.l),
            dislikes: num(v2.d),
            ratings: num(rt.n),
            rating_avg: num(rt.a),
            reviews: num(rv.n),
            players: num(pl.u),
            playtime_seconds: num(pl.n),
        },
        prev: {
            views: num(v.pn),
            viewers: num(v.pu),
            downloads: num(dl.pn),
            downloaders: num(dl.pu),
            likes: num(v2.pl),
            dislikes: num(v2.pd),
            ratings: num(rt.pn),
            rating_avg: num(rt.pa),
            reviews: num(rv.pn),
            players: num(pl.pu),
            playtime_seconds: num(pl.pn),
        },
    };
}

/** Дневной ряд по текущему окну, сгруппированный в карту по дате. */
async function daySeries(
    subjectId: string,
    from: string,
    to: string,
    scope: string = BY_QUEST
): Promise<Map<string, QuestAnalyticsRow>> {
    const fromTs = `${from}T00:00:00Z`;
    const toTs = `${to}T23:59:59.999Z`;
    // node-postgres объявляет параметры как «тип неизвестен», и Postgres
    // выводит его из текста запроса. Параметр, который в тексте не упомянут,
    // остаётся без типа — 42P18 на пустом месте. Поэтому у каждого запроса
    // свой короткая раскладка, а не один общий массив на шесть.
    const dayParams = [subjectId, from, to];
    const tsParams = [subjectId, fromTs, toTs];
    // Ряд по дням считает «игроками» того же человека, что и награды: меньше
    // десяти минут в сутках — не игровой день, а открытая и забытая вкладка.
    const playParams = [...dayParams, GAME_DAY_MIN_SECONDS];

    const [views, downloads, votes, ratings, reviews, play] = await Promise.all([
        pool.query(
            `SELECT day, SUM(views)::int AS n, COUNT(DISTINCT user_id)::int AS u
               FROM quest_views
              WHERE ${scope} AND day BETWEEN $2::date AND $3::date
              GROUP BY day`,
            dayParams
        ),
        pool.query(
            `SELECT (downloaded_at AT TIME ZONE 'UTC')::date AS day, COUNT(*)::int AS n
               FROM quest_downloads
              WHERE ${scope} AND downloaded_at >= $2::timestamptz
                AND downloaded_at <= $3::timestamptz
              GROUP BY day`,
            tsParams
        ),
        pool.query(
            `SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
                    COUNT(*) FILTER (WHERE is_like)::int AS l,
                    COUNT(*) FILTER (WHERE NOT is_like)::int AS d
               FROM quest_votes
              WHERE ${scope} AND created_at >= $2::timestamptz
                AND created_at <= $3::timestamptz
              GROUP BY day`,
            tsParams
        ),
        pool.query(
            `SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
                    COUNT(*)::int AS n, AVG(rating)::float AS a
               FROM ratings
              WHERE ${scope} AND created_at >= $2::timestamptz
                AND created_at <= $3::timestamptz
              GROUP BY day`,
            tsParams
        ),
        pool.query(
            `SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
                    COUNT(*) FILTER (WHERE status = 'approved')::int AS n
               FROM reviews
              WHERE ${scope} AND created_at >= $2::timestamptz
                AND created_at <= $3::timestamptz
              GROUP BY day`,
            tsParams
        ),
        pool.query(
            `SELECT day, SUM(seconds)::bigint AS n,
                    COUNT(DISTINCT user_id) FILTER (WHERE seconds >= $4)::int AS u
               FROM playtime_daily
              WHERE ${scope} AND day BETWEEN $2::date AND $3::date
              GROUP BY day`,
            playParams
        ),
    ]);

    const byDay = new Map<string, QuestAnalyticsRow>();
    const rowFor = (raw: unknown): QuestAnalyticsRow => {
        const day = dayKey(raw);
        let row = byDay.get(day);
        if (!row) {
            row = emptyRow(day);
            byDay.set(day, row);
        }
        return row;
    };

    for (const r of views.rows) {
        const row = rowFor(r.day);
        row.views = num(r.n);
        row.viewers = num(r.u);
    }
    for (const r of downloads.rows) rowFor(r.day).downloads = num(r.n);
    for (const r of votes.rows) {
        const row = rowFor(r.day);
        row.likes = num(r.l);
        row.dislikes = num(r.d);
    }
    for (const r of ratings.rows) {
        const row = rowFor(r.day);
        row.ratings = num(r.n);
        row.rating_avg = r.a === null ? null : num(r.a);
    }
    for (const r of reviews.rows) rowFor(r.day).reviews = num(r.n);
    for (const r of play.rows) {
        const row = rowFor(r.day);
        row.playtime_seconds = num(r.n);
        row.players = num(r.u);
    }

    return byDay;
}

/**
 * Подробная статистика квеста одним ответом: экран один, и пять независимых
 * крутилок над пятью карточками выглядят как сломанная аналитика.
 *
 * Возвращает null, если квеста нет — права на чужую статистику проверяет
 * вызывающий, им нужен автор квеста.
 */
export async function getQuestAnalytics(
    questId: string,
    days: number
): Promise<QuestAnalytics | null> {
    const w = windowsOf(days);

    const questRes = await pool.query(
        `SELECT id, title, status, created_at,
                COALESCE(downloads_count,0)::int AS downloads_count,
                COALESCE(like_count,0)::int AS like_count,
                COALESCE(dislike_count,0)::int AS dislike_count
           FROM quests WHERE id = $1`,
        [questId]
    );
    if (questRes.rows.length === 0) return null;
    const quest = questRes.rows[0];

    const [totals, byDay, lifetime, hist] = await Promise.all([
        windowTotals(questId, w),
        daySeries(questId, w.from, w.to),
        pool.query(
            `SELECT
               (SELECT COALESCE(sum(views),0) FROM quest_views WHERE quest_id = $1) AS views,
               (SELECT COUNT(DISTINCT user_id) FROM quest_views WHERE quest_id = $1) AS viewers,
               (SELECT COALESCE(sum(playtime_seconds),0) FROM user_quest_playtime WHERE quest_id = $1) AS play_seconds,
               (SELECT COUNT(DISTINCT user_id) FROM playtime_daily WHERE quest_id = $1 AND seconds >= $2) AS players,
               (SELECT COUNT(*) FROM reviews WHERE quest_id = $1) AS reviews,
               (SELECT COUNT(*) FROM reviews WHERE quest_id = $1 AND status = 'approved') AS reviews_approved,
               (SELECT COUNT(*) FROM reviews WHERE quest_id = $1 AND author_reply IS NOT NULL) AS reviews_answered,
               (SELECT max(day) FROM quest_views WHERE quest_id = $1) AS last_viewed_day,
               (SELECT max(downloaded_at) FROM quest_downloads WHERE quest_id = $1) AS last_downloaded_at,
               (SELECT max(last_played_at) FROM user_quest_playtime WHERE quest_id = $1) AS last_played_at`,
            [questId, GAME_DAY_MIN_SECONDS]
        ),
        pool.query(
            `SELECT rating, COUNT(*)::int AS n FROM ratings WHERE quest_id = $1 GROUP BY rating`,
            [questId]
        ),
    ]);

    // Ряд обязан быть непрерывным: дырка автором читается как «статистика
    // сломалась», ноль — как «никто не заходил». А это разные ситуации.
    const series: QuestAnalyticsRow[] = [];
    for (let i = days - 1; i >= 0; i--) {
        const day = isoDay(i);
        series.push(byDay.get(day) ?? emptyRow(day));
    }

    const histByRating = new Map<number, number>(
        hist.rows.map((r: any) => [num(r.rating), num(r.n)] as [number, number])
    );
    const l = lifetime.rows[0] ?? {};
    const iso = (v: unknown): string | null =>
        v ? new Date(v as string).toISOString() : null;

    return {
        quest: {
            id: quest.id,
            title: quest.title,
            status: quest.status,
            created_at: iso(quest.created_at),
            downloads_count: num(quest.downloads_count),
            like_count: num(quest.like_count),
            dislike_count: num(quest.dislike_count),
        },
        days,
        from: w.from,
        to: w.to,
        series,
        window: totals.cur,
        previous: totals.prev,
        lifetime: {
            views: num(l.views),
            viewers: num(l.viewers),
            plays_total_seconds: num(l.play_seconds),
            players: num(l.players),
            reviews: num(l.reviews),
            reviews_approved: num(l.reviews_approved),
            reviews_answered: num(l.reviews_answered),
            last_viewed_day: l.last_viewed_day ? dayKey(l.last_viewed_day) : null,
            last_downloaded_at: iso(l.last_downloaded_at),
            last_played_at: iso(l.last_played_at),
        },
        rating_histogram: [5, 4, 3, 2, 1].map((rating) => ({
            rating,
            count: histByRating.get(rating) ?? 0,
        })),
    };
}

// ============================================================================
//  СВОДКА АВТОРА — те же правила, только по всем его квестам сразу
//
//  Отдельная логика здесь сознательно не заведена: итоги двух окон и дневной
//  ряд считаются теми же `windowTotals`/`daySeries`, что и по одному квесту,
//  только с другой областью. Иначе «игрок» в сводке и в карточке квеста значил
//  бы разное, а это ровно тот класс расхождений, который невозможно заметить
//  глазами и невозможно объяснить автору.
// ============================================================================

export interface AuthorAnalyticsQuest {
    id: string;
    title: string;
    status: string;
    views: number;
    viewers: number;
    downloads: number;
    players: number;
    playtime_seconds: number;
    likes: number;
    rating_avg: number | null;
}

export interface AuthorAnalytics {
    days: number;
    from: string;
    to: string;
    quests_total: number;
    quests_published: number;
    window: QuestAnalyticsWindow;
    previous: QuestAnalyticsWindow;
    series: QuestAnalyticsRow[];
    quests: AuthorAnalyticsQuest[];
}

/** Сколько квестов показываем строками: больше — это уже не сводка, а выгрузка. */
const MAX_QUEST_ROWS = 60;

export async function getAuthorAnalytics(
    authorId: string,
    days: number
): Promise<AuthorAnalytics> {
    const w = windowsOf(days);
    const fromTs = `${w.from}T00:00:00Z`;
    const toTs = `${w.to}T23:59:59.999Z`;

    const [totals, byDay, counts, rows] = await Promise.all([
        windowTotals(authorId, w, BY_AUTHOR),
        daySeries(authorId, w.from, w.to, BY_AUTHOR),
        pool.query(
            `SELECT COUNT(*)::int AS total,
                    COUNT(*) FILTER (WHERE status = 'published')::int AS published
               FROM quests WHERE author_id = $1`,
            [authorId]
        ),
        pool.query(
            `SELECT q.id, q.title, q.status,
                    (SELECT COALESCE(sum(v.views),0) FROM quest_views v
                      WHERE v.quest_id = q.id AND v.day BETWEEN $2::date AND $3::date) AS views,
                    (SELECT COUNT(DISTINCT v2.user_id) FROM quest_views v2
                      WHERE v2.quest_id = q.id AND v2.day BETWEEN $2::date AND $3::date) AS viewers,
                    (SELECT COUNT(*) FROM quest_downloads d
                      WHERE d.quest_id = q.id AND d.downloaded_at >= $4::timestamptz
                        AND d.downloaded_at <= $5::timestamptz) AS downloads,
                    (SELECT COUNT(DISTINCT p.user_id) FROM playtime_daily p
                      WHERE p.quest_id = q.id AND p.day BETWEEN $2::date AND $3::date
                        AND p.seconds >= $6) AS players,
                    (SELECT COALESCE(sum(p2.seconds),0) FROM playtime_daily p2
                      WHERE p2.quest_id = q.id AND p2.day BETWEEN $2::date AND $3::date) AS play_seconds,
                    (SELECT COUNT(*) FILTER (WHERE vt.is_like) FROM quest_votes vt
                      WHERE vt.quest_id = q.id AND vt.created_at >= $4::timestamptz
                        AND vt.created_at <= $5::timestamptz) AS likes,
                    (SELECT AVG(r.rating) FROM ratings r WHERE r.quest_id = q.id) AS rating_avg
               FROM quests q
              WHERE q.author_id = $1
              ORDER BY views DESC, q.created_at DESC
              LIMIT $7`,
            [
                authorId,
                w.from,
                w.to,
                fromTs,
                toTs,
                GAME_DAY_MIN_SECONDS,
                MAX_QUEST_ROWS
            ]
        ),
    ]);

    const series: QuestAnalyticsRow[] = [];
    for (let i = days - 1; i >= 0; i--) {
        const day = isoDay(i);
        series.push(byDay.get(day) ?? emptyRow(day));
    }

    const c = counts.rows[0] ?? {};

    return {
        days,
        from: w.from,
        to: w.to,
        quests_total: num(c.total),
        quests_published: num(c.published),
        window: totals.cur,
        previous: totals.prev,
        series,
        quests: rows.rows.map((r: any): AuthorAnalyticsQuest => ({
            id: String(r.id),
            title: String(r.title ?? ''),
            status: String(r.status ?? ''),
            views: num(r.views),
            viewers: num(r.viewers),
            downloads: num(r.downloads),
            players: num(r.players),
            playtime_seconds: num(r.play_seconds),
            likes: num(r.likes),
            rating_avg: r.rating_avg === null ? null : num(r.rating_avg),
        })),
    };
}
