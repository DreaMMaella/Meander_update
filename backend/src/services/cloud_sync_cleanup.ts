import pool from '../config/database';
import { deleteAllUserFiles } from './cloud_sync_storage';

/**
 * Meander Cloud — фоновая очистка облака для неактивных пользователей.
 *
 * Стадии (используем `cloud_sync_quotas.cleanup_stage`):
 *
 *   active   →  пользователь активен (заходил недавно).
 *   warning  →  ≥83 дня без захода: за ≈7 дней до архивации (показываем баннер
 *                и можно слать push). Файлы пока на месте.
 *   archived →  ≥90 дней без захода: физически удалили user-`.mnd` с диска.
 *                Метаданные (size_bytes, fingerprint и т.п.) обнуляем,
 *                запись помечаем `deleted_at`, но строку оставляем, чтобы при
 *                возврате юзера видеть, что в облаке было. market_ref не трогаем.
 *   purged   →  ≥365 дней без захода (и нет опубликованных квестов в маркете):
 *                полная зачистка всех cloud_sync_* строк + директории.
 *
 *  Cron-задача `runCloudSyncCleanup()` запускается из app.ts по расписанию.
 *  Поведение полностью аддитивное: market_ref-записи никогда не удаляем
 *  автоматически — они бесплатные и могут пригодиться при возврате юзера.
 */

const DAYS = 24 * 60 * 60 * 1000;

const WARNING_AFTER_DAYS = 83;
const ARCHIVE_AFTER_DAYS = 90;
const PURGE_AFTER_DAYS = 365;

interface CleanupReport {
    warned: number;
    archived: number;
    purged: number;
    failed: number;
    durationMs: number;
}

/**
 * Помечает юзеров, которые скоро попадут под архивацию.
 * Только переход active → warning.
 */
async function applyWarnings(): Promise<number> {
    const r = await pool.query(
        `UPDATE cloud_sync_quotas q
            SET cleanup_stage = 'warning',
                cleanup_at    = now(),
                updated_at    = now()
           FROM profiles p
          WHERE p.id = q.user_id
            AND q.cleanup_stage = 'active'
            AND p.last_seen_at IS NOT NULL
            AND p.last_seen_at < now() - $1::interval
          RETURNING q.user_id`,
        [`${WARNING_AFTER_DAYS} days`],
    );
    return r.rowCount ?? 0;
}

/**
 * Архивирует user-файлы (≥90 дней). Помечает все user-записи `deleted_at`.
 * Удаляет физическую директорию пользователя.
 * market_ref-записи остаются — место не занимают.
 */
async function applyArchive(): Promise<{ archived: number; failed: number }> {
    const candidates = await pool.query(
        `SELECT q.user_id
           FROM cloud_sync_quotas q
           JOIN profiles p ON p.id = q.user_id
          WHERE q.cleanup_stage IN ('active', 'warning')
            AND p.last_seen_at IS NOT NULL
            AND p.last_seen_at < now() - $1::interval`,
        [`${ARCHIVE_AFTER_DAYS} days`],
    );

    let archived = 0;
    let failed = 0;
    for (const row of candidates.rows) {
        const userId: string = row.user_id;
        try {
            // 1) Удаляем user-файлы из БД (soft delete, чтобы триггер пересчитал used_*)
            await pool.query(
                `UPDATE cloud_sync_quests
                    SET deleted_at = now(),
                        size_bytes = 0,
                        fingerprint = NULL,
                        storage_path = '',
                        updated_at = now()
                  WHERE user_id = $1
                    AND source = 'user'
                    AND deleted_at IS NULL`,
                [userId],
            );
            // 2) Удаляем физически с диска всю директорию юзера
            await deleteAllUserFiles(userId);
            // 3) Помечаем quota
            await pool.query(
                `UPDATE cloud_sync_quotas
                    SET cleanup_stage = 'archived',
                        cleanup_at    = now(),
                        updated_at    = now()
                  WHERE user_id = $1`,
                [userId],
            );
            // 4) Аудит
            try {
                await pool.query(
                    `INSERT INTO cloud_sync_audit (user_id, action, detail)
                     VALUES ($1, 'archive', $2::jsonb)`,
                    [
                        userId,
                        JSON.stringify({
                            reason: 'inactive_for_days',
                            days: ARCHIVE_AFTER_DAYS,
                        }),
                    ],
                );
            } catch (_) {}
            archived++;
        } catch (e) {
            console.error('[cloud-cleanup] archive failed for', userId, e);
            failed++;
        }
    }
    return { archived, failed };
}

