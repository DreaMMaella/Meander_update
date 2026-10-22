/**
 * SQL каталога маркета (`GET /quests`).
 *
 * Строка запроса собрана здесь, а не внутри маршрута, потому что на ней
 * держатся три разных обещания экрана: видны только опубликованные квесты,
 * показывается только то, что разрешено adult-настройкой зрителя, и номер
 * плейсхолдера жанра не съезжает, когда поиск уже занял `$1`.
 */

// Стиль ника автора подмешиваем джоином, а не через view: на проде
// `market_quests` определён явным списком колонок, и `CREATE OR REPLACE VIEW`
// с `q.*` переписал бы его состав.
const SELECT =
    "SELECT mq.*, p.cosmetics ->> 'name_style' AS author_name_style, p.cosmetics AS author_cosmetics " +
    "FROM market_quests mq LEFT JOIN profiles p ON p.id = mq.author_id " +
    "WHERE mq.status = 'published'";

export interface MarketListOptions {
    search?: string;
    category?: string;
    showNsfw?: boolean;
}

export interface BuiltQuery {
    text: string;
    params: any[];
}

export function marketListQuery({ search, category, showNsfw = false }: MarketListOptions): BuiltQuery {
    let text = SELECT;
    const params: any[] = [];

    if (!showNsfw) {
        text += ' AND mq.is_nsfw = FALSE';
    }

    // Ищем и по названию, и по автору: поле в маркете подписано «Найти историю,
    // автора, жанр…», а до этой ветки ник автора не находился вообще — на проде
    // по слову «NN» каталог отвечал пустотой, тогда как в нём восемь
    // опубликованных квестов с таким ником автора. Один плейсхолдер на оба
    // условия, параметр в массиве один — как в поиске музыкального маркета.
    if (search) {
        text += ` AND (mq.title ILIKE $${params.length + 1} OR mq.author_name ILIKE $${params.length + 1})`;
        params.push(`%${search}%`);
    }

    if (category && category !== 'All') {
        text += ` AND $${params.length + 1} = ANY(mq.genres)`;
        params.push(category);
    }

    text += ' ORDER BY mq.created_at DESC';

    return { text, params };
}
