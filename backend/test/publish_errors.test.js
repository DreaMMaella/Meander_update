// Негативный контроль: тесты `declaredSizeRejection*` и `фильтр*` падают, если
// убрать отсев по Content-Length или ветку отказа в фильтре; тест «фильтр стоит
// в маршруте ДО разбора multipart-тела» падает, если поставить фильтр после
// `upload.fields`; тесты «toHttpResponse…» падают, если вернуть в catch-all
// `res.status(400).json({error: err.message})` — на голых 400 с английским
// текстом.
//
// Что проверяем: публикация отвечает кодом, по которому клиент различает
// «твой файл не влез», «это чужой квест», «правила отклонили» и «сервер сам
// сломался» — и не выбрасывает наружу внутренние сообщения.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const {
    PublishError,
    archiveUnreadable,
    buildPublishSizeGate,
    contentRejected,
    declaredSizeRejection,
    duplicateFile,
    fileTooLarge,
    missingQuestFile,
    ownershipConflict,
    sizeLimitFor,
    toHttpResponse
} = require('../dist/services/publish_errors');

const MB = 1024 * 1024;

test('sizeLimitFor', () => {
    assert.strictEqual(sizeLimitFor(false), 100 * MB);
    assert.strictEqual(sizeLimitFor(true), 500 * MB);
});

test('declaredSizeRejection отсекает 210 МБ до разбора тела', () => {
    const err = declaredSizeRejection(String(210 * MB), sizeLimitFor(false));
    assert.ok(err instanceof PublishError, 'ожидался PublishError');
    assert.strictEqual(err.status, 413);
    assert.strictEqual(err.code, 'file_too_large');
    assert.match(err.message, /210/);
    assert.match(err.message, /100/);
});

test('declaredSizeRejection пропускает тот же файл у верифицированного', () => {
    assert.strictEqual(declaredSizeRejection(String(210 * MB), sizeLimitFor(true)), null);
});

test('declaredSizeRejection: запас на служебные поля multipart, дальше — нет', () => {
    const limit = sizeLimitFor(false);
    assert.strictEqual(declaredSizeRejection(String(limit + 5 * MB), limit), null);
    assert.ok(declaredSizeRejection(String(limit + 5 * MB + 1), limit) !== null);
});

test('declaredSizeRejection не чинит запрос без внятного Content-Length', () => {
    assert.strictEqual(declaredSizeRejection(undefined, sizeLimitFor(false)), null);
    assert.strictEqual(declaredSizeRejection('abc', sizeLimitFor(false)), null);
    assert.strictEqual(declaredSizeRejection('0', sizeLimitFor(false)), null);
});

test('коды и статусы отказов перечислимы', () => {
    const cases = [
        [ownershipConflict(), 409, 'quest_owned_by_other_author'],
        [duplicateFile(), 409, 'duplicate_file'],
        [missingQuestFile(), 400, 'quest_file_required'],
        [archiveUnreadable('zip bomb'), 422, 'archive_unreadable'],
        [contentRejected('Слишком мало контента'), 422, 'content_policy_violation']
    ];
    for (const [err, status, code] of cases) {
        assert.strictEqual(err.status, status, `${code}: статус`);
        assert.strictEqual(err.code, code);
        assert.ok(/[А-Яа-я]/.test(err.message), `${code}: текст по-русски`);
    }
});

test('toHttpResponse сохраняет вилку PublishError', () => {
    const out = toHttpResponse(contentRejected('Порнография или интим-услуги'));
    assert.strictEqual(out.status, 422);
    assert.strictEqual(out.body.code, 'content_policy_violation');
    assert.match(out.body.error, /Порнография/);
    assert.strictEqual(out.body.reason, 'Порнография или интим-услуги');
});

test('toHttpResponse не отдаёт наружу внутреннее сообщение', () => {
    const out = toHttpResponse(new Error('duplicate key value violates unique constraint "quests_pkey"'));
    assert.strictEqual(out.status, 500);
    assert.strictEqual(out.body.code, 'publish_failed');
    assert.ok(!/duplicate key|quests_pkey|violates/.test(out.body.error),
        `утечка внутреннего текста: ${out.body.error}`);
});

test('отказ по размеру описан числами, а не общими словами', () => {
    const out = toHttpResponse(fileTooLarge(148.01 * MB, sizeLimitFor(false)));
    assert.strictEqual(out.status, 413);
    assert.strictEqual(out.body.limit_mb, 100);
    assert.strictEqual(out.body.size_mb, Number((148.01).toFixed(2)));
});

// --- Фильтр отсева по размеру (buildPublishSizeGate) ---

function fakeReq(contentLength, userId) {
    return { headers: userId === undefined ? {} : { 'content-length': contentLength }, user: userId ? { id: userId } : undefined };
}

function fakeRes() {
    const res = { statusCode: null, body: null };
    res.status = (code) => { res.statusCode = code; return res; };
    res.json = (body) => { res.body = body; return res; };
    return res;
}

async function runGate(lookupVerified, req) {
    const res = fakeRes();
    let nextCalled = false;
    await buildPublishSizeGate(lookupVerified)(req, res, () => { nextCalled = true; });
    return { res, nextCalled };
}

test('фильтр отклоняет слишком большой пакет до вызова next()', async () => {
    let lookedUp = false;
    const { res, nextCalled } = await runGate(async () => { lookedUp = true; return false; },
        fakeReq(String(210 * MB), 'user-1'));
    assert.strictEqual(lookedUp, true, 'роль автора должна быть запрошена');
    assert.strictEqual(nextCalled, false, 'next() до отклонения — значит multer уже пишет тело');
    assert.strictEqual(res.statusCode, 413);
    assert.strictEqual(res.body.code, 'file_too_large');
});

test('фильтр знает два лимита: 210 МБ проходит только верифицированному', async () => {
    const regular = await runGate(async () => false, fakeReq(String(210 * MB), 'u'));
    assert.strictEqual(regular.res.statusCode, 413);

    const verified = await runGate(async () => true, fakeReq(String(210 * MB), 'u'));
    assert.strictEqual(verified.nextCalled, true);
    assert.strictEqual(verified.res.statusCode, null);
});

test('фильтр не трогает запросы без авторизации и без внятного размера', async () => {
    const anonymous = await runGate(async () => { throw new Error('роль не должна запрошиваться'); },
        fakeReq(String(210 * MB)));
    assert.strictEqual(anonymous.nextCalled, true);

    const noLength = await runGate(async () => false, fakeReq(undefined, 'u'));
    assert.strictEqual(noLength.nextCalled, true);
    assert.strictEqual(noLength.res.statusCode, null);
});

test('фильтр не ломает публикацию, если роль не удалось узнать', async () => {
    const { res, nextCalled } = await runGate(async () => { throw new Error('connection terminated'); },
        fakeReq(String(210 * MB), 'u'));
    assert.strictEqual(nextCalled, true, 'нет БД — нет и отсева, дальше решит маршрут');
    assert.strictEqual(res.statusCode, null);
});

test('фильтр стоит в маршруте ДО разбора multipart-тела', () => {
    const route = fs.readFileSync(path.join(__dirname, '..', 'dist', 'routes', 'quests.js'), 'utf8');
    const mount = route.match(/router\.post\(\s*'\/'\s*,([^{]*?)\s*,\s*upload\.fields\s*\(/);
    assert.ok(mount, 'публикация должна монтироваться одним router.post');
    assert.ok(mount[1].includes('publishSizeGate'),
        'фильтр обязан стоять между authMiddleware и upload.fields: ниже multer уже пишет тело на диск');
});