/**
 * Полная зачистка для давно неактивных пользователей (≥365 дней).
 * Не трогает пользователей, которые публиковали квесты в маркет — у них
 * есть какая-то ценность для платформы, чистим только их облако-блоб.
 */
async function applyPurge(): Promise<{ purged: number; failed: number }> {
    const candidates = await pool.query(
        `SELECT q.user_id
           FROM cloud_sync_quotas q
           JOIN profiles p ON p.id = q.user_id
          WHERE q.cleanup_stage = 'archived'
            AND p.last_seen_at IS NOT NULL
            AND p.last_seen_at < now() - $1::interval
            -- не трогаем тех у кого есть опубликованные квесты — пусть остаётся профиль
            AND NOT EXISTS (
                SELECT 1 FROM quests qm
                 WHERE qm.author_id = q.user_id AND qm.status = 'published'
            )`,
        [`${PURGE_AFTER_DAYS} days`],
    );

    let purged = 0;
    let failed = 0;
    for (const row of candidates.rows) {
        const userId: string = row.user_id;
        try {
            await pool.query(
                `DELETE FROM cloud_sync_quests WHERE user_id = $1`,
                [userId],
            );
            await pool.query(
                `UPDATE cloud_sync_quotas
                    SET cleanup_stage = 'purged',
                        cleanup_at    = now(),
                        used_bytes    = 0,
                        used_quests   = 0,
                        updated_at    = now()
                  WHERE user_id = $1`,
                [userId],
            );
            // На всякий случай файлы тоже
            await deleteAllUserFiles(userId);
            try {
                await pool.query(
                    `INSERT INTO cloud_sync_audit (user_id, action, detail)
                     VALUES ($1, 'purge', $2::jsonb)`,
                    [
                        userId,
                        JSON.stringify({
                            reason: 'inactive_for_days',
                            days: PURGE_AFTER_DAYS,
                        }),
                    ],
                );
            } catch (_) {}
            purged++;
        } catch (e) {
            console.error('[cloud-cleanup] purge failed for', userId, e);
            failed++;
        }
    }
    return { purged, failed };
}

/**
 * Возвращает юзера в активное состояние, если он зашёл после архивации.
 * Файлы не возвращаем (они уже удалены), но `cleanup_stage` сбрасываем
 * в active, чтобы UI не показывал «архив».
 */
export async function resetCleanupStageOnActivity(
    userId: string,
): Promise<void> {
    try {
        await pool.query(
            `UPDATE cloud_sync_quotas
                SET cleanup_stage = CASE
                        WHEN cleanup_stage IN ('warning', 'archived') THEN 'active'
                        ELSE cleanup_stage
                    END,
                    updated_at = now()
              WHERE user_id = $1`,
            [userId],
        );
    } catch (_) {
        // best-effort
    }
}

/**
 * Главная точка: запускает все стадии последовательно.
 * Возвращает отчёт для логирования / админ-UI.
 */
export async function runCloudSyncCleanup(): Promise<CleanupReport> {
    const t0 = Date.now();
    let warned = 0;
    let archived = 0;
    let purged = 0;
    let failed = 0;
    try {
        warned = await applyWarnings();
    } catch (e) {
        console.error('[cloud-cleanup] applyWarnings failed:', e);
    }
    try {
        const r = await applyArchive();
        archived = r.archived;
        failed += r.failed;
    } catch (e) {
        console.error('[cloud-cleanup] applyArchive failed:', e);
    }
    try {
        const r = await applyPurge();
        purged = r.purged;
        failed += r.failed;
    } catch (e) {
        console.error('[cloud-cleanup] applyPurge failed:', e);
    }
    const durationMs = Date.now() - t0;
    if (warned + archived + purged + failed > 0) {
        console.log(
            `[cloud-cleanup] warned=${warned} archived=${archived} purged=${purged} failed=${failed} in ${durationMs}ms`,
        );
    }
    return { warned, archived, purged, failed, durationMs };
}

/**
 * Запускает периодическую очистку.
 * По умолчанию раз в сутки.
 */
export function startCloudSyncCleanupCron(
    intervalMs: number = 24 * 60 * 60 * 1000,
): void {
    // Первый запуск через 5 минут после старта сервера, чтобы не нагружать запуск.
    setTimeout(() => {
        runCloudSyncCleanup().catch(() => {});
        setInterval(() => {
            runCloudSyncCleanup().catch(() => {});
        }, intervalMs);
    }, 5 * 60 * 1000);
    console.log(
        `🧹 [cloud-cleanup] cron started, interval=${Math.round(
            intervalMs / DAYS,
        )} day(s)`,
    );
}