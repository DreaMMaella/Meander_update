import { Request, Response, NextFunction } from 'express';

// Перевод системных ошибок в человеческие — только перечислимые совпадения.
const KNOWN_ERROR_PATTERNS: Record<string, string> = {
    'relation .* does not exist': 'Квест временно недоступен. Попробуйте позже.',
    'duplicate key value': 'Такой элемент уже существует.',
    'violates foreign key constraint': 'Связанный элемент не найден.',
    'permission denied': 'У вас нет прав для этого действия.',
    'Invalid token': 'Сессия истекла. Пожалуйста, войдите заново.',
    'Too many requests': 'Слишком много запросов. Подождите немного.',
    'File too large': 'Файл слишком большой. Уменьшите размер и попробуйте снова.',
    'Bad JSON format': 'Неверный формат данных. Проверьте запрос и попробуйте снова.',
    'CORS blocked': 'Запрос заблокирован настройками безопасности.',
    'quest_votes_pkey': 'Вы уже голосовали за этот квест.',
    'ratings_pkey': 'Вы уже оценили этот квест.',
    'quest_downloads_pkey': 'Вы уже скачали этот квест.',
    'user_followers_pkey': 'Вы уже подписаны на этого автора.',
};

const matchKnownError = (message: string): string | null => {
    for (const [pattern, humanMessage] of Object.entries(KNOWN_ERROR_PATTERNS)) {
        if (new RegExp(pattern, 'i').test(message)) {
            return humanMessage;
        }
    }
    return null;
};

export const humanErrorMiddleware = (
    err: any,
    req: Request,
    res: Response,
    next: NextFunction
): void => {
    const errorMessage = err.message || 'Unknown error';
    const statusCode = err.status || err.statusCode || 500;
    const isProd = process.env.NODE_ENV === 'production';

    const knownMessage = matchKnownError(errorMessage);
    if (knownMessage) {
        res.status(statusCode).json({
            error: knownMessage,
            original_error: isProd ? undefined : errorMessage,
        });
        return;
    }

    res.status(statusCode).json({
        error: isProd ? 'Произошла ошибка. Попробуйте позже.' : errorMessage,
        original_error: isProd ? undefined : errorMessage,
    });
};
