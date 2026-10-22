import pool from '../config/database';
import { AuthRequest } from '../middleware/auth';

/**
 * Актуальная роль из базы. Роль из JWT не пригодна для решений: токен живёт
 * 7 дней, и после понижения, бана или разжалования в нём остаётся старая
 * запись — то есть право, которого у человека уже нет.
 */
export const currentRole = async (req: AuthRequest): Promise<string | null> => {
    const userId = req.user?.id;
    if (!userId) return null;
    const r = await pool.query('SELECT role FROM profiles WHERE id = $1', [userId]);
    return r.rows[0]?.role ?? null;
};

export const isAdmin = async (req: AuthRequest): Promise<boolean> =>
    (await currentRole(req)) === 'admin';

/** Администратор или модератор — те, кто правит чужой контент. */
export const isStaff = async (req: AuthRequest): Promise<boolean> => {
    const role = await currentRole(req);
    return role === 'admin' || role === 'moderator';
};

/**
 * Непубликованную работу видят только её автор и администратор.
 *
 * Детали квеста, музыки и ассетов проверяют ровно это; хелпер нужен, чтобы
 * отдача файлов и остальные маршруты не разъезжались с ними.
 */
export const canSeeUnpublished = async (
    req: AuthRequest,
    authorId: string | null | undefined
): Promise<boolean> => {
    const userId = req.user?.id;
    if (!userId) return false;
    if (authorId && authorId === userId) return true;
    return isAdmin(req);
};
