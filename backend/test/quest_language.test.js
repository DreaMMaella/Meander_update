// Негативный контроль для метки языка (#331).
// «принимает форму» падает, если выбросить проверку регуляркой (тогда в
// колонку попадёт что угодно, вплоть до HTML); «сброс метки — null» падает,
// если пустую строку начать трактовать как валидный тег; «редактор не
// падает» — если undefined/массив начать приводить через String().
//
// Тест на чистом хелпере, а не на живом POST /quests: локальной базы в
// проекте нет, а публикацию на проде гоняем руками. SQL-часть (колонка и
// пересоздание витрины) лежит в migration_quest_language.sql.

const test = require('node:test');
const assert = require('node:assert');

const { normalizeQuestLanguage } = require('../dist/services/quest_language');

test('принимает форму языка', () => {
    assert.strictEqual(normalizeQuestLanguage('ru'), 'ru');
    assert.strictEqual(normalizeQuestLanguage('zh-CN'), 'zh-CN');
    assert.strictEqual(normalizeQuestLanguage('  pt-BR  '), 'pt-BR');
    assert.strictEqual(normalizeQuestLanguage('sr-RS'), 'sr-RS');
});

test('нёс языка — null, а не исключение', () => {
    for (const value of [undefined, null, '', '   ', 42, {}, [], 'ru ru']) {
        assert.strictEqual(normalizeQuestLanguage(value), null, String(value));
    }
});

test('отбрасывает не-теги', () => {
    for (const value of ['r', 'ru-CH-BOONT-TF', '<script>x</script>', 'ру', 'ru; DROP TABLE quests']) {
        assert.strictEqual(normalizeQuestLanguage(value), null, value);
    }
});

test('слишком длинное значение не едет в колонку', () => {
    assert.strictEqual(normalizeQuestLanguage('a'.repeat(36)), null);
    assert.strictEqual(normalizeQuestLanguage('en-' + 'x'.repeat(36)), null);
});
