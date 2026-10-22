import pool from '../config/database';
import { deleteAllUserFiles } from './cloud_sync_storage';

/**
 * Удаление аккаунтов, заявленных владельцами (App Store 5.1.1(v)).
 *
 * Человек нажимает «Удалить аккаунт» в настройках → POST /auth/account ставит
 * `profiles.deletion_purge_at = now() + 3 дня` (отменить можно до этого
 * момента). Здесь ждём срок и исполняем.
 *
 * Исполнение — одна транзакция с `DELETE FROM profiles`: в схеме каждая ссылка
 * на profiles обвешана ON DELETE CASCADE (или SET NULL там, где строка должна
 * пережить автора — опубликованные квесты, треки, товары маркета), поэтому
 * удалять по таблицам руками не нужно и нельзя: движок сам решает, что ушло
 * вместе с человеком.
 *
 * ВАЖНО: удаление необратимо и уносит в каскад чужой контент (сообщество,
 * созданное этим человеком, его посты и темы). Пока в окружении нет
 * `ACCOUNT_DELETION_PURGE=1`, sweep только считает готовые к удалению заявки и
 * ничего не трогает.
 */

const DAY = 24 * 60 * 60 * 1000;

/** Файл-джоб выбирает не больше N аккаунтов за проход. */
const BATCH_LIMIT = 20;

const purgeEnabled = (): boolean =>
    String(process.env.ACCOUNT_DELETION_PURGE ?? '').trim() === '1';

interface DeletionReport {
    ready: number;
    purged: number;
    failed: number;
    enforced: boolean;
    durationMs: number;
}

async function findReady(): Promise<string[]> {
    const r = await pool.query(
        `SELECT id::text
           FROM profiles
          WHERE deletion_purge_at IS NOT NULL
            AND deletion_purge_at <= now()
          ORDER BY deletion_purge_at
          LIMIT $1`,
        [BATCH_LIMIT],
    );
    return r.rows.map((row: { id: string }) => row.id);
}

/**
 * Удаляет один аккаунт. Возвращает true, если строка profiles ушла.
 * Повторный вызов для уже удалённого — no-op.
 */
async function purgeAccount(userId: string): Promise<boolean> {
    // Файлы в облаке синхронизации — вне транзакции: дисковые операции не
    // откатываются, а их отсутствие не должно мешать удалить аккаунт.
    try {
        await deleteAllUserFiles(userId);
    } catch (e) {
        console.error(`[account-deletion] files cleanup failed for ${userId}:`, e);
    }

    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        // FOR UPDATE: за это же окно человек мог нажать «отменить».
        const locked = await client.query(
            `SELECT id
               FROM profiles
              WHERE id = $1
                AND deletion_purge_at IS NOT NULL
                AND deletion_purge_at <= now()
                FOR UPDATE`,
            [userId],
        );
        if (locked.rowCount === 0) {
            await client.query('ROLLBACK');
            return false;
        }

        const audit = await client.query(
            `SELECT id
               FROM account_deletion_audit
              WHERE user_id = $1
                AND resolved_at IS NULL
              ORDER BY requested_at DESC
              LIMIT 1`,
            [userId],
        );

        const deleted = await client.query('DELETE FROM profiles WHERE id = $1', [
            userId,
        ]);

        // Журнал остаётся, но обезличенный: ни PII, ни идентификатора.
        if (audit.rowCount) {
            await client.query(
                `UPDATE account_deletion_audit
                    SET resolved_at   = now(),
                        outcome       = 'purged',
                        user_id       = NULL,
                        rows_affected = $2::jsonb
                  WHERE id = $1`,
                [
                    audit.rows[0].id,
                    JSON.stringify({ profile_deleted: deleted.rowCount ?? 0 }),
                ],
            );
        }

        await client.query('COMMIT');
        return (deleted.rowCount ?? 0) > 0;
    } catch (e) {
        await client.query('ROLLBACK').catch(() => {});
        throw e;
    } finally {
        client.release();
    }
}

/** Одна волна: считает готовые заявки и, если включено, удаляет их. */
export async function runAccountDeletionSweep(): Promise<DeletionReport> {
    const t0 = Date.now();
    const enforced = purgeEnabled();
    let ready = 0;
    let purged = 0;
    let failed = 0;

    try {
        const ids = await findReady();
        ready = ids.length;
        if (ready > 0 && !enforced) {
            console.warn(
                `[account-deletion] ${ready} заявок созрело, но ACCOUNT_DELETION_PURGE != 1 — ` +
                    `ничего не удаляем. Включите переменную, когда решите вопрос с контентом автора.`,
            );
        }
        if (enforced) {
            for (const id of ids) {
                try {
                    if (await purgeAccount(id)) purged++;
                } catch (e) {
                    failed++;
                    console.error(`[account-deletion] purge failed for ${id}:`, e);
                }
            }
        }
    } catch (e) {
        console.error('[account-deletion] sweep failed:', e);
    }

    const durationMs = Date.now() - t0;
    if (ready + purged + failed > 0) {
        console.log(
            `[account-deletion] ready=${ready} purged=${purged} failed=${failed} enforced=${enforced} in ${durationMs}ms`,
        );
    }
    return { ready, purged, failed, enforced, durationMs };
}

/** Почасовой проход. Первый — через 6 минут после старта, чтобы не мешать запуску. */
export function startAccountDeletionSweep(
    intervalMs: number = 60 * 60 * 1000,
): void {
    setTimeout(() => {
        runAccountDeletionSweep().catch(() => {});
        setInterval(() => {
            runAccountDeletionSweep().catch(() => {});
        }, intervalMs);
    }, 6 * 60 * 1000);
    console.log(
        `🗑 [account-deletion] sweep started, interval=${Math.round(
            intervalMs / DAY,
        )} day(s), purge=${purgeEnabled() ? 'ENFORCED' : 'dry-run'}`,
    );
}
