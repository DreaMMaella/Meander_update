/**
 * Ошибки публикации квеста — по перечислимым кодам, а не «всё 400 и текст
 * исключения наружу».
 *
 * Причина, по которой маршрут раньше бросал голые `new Error(...)`: человек
 * у экрана публикации видел английское внутреннее сообщение (`File size
 * exceeds limit. Your limit: 100 MB`), либо текст чужого исключения БД, и по
 * этому тексту нельзя было понять, его это вина или сервер сломался. Прод-
 * выборка за две недели: 11 отказов публикации из 68, и все они приходили
 * кодом 400 — то есть клиент не мог отличить «файл больше лимита» от
 * «сервер упал».
 */

import type { NextFunction, Request, Response } from 'express';

export interface SizeGateRequest extends Request {
    user?: { id?: string };
}

export const REGULAR_USER_MAX_FILE_SIZE_BYTES = 100 * 1024 * 1024;
export const VERIFIED_USER_MAX_FILE_SIZE_BYTES = 500 * 1024 * 1024;

export const MB = 1024 * 1024;

export class PublishError extends Error {
    readonly code: string;
    readonly status: number;
    readonly details: Record<string, unknown>;

    constructor(
        code: string,
        status: number,
        message: string,
        details: Record<string, unknown> = {}
    ) {
        super(message);
        this.name = 'PublishError';
        this.code = code;
        this.status = status;
        this.details = details;
    }
}

export function sizeLimitFor(isVerified: boolean): number {
    return isVerified ? VERIFIED_USER_MAX_FILE_SIZE_BYTES : REGULAR_USER_MAX_FILE_SIZE_BYTES;
}

/**
 * Отсев по заявленному в Content-Length размеру — ДО разбора тела запроса.
 *
 * Без него 200-мегабайтный пакет доезжает до сервера целиком, ложится на диск
 * и только потом получает «лимит 100 МБ»: человек ждёт десятки секунд, чтобы
 * услышать «нельзя». Здесь же ответ уходит, пока байты ещё летят.
 */
export function declaredSizeRejection(
    contentLength: unknown,
    limitBytes: number
): PublishError | null {
    const declared = Number(contentLength);
    if (!Number.isFinite(declared) || declared <= 0) return null;
    // 5 МБ — запас на служебные поля multipart (обложка, скриншоты, text-поля):
    // заявленный размер тела всегда чуть больше самого пакета.
    const multipartOverheadBytes = 5 * MB;
    if (declared <= limitBytes + multipartOverheadBytes) return null;
    return fileTooLarge(declared, limitBytes);
}

/**
 * Отсев по размеру ДО разбора multipart-тела.
 *
 * Порядок постановки важен: multer пишет тело на диск, и без этого фильтра
 * 200-мегабайтный пакет приезжал целиком, чтобы тут же услышать «лимит 100
 * МБ». Lookup роли вынесен параметром — так фильтр проверяется тестом без БД,
 * а маршрут остаётся единственным местом, где есть pool.
 */
export function buildPublishSizeGate(lookupVerified: (userId: string) => Promise<boolean>) {
    return async function publishSizeGate(
        req: SizeGateRequest,
        res: Response,
        next: NextFunction
    ): Promise<void> {
        try {
            const userId = req.user?.id;
            if (!userId) return next();
            const limitBytes = sizeLimitFor(await lookupVerified(userId));
            const rejection = declaredSizeRejection(req.headers['content-length'], limitBytes);
            if (rejection) {
                console.log(`⛔ [Publish] размер отклонён до разбора тела: ${rejection.details?.size_mb} МБ`);
                res.status(rejection.status).json(toHttpResponse(rejection).body);
                return;
            }
            next();
        } catch (e) {
            // Не узнали роль — не блокируем публикацию: размер перепроверится
            // после записи файла.
            console.error('[Publish] size gate failed:', e);
            next();
        }
    };
}

export function fileTooLarge(sizeBytes: number, limitBytes: number): PublishError {
    const sizeMb = (sizeBytes / MB).toFixed(2);
    const limitMb = Math.round(limitBytes / MB);
    return new PublishError(
        'file_too_large',
        413,
        `Пакет квеста слишком большой: ${sizeMb} МБ при лимите ${limitMb} МБ. ` +
            `Убери лишнее из ресурсов квеста (лишние картинки, звук, видео) ` +
            `или попроси верификацию автора — с ней лимит 500 МБ.`,
        { size_bytes: sizeBytes, size_mb: Number(sizeMb), limit_bytes: limitBytes, limit_mb: limitMb }
    );
}

export function missingQuestFile(): PublishError {
    return new PublishError(
        'quest_file_required',
        400,
        'Файл квеста не дошёл до сервера. Попробуй опубликовать заново — ' +
            'обычно это обрыв связи во время загрузки.'
    );
}

export function ownershipConflict(): PublishError {
    return new PublishError(
        'quest_owned_by_other_author',
        409,
        'Квест с таким идентификатором уже опубликован другим автором. ' +
            'Так бывает, когда редактируют копию, скачанную из маркета: она ' +
            'сохраняет id исходной публикации. Сохрани работу под новым ' +
            'именем и опубликуй как новый квест.'
    );
}

export function duplicateFile(): PublishError {
    return new PublishError(
        'duplicate_file',
        409,
        'Такой файл уже есть в магазине у другого автора.'
    );
}

export function archiveUnreadable(reason: string): PublishError {
    return new PublishError(
        'archive_unreadable',
        422,
        'Сервер не смог разобрать пакет квеста. Проверь, что квест собирается ' +
            'без ошибок, и попробуй опубликовать заново.',
        { reason }
    );
}

export function contentRejected(reason: string): PublishError {
    return new PublishError(
        'content_policy_violation',
        422,
        `Публикация отклонена по правилам магазина: ${reason}`,
        { reason }
    );
}

export interface PublishHttpResponse {
    status: number;
    body: { error: string; code: string; [key: string]: unknown };
}

/**
 * Всё, что не PublishError, — поломка сервера: наружу уходит общая фраза,
 * оригинал остаётся в логе (там же, где и stack).
 */
export function toHttpResponse(err: unknown): PublishHttpResponse {
    if (err instanceof PublishError) {
        return {
            status: err.status,
            body: { error: err.message, code: err.code, ...err.details }
        };
    }
    return {
        status: 500,
        body: {
            error: 'Сервер не смог обработать публикацию. Попробуй позже — ' +
                'если ошибка повторяется, напиши в поддержку.',
            code: 'publish_failed'
        }
    };
}
