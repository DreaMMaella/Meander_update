// Негативный контроль: «ищет автора» падает, если вернуть в предикате только
// mq.title; «один параметр на оба условия» — если начать толкать шаблон два
// раза; «плейсхолдер жанра не съезжает» — если сдвинуть нумерацию. Тесты
// «пороги видимости» падают, если выбросить фильтр статуса или adult-настройку.
//
// Почему тест на тексте SQL, а не на живом запросе: локальной базы в проекте
// нет, а прод крутит старый код. Сам предикат проверён read-only выборкой с
// прода: до фикса слово «NN» давало 0 совпадений по названию и 8 по автору.

const test = require('node:test');
const assert = require('node:assert');

const { marketListQuery } = require('../dist/services/market_query');

test('поиск ищет и по названию, и по автору', () => {
    const { text, params } = marketListQuery({ search: 'Иллюминат' });
    assert.ok(text.includes('mq.title ILIKE $1'), text);
    assert.ok(text.includes('mq.author_name ILIKE $1'), text);
    assert.ok(text.includes('OR'), 'условия должны быть через OR, иначе автор ищется вместо названия');
    assert.deepStrictEqual(params, ['%Иллюминат%']);
});

test('один параметр на оба условия: предикат в скобках', () => {
    const { text } = marketListQuery({ search: 'x', category: 'Horror' });
    assert.ok(text.includes(' AND (mq.title ILIKE $1 OR mq.author_name ILIKE $1) AND '), text);
});

test('без поиска предиката нет', () => {
    const { text, params } = marketListQuery({});
    assert.ok(!text.includes('ILIKE'), text);
    assert.deepStrictEqual(params, []);
});

test('видны только опубликованные, adult — только по настройке зрителя', () => {
    const { text } = marketListQuery({ search: 'x' });
    assert.ok(text.includes("mq.status = 'published'"), text);
    assert.ok(text.includes('mq.is_nsfw = FALSE'), text);
    assert.ok(!marketListQuery({ showNsfw: true }).text.includes('is_nsfw'));
});

test('жанр получает следующий свободный номер, когда поиск занял $1', () => {
    const { text, params } = marketListQuery({ search: 'дождь', category: 'Horror' });
    assert.ok(text.includes('$2 = ANY(mq.genres)'), text);
    assert.deepStrictEqual(params, ['%дождь%', 'Horror']);
});

test('категория All не добавляет условия', () => {
    const { text, params } = marketListQuery({ search: 'x', category: 'All' });
    assert.ok(!text.includes('ANY(mq.genres)'), text);
    assert.deepStrictEqual(params, ['%x%']);
});
