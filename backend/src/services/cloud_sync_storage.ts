import { promises as fs, createReadStream } from 'fs';
import path from 'path';
import crypto from 'crypto';

/**
 * Meander Cloud — physical storage on local filesystem.
 *
 * Layout: <root>/<userId>/<questId>.mnd
 *
 * Конфигурируется через env CLOUD_SYNC_ROOT (по умолчанию `<cwd>/storage/cloud_sync`).
 */

function resolveRoot(): string {
    const env = process.env.CLOUD_SYNC_ROOT;
    if (env && env.trim().length > 0) return path.resolve(env);
    return path.resolve(process.cwd(), 'storage', 'cloud_sync');
}

export const CLOUD_SYNC_ROOT = resolveRoot();

async function ensureDir(p: string): Promise<void> {
    await fs.mkdir(p, { recursive: true });
}

function userDir(userId: string): string {
    // Защита от path traversal — допускаем только UUID-like символы
    if (!/^[0-9a-fA-F-]{32,40}$/.test(userId)) {
        throw new Error(`Invalid userId for storage: ${userId}`);
    }
    return path.join(CLOUD_SYNC_ROOT, userId);
}

function safeQuestId(questId: string): string {
    // Допускаем только латиницу, цифры, дефис, подчёркивание (chunk до 128 символов)
    const clean = questId.replace(/[^a-zA-Z0-9_-]/g, '_');
    if (clean.length === 0 || clean.length > 128) {
        throw new Error(`Invalid questId for storage: ${questId}`);
    }
    return clean;
}

export function questFilePath(userId: string, questId: string): string {
    return path.join(userDir(userId), `${safeQuestId(questId)}.mnd`);
}

export async function writeQuestFile(
    userId: string,
    questId: string,
    data: Buffer,
): Promise<{ path: string; size: number; fingerprint: string }> {
    await ensureDir(userDir(userId));
    const filePath = questFilePath(userId, questId);
    const tmpPath = `${filePath}.tmp-${Date.now()}`;

    // Атомарная запись: пишем во временный файл, потом rename
    await fs.writeFile(tmpPath, data, { flag: 'w' });
    await fs.rename(tmpPath, filePath);

    const fingerprint = sha256Hex(data);
    return {
        path: path.relative(CLOUD_SYNC_ROOT, filePath),
        size: data.byteLength,
        fingerprint,
    };
}

export async function readQuestStream(
    userId: string,
    questId: string,
): Promise<{ stream: NodeJS.ReadableStream; size: number }> {
    const filePath = questFilePath(userId, questId);
    const stat = await fs.stat(filePath);
    if (!stat.isFile()) throw new Error(`Not a file: ${filePath}`);
    return { stream: createReadStream(filePath), size: stat.size };
}

export async function deleteQuestFile(
    userId: string,
    questId: string,
): Promise<void> {
    const filePath = questFilePath(userId, questId);
    try {
        await fs.unlink(filePath);
    } catch (e: any) {
        if (e?.code !== 'ENOENT') throw e;
    }
}

export async function questFileExists(
    userId: string,
    questId: string,
): Promise<boolean> {
    try {
        const stat = await fs.stat(questFilePath(userId, questId));
        return stat.isFile();
    } catch {
        return false;
    }
}

export function sha256Hex(data: Buffer): string {
    return crypto.createHash('sha256').update(data).digest('hex');
}

/**
 * Удалить все файлы пользователя (например, при DELETE аккаунта).
 * Best-effort: ENOENT игнорируем.
 */
export async function deleteAllUserFiles(userId: string): Promise<void> {
    const dir = userDir(userId);
    try {
        await fs.rm(dir, { recursive: true, force: true });
    } catch (e: any) {
        if (e?.code !== 'ENOENT') throw e;
    }
}