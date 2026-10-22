import pool from '../config/database';
import { buildPushFromNotification } from './fcm';
import { SYSTEM_USER_ID, DM_RULES } from './gating';

/**
 * Зеркало системных уведомлений в чат команды.
 *
 * Колокольчик остаётся как есть — здесь то же событие становится репликой в
 * диалоге, который человек открывает, чтобы понять, что вообще происходило с
 * его аккаунтом. Текст не изобретаем: берём ту же русскую формулировку, что и
 * для пуша, иначе два канала начнут рассказывать об одном событии по-разному.
 * Пороги приватности и кулдауны ЛС на неё не распространяются: автор сообщения
 * — сама система, а не человек.
 */
export const mirrorToSystemChat = async (
    userIds: string[],
    actorId: string | null,
    type: string,
    payload?: Record<string, any> | null
): Promise<void> => {
    // Новость команды уже лежит в чатах как сообщение рассылки — второе её
    // же зеркало было бы дублем. Личное сообщение тем более: приватный текст
    // не должен попадать в третий канал.
    if (type === 'system_news' || type === 'dm_message') return;
    const recipients = Array.from(new Set(userIds.filter(id => id && id !== SYSTEM_USER_ID)));
    if (recipients.length === 0) return;

    let actorName: string | null = null;
    if (actorId) {
        const actor = await pool.query('SELECT full_name FROM profiles WHERE id = $1', [actorId]);
        actorName = actor.rows[0]?.full_name ?? null;
    }

    const notice = buildPushFromNotification(type, payload, actorName);
    if (!notice) return;
    const body = notice.body.slice(0, DM_RULES.maxBodyChars);

    // ON CONFLICT DO UPDATE возвращает строку и при вставке, и при уже
    // существующем диалоге — поэтому одним запросом получаем треды всех, кому
    // пишем, и сразу в них пишем.
    await pool.query(
        `WITH threads AS (
            INSERT INTO dm_threads (user_a, user_b)
            SELECT $1::uuid, u FROM (SELECT DISTINCT unnest($2::uuid[]) AS u) x WHERE u <> $1::uuid
            ON CONFLICT (user_a, user_b) DO UPDATE SET user_a = EXCLUDED.user_a
            RETURNING id, user_b
         ), written AS (
            INSERT INTO dm_messages (thread_id, sender_id, body, kind)
            SELECT id, $1::uuid, $3, $4 FROM threads
            RETURNING 1
         )
         UPDATE dm_threads t SET last_message_at = NOW()
           FROM threads WHERE t.id = threads.id`,
        [SYSTEM_USER_ID, recipients, body, type]
    );
};
