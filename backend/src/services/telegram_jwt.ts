import crypto from 'crypto';

/**
 * Проверка id_token от Telegram Login Widget.
 *
 * Исторически несовпадение подписи только логировалось, и сервер принимал любой
 * JWT, у которого не истёк exp: подписав свой токен с чужим telegram_id, можно
 * было войти под любым аккаунтом или создать новый. Ключ подписи известен только
 * владельцу бота, поэтому проверка обязательна.
 */
export class TelegramTokenError extends Error {
    status = 401;
    constructor(message: string) {
        super(message);
        this.name = 'TelegramTokenError';
    }
}

function base64UrlDecode(str: string): string {
    let s = str.replace(/-/g, '+').replace(/_/g, '/');
    while (s.length % 4) s += '=';
    return Buffer.from(s, 'base64').toString('utf-8');
}

const signaturesMatch = (expected: string, actual: string): boolean => {
    const a = Buffer.from(expected);
    const b = Buffer.from(actual);
    // Разная длина — сразу мимо: timingSafeEqual на неровных буферах кидает.
    return a.length === b.length && crypto.timingSafeEqual(a, b);
};

export function verifyTelegramIdToken(idToken: string, botToken: string): any {
    if (!botToken) throw new TelegramTokenError('Telegram sign-in is not configured');

    const parts = String(idToken || '').split('.');
    if (parts.length !== 3) throw new TelegramTokenError('Invalid JWT format');

    let header: any;
    let payload: any;
    try {
        header = JSON.parse(base64UrlDecode(parts[0]));
        payload = JSON.parse(base64UrlDecode(parts[1]));
    } catch {
        throw new TelegramTokenError('Invalid JWT encoding');
    }

    // Только HS256: alg=none и RS256 проверить нечем, а принять их — значит
    // вернуть ту же дыру.
    if (header?.alg !== 'HS256') throw new TelegramTokenError('Unsupported Telegram token algorithm');

    const data = `${parts[0]}.${parts[1]}`;
    // Telegram подписывает id_token ключом SHA256(bot_token); сырой токен
    // оставляем вторым кандидатом — так проверяли старые сборки.
    const derived = crypto.createHash('sha256').update(botToken).digest();
    const expected = crypto.createHmac('sha256', derived).update(data).digest('base64url');
    const expectedRaw = crypto.createHmac('sha256', botToken).update(data).digest('base64url');
    if (!signaturesMatch(expected, parts[2]) && !signaturesMatch(expectedRaw, parts[2])) {
        throw new TelegramTokenError('Invalid Telegram token signature');
    }

    if (payload.exp && Date.now() / 1000 > payload.exp) {
        throw new TelegramTokenError('Telegram token expired');
    }
    return payload;
}

/** Подпись виджета (`telegramData` + `hash`) — тот же ключ, схема другая. */
export function verifyTelegramWidgetHash(data: Record<string, any>, botToken: string): boolean {
    const checkString = Object.keys(data)
        .filter((k) => k !== 'hash')
        .sort()
        .map((k) => `${k}=${data[k]}`)
        .join('\n');
    const secret = crypto.createHash('sha256').update(botToken).digest();
    const expected = crypto.createHmac('sha256', secret).update(checkString).digest('hex');
    return signaturesMatch(expected, String(data.hash));
}
