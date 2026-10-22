#!/usr/bin/env python3
"""Конвейер словарей интерфейса: разбор, чанки переводчикам, сборка, отчёт.

Ключ перевода — русская строка ровно как в `lib/`, поэтому единственный
источник правды по ключам — английский словарь (`dictionaries/en_*.dart`):
гард `l10n_guard_test.dart` следит, чтобы он поспевал за кодом. Все прочие
языки — производные от того же набора ключей.

Команды:
  export                 канонический список ключей -> /tmp/l10n/en.tsv
  chunks --lang de       нарезать недостающие ключи чанками для переводчика
  merge --lang de        собрать out_*.tsv обратно в dictionaries/de.dart
  report                 покрытие и дефекты по каждому языку

Промежуточные TSV живут в /tmp/l10n: артефакт, который переживает перезагрузку,
— сам Dart-словарь в репозитории.
"""

import argparse
import glob
import json
import os
import re
import tempfile

APP_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DICT_DIR = os.path.join(APP_ROOT, "lib", "core", "l10n", "dictionaries")
REGISTRY = os.path.join(APP_ROOT, "lib", "core", "l10n", "app_languages.dart")
WORK = "/tmp/l10n"

# Экранирование Dart-литерала -> настоящий символ (то же, что в гард-тесте).
UNESCAPE = {
    "n": "\n", "t": "\t", "r": "\r", "a": "\x07", "b": "\b", "f": "\f",
    "v": "\v", "0": "\0", "e": "\x1b", "\\": "\\", "'": "'", '"': '"',
    "$": "$", "`": "`",
}

_QUOTED = r"(?:(\"((?:[^\"\\]|\\.)*)\")|'((?:[^'\\\n]|\\.)*)')"
# Запись словаря: `  'ключ': 'значение',`. Двойной кавычкой пишут значение,
# когда внутри апостроф (en_b11_holes). Якорь по началу строки обязателен:
# без него пара нашлась бы внутри значения-JSON (`{"p0": "x"}`), и разбор
# начал бы выдумывать ключи. Перенос после двоеточия разрешён — `dart format`
# длинные пары разбивает именно так.
_ENTRY_RE = re.compile(
    r"(?m)^[ \t]*" + _QUOTED + r"[ \t]*:[ \t\r\n]*" + _QUOTED + r"[ \t]*,?[ \t]*$"
)
_PLACEHOLDER_RE = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")
_CYRILLIC_RE = re.compile(r"[\u0400-\u04ff]")
# Форма числа: `'минута': ['Minute', 'Minuten'],` — одной строкой.
_LIST_ENTRY_RE = re.compile(
    r"(?m)^[ \t]*" + _QUOTED + r"[ \t]*:[ \t]*\[([^\]\n]*)\][ \t]*,?[ \t]*$"
)
_LIST_MAP_RE = re.compile(
    r"Map<String, List<String>>\s+\w+\s*=\s*\{(.*?)\n\};", re.S
)
# Литерал внутри `[ ... ]`: те же три группы, что и у ключа.
_ITEM_RE = re.compile(_QUOTED)
# Сколько форм у правила — по имени селектора из `app_language.dart`. Правило
# числа берётся из реестра `app_languages.dart`, поэтому написать его в двух
# местах и разойтись нельзя: `merge` сверяет длину списка с реестром.
PLURAL_FORMS = {
    "otherOnly": 1,
    "oneOrMany": 2,
    "moreThanOne": 2,
    "slavicPlural": 3,
    "arabicPlural": 6,
}
# Целевые письменности: у языка без своих знаков перевод подозрителен.
# Диапазоны записаны escaped-парами: в этом файле не должно быть ни
# иероглифов, ни арабских букв — их приносит перевод.
# Порядок обхода модулей для переводчиков: оболочка и экраны первого входа
# раньше глубин редактора. Имена — стеки без `en_`.
PRIORITY = [
    "common", "b2_core", "core", "b2_shared", "shared", "app", "b2_app",
    "shell", "b2_shell", "settings", "b2_settings", "b10_languages",
    "market", "b2_market", "hub", "b2_hub", "quests", "b2_quests", "b4_quests",
    "b5_quests", "b3_quests", "library", "b2_library", "resources",
    "b2_resources", "b5_resources", "publish", "b8_publish", "profile",
    "b2_profile", "b4_profile", "social", "b8_social", "community",
    "b2_community", "forums", "b2_forums", "messages", "b2_messages",
    "player", "b2_player", "game", "b2_game", "analytics", "b2_analytics",
    "b12_display", "misc", "b8_misc", "b2_misc", "undo", "b2_undo",
    "export", "b2_export", "theme", "b7_theme", "audio", "b2_music_library",
    "music_library", "asset_market", "b2_asset_market", "plugins",
    "b2_plugins", "plugin_host", "b2_plugin_host", "b2_analytics",
]
SCRIPTS = {
    "zh-CN": r"[\u4e00-\u9fff]",
    "ja": r"[\u3040-\u30ff\u4e00-\u9fff]",
    "ko": r"[\uac00-\ud7a3]",
    "ar": r"[\u0600-\u06ff]",
    "hi": r"[\u0900-\u097f]",
}


def decode(body: str) -> str:
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            if nxt == "u" and i + 5 < len(body):
                out.append(chr(int(body[i + 2:i + 6], 16)))
                i += 6
                continue
            out.append(UNESCAPE.get(nxt, nxt))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def encode(text: str) -> str:
    """Текст -> тело одинарного Dart-литерала.

    Внутри скрипта строки ходят уже расшифрованными (из TSV переводчик даёт
    обычный текст), поэтому экранировать нужно всё, что меняет смысл в Dart:
    обратный слэш, кавычку, `$`-интерполяцию и переводы строк.
    """
    out = []
    for c in text:
        if c == "\\":
            out.append(r"\\")
        elif c == "'":
            out.append(r"\'")
        elif c == "$":
            out.append(r"\$")
        elif c == "\n":
            out.append(r"\n")
        elif c == "\t":
            out.append(r"\t")
        elif c == "\r":
            out.append(r"\r")
        else:
            out.append(c)
    return "".join(out)


def literal(match, base: int):
    """(тело, кавычка) тройки групп `"…" | '…'`, начиная с группы `base`.

    Внутри групп `"…" | … | '…'` три номера: вся двойная кавычка, её тело и
    тело одинарной.
    """
    if match.group(base + 1) is not None:
        return match.group(base + 2), '"'
    return match.group(base + 3), "'"


def _clean(text: str) -> str:
    """Строки-комментарии в пустоту: апостроф в комментарии иначе сдвигает
    разбор пар «ключ: значение»."""
    return "\n".join(
        "" if line.lstrip().startswith(("//", "///")) else line
        for line in text.splitlines()
    )


def _first_map(path: str) -> str:
    return open(path, encoding="utf-8").read().split("\n};", 1)[0]


def english_entries():
    """[(ключ, английское значение)] в каноническом порядке модулей.

    Порядок = имя файла, затем порядок внутри: он же ложится в генерируемые
    словари, поэтому diff между прогонами остаётся читаемым.
    """
    return [(key, value) for key, value, _ in english_rows()]


def english_rows():
    """Как `english_entries`, но с модулем-источником каждой строки."""
    out, seen = [], {}
    for path in sorted(glob.glob(os.path.join(DICT_DIR, "en_*.dart"))):
        # Стек без префикса словаря: `en_b2_market.dart` -> модуль `b2_market`.
        stem = os.path.basename(path)[:-5].removeprefix("en_")
        for match in _ENTRY_RE.finditer(_clean(_first_map(path))):
            key = decode(literal(match, 0)[0])
            value = decode(literal(match, 3)[0])
            if key in seen:
                raise SystemExit(
                    f"ключ «{key}» дважды: {os.path.basename(path)} и "
                    f"{os.path.basename(seen[key])} — словари модулей пересеклись")
            seen[key] = path
            out.append((key, value, stem))
    return out


def chunk_order(rows):
    """Индексы строк в порядке переводчиков: сначала витрина, потом остальное.

    Кампания перевода длиннее одного прогона, а промах по словарю добирает
    английский, поэтому порядок чанков решает, какой язык выглядит переведённым
    наполовину. `PRIORITY` — экраны, которые человек видит первыми.
    """
    rank = {stem: i for i, stem in enumerate(PRIORITY)}
    return sorted(
        range(len(rows)),
        key=lambda i: (rank.get(rows[i][2], len(PRIORITY)), i),
    )


def read_language_dict(code: str):
    path = os.path.join(DICT_DIR, f"{dict_file(code)}.dart")
    if not os.path.exists(path):
        return {}
    result = {}
    for match in _ENTRY_RE.finditer(_clean(_first_map(path))):
        result[decode(literal(match, 0)[0])] = decode(literal(match, 3)[0])
    return result


def read_language_plurals(code: str):
    """{лемма: [формы]} из второй карты словаря языка."""
    path = os.path.join(DICT_DIR, f"{dict_file(code)}.dart")
    if not os.path.exists(path):
        return {}
    return _parse_list_maps(open(path, encoding="utf-8").read())


def english_plurals():
    """Формы числа английского словаря: он и есть эталон лемм."""
    out = {}
    for path in sorted(glob.glob(os.path.join(DICT_DIR, "en_*.dart"))):
        out.update(_parse_list_maps(open(path, encoding="utf-8").read()))
    return out


def _parse_list_maps(text: str):
    result = {}
    for body in _LIST_MAP_RE.findall(_clean(text)):
        for match in _LIST_ENTRY_RE.finditer(body):
            lemma = decode(literal(match, 0)[0])
            result[lemma] = [
                decode(literal(item, 0)[0])
                for item in _ITEM_RE.finditer(match.group(4))
            ]
    return result


def registry():
    """{код: селектор числа} из `app_languages.dart` — реестр как его видит Dart.

    Правило числа языка живёт в реестре; скрипт берёт его оттуда, чтобы
    проверка длины списка не расходилась с приложением. Язык-источник задан
    константой `kSourceLanguageCode`, её читаем из `app_language.dart`.
    """
    source = re.search(
        r"kSourceLanguageCode\s*=\s*'([^']+)'",
        open(_LANGUAGE_FILE, encoding="utf-8").read(),
    )
    if not source:
        raise SystemExit("не найден kSourceLanguageCode — реестр не разобрать")
    out = {}
    text = open(REGISTRY, encoding="utf-8").read()
    for block in text.split("AppLanguage(")[1:]:
        code = re.search(r"code:\s*(?:'((?:[^'\\]|\\.)*)'|(\w+))", block)
        if not code:
            continue
        key = decode(code.group(1)) if code.group(1) is not None else (
            source.group(1) if code.group(2) == "kSourceLanguageCode" else "")
        if not key:
            continue
        selector = re.search(r"pluralOf:\s*(\w+)", block)
        out[key] = selector.group(1) if selector else "oneOrMany"
    return out


def placeholders(text: str):
    return set(_PLACEHOLDER_RE.findall(text))


# Совпадение с английским законно, когда строка — единицы измерения или
# техническое имя: «{v} MB», «Audio», «Wi-Fi» в итальянском и испанском те же
# самые. Ждать от переводчика «исправления» тут нельзя: он начинает прятать
# неразрывные пробелы, а они попадают в Dart-литерал и ломают поиск по строке.
TECH_TOKENS = {
    "b", "kb", "mb", "gb", "tb", "pb", "s", "ms", "min", "h", "d", "w", "hz",
    "khz", "mhz", "ghz", "db", "fps", "ok", "oh", "audio", "video", "hi", "lo",
    "url", "uri", "id", "uuid", "lua", "json", "xml", "yaml", "png", "jpg",
    "jpeg", "gif", "webp", "svg", "mp3", "mp4", "webm", "apk", "aab", "exe",
    "dll", "so", "pdf", "txt", "md", "zip", "wi-fi", "ios", "android",
    "linux", "windows", "macos", "meander", "ctrl", "alt", "shift", "tab",
    "esc", "enter", "backspace", "space", "gtk", "qt", "ffi", "api", "sdk",
}
_TOKEN_RE = re.compile(r"[^\W\d_]+|\d+", re.UNICODE)
# Переводчик, которому запретили совпадать с английским, начинает прятать
# неразрывные пробелы и нулевые разделители. В Dart-литерале это невидимый
# символ: поиск по строке и копирование из экрана ломаются.
_INVISIBLE = {
    "\u00a0": " ", "\u202f": " ", "\u2007": " ", "\u2009": " ", "\u200a": " ",
    "\u200b": "", "\u200c": "", "\u200d": "", "\ufeff": "",
}


def clean_invisible(text: str) -> str:
    for src, dst in _INVISIBLE.items():
        text = text.replace(src, dst)
    return text


def copied_from_english(value: str, en: str) -> bool:
    """Много слов и ни одного русского, при этом дословно английская фраза.

    Плейсхолдеры выкидываются до разбора: «{v} MB» — это одно слово, а не
    двухсловная английская фраза.
    """
    if value != en:
        return False
    tokens = _TOKEN_RE.findall(_PLACEHOLDER_RE.sub(" ", value))
    if len(tokens) < 2:
        return False
    return not all(t.lower() in TECH_TOKENS or t.isdigit() for t in tokens)


def dict_file(code: str) -> str:
    """Имя файла словаря из кода: `pt-BR` -> `pt_br.dart`.

    Дефис в имени dart-файла не проходит `file_names`, поэтому код языка и
    имя файла различаются; обратный переход даёт `file_codes`.
    """
    return code.lower().replace("-", "_")


def file_codes():
    """{имя файла без расширения: код языка} по реестру `app_languages.dart`."""
    return {dict_file(code): code for code in registry()}


def k_source():
    """Код языка-источника из `app_language.dart`."""
    return re.search(r"kSourceLanguageCode\s*=\s*'([^']+)'",
                     open(_LANGUAGE_FILE, encoding="utf-8").read()).group(1)


_LANGUAGE_FILE = os.path.join(APP_ROOT, "lib", "core", "l10n", "app_language.dart")


def map_var(code: str) -> str:
    """Имя Dart-карты из кода языка: `pt-BR` -> `ptBrStrings`."""
    parts = code.split("-")
    return parts[0] + "".join(part.capitalize() for part in parts[1:]) + "Strings"


def plurals_var(code: str) -> str:
    """Имя карты форм числа: `pt-BR` -> `ptBrPlurals`."""
    return map_var(code)[: -len("Strings")] + "Plurals"


def plural_form_count(code: str) -> int:
    selector = registry().get(code)
    if selector is None:
        raise SystemExit(
            f"{code}: языка нет в реестре app_languages.dart — сначала строка "
            "в реестр, потом словарь")
    if selector not in PLURAL_FORMS:
        raise SystemExit(f"{code}: правило {selector} неизвестно скрипту; "
                         "допишите его в PLURAL_FORMS")
    return PLURAL_FORMS[selector]


def write_plurals_todo(code: str):
    """plurals_todo.jsonl: лемма + английские формы как образец.

    Русская лемма — это первая форма `trp`, её переводчик и должен положить в
    ключ; список форм языка по длине обязан совпасть с правилом языка.
    """
    en = english_plurals()
    have = {} if code == "en" else read_language_plurals(code)
    todo = {lemma: forms for lemma, forms in en.items() if lemma not in have}
    if not todo:
        print(f"{code}: формы числа закрыты ({len(en)} лемм)")
        return
    directory = os.path.join(WORK, code)
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, "plurals_todo.jsonl")
    with open(path, "w", encoding="utf-8") as handle:
        for lemma, forms in todo.items():
            handle.write(json.dumps(
                {"lemma": lemma, "en": forms}, ensure_ascii=False) + "\n")
    print(f"{path}  ({len(todo)} лемм, нужно по {plural_form_count(code)} форм)")


def read_plural_outputs(code: str):
    """{лемма: [формы]} из plurals_out.jsonl; кривые строки — отдельно."""
    result, broken = {}, []
    for path, record in read_records(os.path.join(WORK, code), "plurals_out"):
        lemma = record.get("lemma")
        forms = record.get("t")
        if not isinstance(lemma, str) or not isinstance(forms, list) or not forms:
            broken.append(f"{os.path.basename(path)}: {line_of(record)}")
            continue
        if any(not isinstance(f, str) or not f.strip() for f in forms):
            broken.append(f"{os.path.basename(path)}: {lemma}: пустая форма")
            continue
        forms = [clean_invisible(f.strip()) for f in forms]
        lemma = clean_invisible(lemma.strip())
        if lemma in result and result[lemma] != forms:
            broken.append(f"{lemma}: два разных списка")
        result[lemma] = forms
    return result, broken


def line_of(record) -> str:
    return json.dumps(record, ensure_ascii=False)[:80]


def write_chunks(code: str, size: int, force: bool):
    """chunk_NN.jsonl: `{i, en, ru}` — по записи на строку.

    JSONL вместо TSV: в 92 ключах есть перевод строки и табуляция (куски кода в
    подсказках), а `json.dumps` экранирует их сам. Переводчик обязан вернуть те
    же `i`.
    """
    rows = english_rows()
    have = {} if force else read_language_dict(code)
    todo = [i for i in chunk_order(rows) if not have.get(rows[i][0], "").strip()]
    if not todo:
        print(f"{code}: переводить нечего, {len(rows)} ключей закрыто")
    else:
        directory = os.path.join(WORK, code)
        os.makedirs(directory, exist_ok=True)
        for start in range(0, len(todo), size):
            part = todo[start:start + size]
            path = os.path.join(directory, f"chunk_{start // size + 1:02d}.jsonl")
            with open(path, "w", encoding="utf-8") as handle:
                for i in part:
                    ru, en, _ = rows[i]
                    handle.write(json.dumps(
                        {"i": i, "en": en, "ru": ru}, ensure_ascii=False) + "\n")
            print(f"{path}  ({len(part)} ключей)")
        print(f"{code}: {len(todo)} ключей в {(len(todo) + size - 1) // size} чанках")
    write_plurals_todo(code)


def read_records(directory: str, stem: str):
    """[(файл, запись)] из `<stem>*.jsonl`: одна строка — один объект."""
    out = []
    for path in sorted(glob.glob(os.path.join(directory, f"{stem}*.jsonl"))):
        for line in open(path, encoding="utf-8").read().splitlines():
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                record = None
            if not isinstance(record, dict):
                print(f"  ! {os.path.basename(path)}: не запись JSON: {line[:60]}")
                continue
            out.append((path, record))
    return out


def chunk_snapshot(code: str):
    """{индекс: ключ} из chunk_*.jsonl — снимок словаря на момент раскладки.

    Переводчик возвращает индекс из своего чанка, а ключевой набор с тех пор
    мог сдвинуться (в `en_*.dart` что-то добавили или убрали). Доверять индексу
    напрямую значит положить перевод в чужую строку, и QA-гард этого не видит:
    он сверяет плейсхолдеры с тем же чанком. Поэтому переводим индекс в ключ
    чанка, а ключ — в текущий индекс.

    Один индекс в двух чанках — это уже не снимок: второй ключ перетёр бы
    первый, и перевод уехал бы в чужую строку. Хвосты с доводкой новых
    ключей обязаны брать свободные индексы за концом раскладки.
    Возвращает ({индекс: ключ}, замечания).
    """
    snapshot = {}
    duplicates = []
    for path, record in read_records(os.path.join(WORK, code), "chunk_"):
        index, ru = record.get("i"), record.get("ru")
        if not (isinstance(index, int) and isinstance(ru, str)):
            continue
        held = snapshot.get(index)
        if held is not None and held != ru:
            duplicates.append(
                f"{index}: индекс занят ключом «{held[:40]}», а {os.path.basename(path)} "
                f"кладёт туда «{ru[:40]}»"
            )
            # Спорный индекс глушим совсем: перевод с него всё равно не знает,
            # в какой из двух ключей лечь.
            snapshot[index] = ""
            continue
        snapshot[index] = ru
    return snapshot, duplicates


def read_outputs(code: str):
    """{текущий_idx: перевод} из out_*.jsonl; кривые строки — отдельно."""
    snapshot, broken = chunk_snapshot(code)
    current = {ru: i for i, (ru, _) in enumerate(english_entries())}
    translated = {}
    for path, record in read_records(os.path.join(WORK, code), "out_"):
        index, value = record.get("i"), record.get("t")
        if not isinstance(index, int) or not isinstance(value, str) or not value.strip():
            broken.append(f"{os.path.basename(path)}: {line_of(record)}")
            continue
        value = clean_invisible(value.strip())
        # Чанков нет — перекладывать нечего, индекс считаем текущим.
        ru = snapshot.get(index) if snapshot else None
        if snapshot and ru is None:
            broken.append(f"{index}: индекса нет ни в одном чанке")
            continue
        if ru == "":
            # Спорный индекс: замечание уже выдал снимок чанков.
            continue
        if ru is not None:
            index = current.get(ru)
            if index is None:
                broken.append(f"«{ru[:40]}»: ключа больше нет в английском словаре")
                continue
        if index in translated and translated[index] != value:
            broken.append(f"{index}: два разных перевода в разных чанках")
        translated[index] = value
    return translated, broken


def write_language_dict(code, native, entries, merged, plurals):
    path = os.path.join(DICT_DIR, f"{dict_file(code)}.dart")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(
            f"/// Словарь «{native}»: русская строка -> перевод.\n"
            "///\n"
            "/// Файл собирает `tool/l10n/l10n_pipeline.py merge`; правки от руки\n"
            "/// следующий прогон перезапишет только ключи, что пришли из out_*.jsonl.\n"
            "/// Пропущенные ключи не беда: `fallbackCode` отдаёт их английскому,\n"
            "/// поэтому словарь наполняется по частям, а кириллицу пользователь не видит.\n"
            f"final Map<String, String> {map_var(code)} = {{\n")
        for ru, _ in entries:
            value = merged.get(ru)
            if value is None:
                continue
            handle.write(f"  '{encode(ru)}': '{encode(value)}',\n")
        handle.write("};\n\n")
        handle.write(
            "/// Формы числа: lemma первой русской формы -> список форм языка\n"
            f"/// в порядке его правила ({registry().get(code, 'oneOrMany')}).\n"
            f"final Map<String, List<String>> {plurals_var(code)} = {{\n")
        for lemma, forms in english_plurals().items():
            value = plurals.get(lemma)
            if value is None:
                continue
            items = ", ".join(f"'{encode(form)}'" for form in value)
            handle.write(f"  '{encode(lemma)}': [{items}],\n")
        handle.write("};\n")
    return path


def merge(code: str, native: str):
    entries = english_entries()
    known = {ru for ru, _ in entries}
    stored = read_language_dict(code)
    translated, problems = read_outputs(code)

    merged = dict(stored)
    added = 0
    # Индекс вне списка ключей — переводчик выдумал строку: молча пропустить
    # значит потерять её из отчёта о покрытии.
    problems.extend(f"{index}: индекса нет среди ключей"
                    for index in translated if not 0 <= index < len(entries))
    for index, (ru, en) in enumerate(entries):
        if index not in translated:
            continue
        value = translated[index]
        if placeholders(ru) != placeholders(value):
            problems.append(f"{index}: плейсхолдеры не совпали: «{ru}» -> «{value}»")
            continue
        if _CYRILLIC_RE.search(value):
            problems.append(f"{index}: кириллица в переводе «{value}»")
            continue
        # Дословно английская фраза из нескольких слов — переводчик не работал.
        # Одно слово и единицы измерения совпадают с английским законно.
        if copied_from_english(value, en):
            problems.append(f"{index}: осталась английская фраза «{value}»")
            continue
        if merged.get(ru) != value:
            merged[ru] = value
            added += 1
    dead = [ru for ru in merged if ru not in known]
    if dead:
        problems.append(f"мёртвых ключей в словаре: {len(dead)} (первым: «{dead[0]}»)")

    plurals = dict(read_language_plurals(code))
    wanted = plural_form_count(code)
    incoming, plural_problems = read_plural_outputs(code)
    for lemma, forms in incoming.items():
        if lemma not in known and lemma not in english_plurals():
            plural_problems.append(f"{lemma}: леммы нет в английском словаре")
            continue
        if len(forms) != wanted:
            plural_problems.append(
                f"{lemma}: форм {len(forms)}, а правилу языка нужно {wanted}")
            continue
        if any(_CYRILLIC_RE.search(f) for f in forms):
            plural_problems.append(f"{lemma}: кириллица в форме")
            continue
        plurals[lemma] = forms
    problems.extend(plural_problems)

    path = write_language_dict(code, native, entries, merged, plurals)
    covered = sum(1 for ru, _ in entries if merged.get(ru, "").strip())
    plural_total = len(english_plurals())
    print(f"{code}: применено {added}, покрытие {covered}/{len(entries)}, "
          f"формы числа {len(plurals)}/{plural_total} -> {path}")
    if problems:
        print(f"{code}: замечаний {len(problems)}")
        for item in problems[:80]:
            print(f"  - {item}")
    return len(problems)


def report():
    entries = english_entries()
    keys = {ru for ru, _ in entries}
    en_by_key = dict(entries)
    lemmas = english_plurals()
    langs = registry()
    names = file_codes()
    files = {os.path.basename(p)[:-5] for p in
             glob.glob(os.path.join(DICT_DIR, "[a-z][a-z]*.dart"))}
    # Модули `en_*.dart` и `en.dart` — части английского словаря, не язык.
    orphan = sorted(n for n in files
                    if not n.startswith("en") and n not in names)
    print(f"ключей: {len(entries)}, лемм формы числа: {len(lemmas)}")
    if orphan:
        print(f"Словарь есть, языка в реестре нет: {', '.join(orphan)}")
    # Отчёт по производным языкам: английский — источник ключей, сверять его
    # покрытие не с чем.
    for code in sorted(langs):
        name = dict_file(code)
        if name not in files or code in ("en", k_source()):
            continue
        data = read_language_dict(code)
        filled = {ru: v for ru, v in data.items() if v.strip()}
        want = SCRIPTS.get(code)
        no_script = sum(1 for ru, v in filled.items()
                        if not re.search(want, v)) if want else 0
        copied = sum(1 for ru, v in filled.items()
                     if copied_from_english(v, en_by_key.get(ru, "\u0000")))
        dead = len([ru for ru in data if ru not in keys])
        forms = read_language_plurals(code)
        bad_forms = [l for l, f in forms.items() if len(f) != plural_form_count(code)]
        print(f"{code}: {len(filled)}/{len(keys)} "
              f"({len(filled) * 100 // max(1, len(keys))}%), "
              f"формы числа {len(forms)}/{len(lemmas)}"
              f"{', неверная длина: ' + str(len(bad_forms)) if bad_forms else ''}, "
              f"мёртвых {dead}, без своей письменности {no_script}, "
              f"английских фраз {copied}")


def selftest():
    """Проверки разбора на синтетических исходниках.

    Конвейер пишет словари целиком, поэтому кривой разбор стоит дороже любой
    опечатки в переводе: молча потерянный ключ = кириллица на экране. Каждый
    контроль парный: на «грязном» образце находка обязана быть, на «чистом» —
    нет, иначе проверка пустая.
    """
    checks, failures = 0, []

    def check(name, condition):
        nonlocal checks
        checks += 1
        if not condition:
            failures.append(name)

    # Двойные кавычки вокруг значения: внутри апостроф (en_b11_holes).
    dq = _ENTRY_RE.search("  \"Don't\": \"it's fine\",\n")
    check("двойные кавычки",
          dq is not None and literal(dq, 0) == ("Don't", '"')
          and literal(dq, 3) == ("it's fine", '"'))

    # Перенос после двоеточия — так пишет `dart format` для длинных пар.
    wrapped = "  'Очень долгая подпись интерфейса':\n      'A long value',\n"
    hit = _ENTRY_RE.search(wrapped)
    check("перенос пары",
          hit is not None and len(list(_ENTRY_RE.finditer(wrapped))) == 1)
    check("ключ с переноса",
          hit is not None and literal(hit, 0)[0] == "Очень долгая подпись интерфейса")
    check("значение с переноса", hit is not None and literal(hit, 3)[0] == "A long value")

    # Значение-JSON: пара `"p0": "x"` внутри литерала не рождает фантомного
    # ключа — якорь по началу строки.
    inside = list(_ENTRY_RE.finditer("  'Выбери {p0}': \"{\\\"p0\\\": \\\"x\\\"}\",\n"))
    check("фантом из JSON-значения",
          len(inside) == 1 and decode(literal(inside[0], 3)[0]) == '{"p0": "x"}')

    # Кавычка внутри одинарного литерала обязана быть экранирована, иначе
    # разбор вообще не найдёт пару.
    check("экранированная кавычка",
          len(_ENTRY_RE.findall("  'нельзя': 'it\\'s ok',\n")) == 1)
    # Тот же литерал без экранирования — не пара: апостроф закрыл значение.
    check("без экранирования пары нет",
          len(_ENTRY_RE.findall("  'нельзя': 'it's ok',\n")) == 0)

    # encode/decode: обратный круг для самого противного текста.
    nasty = "Путь C:\\temp\nтаб\t$dollар 'quote' \"dq\""
    check("круг encode/decode", decode(encode(nasty)) == nasty)
    check("однострочный вывод", "\n" not in encode(nasty))

    # Карта форм числа читается из второй карты файла: `Map<String, String>`
    # не должна попадать в `_LIST_MAP_RE`, иначе строки интерфейса полезут в
    # формы числа.
    sample = (
        "final Map<String, String> deStrings = {\n"
        "  'Сохранить': 'Speichern',\n"
        "};\n\n"
        "final Map<String, List<String>> dePlurals = {\n"
        "  'квест': ['Quest', 'Quests'],\n"
        "  'день': ['Tag', 'Tage'],\n"
        "};\n"
    )
    lists = _parse_list_maps(sample)
    check("формы числа читаются", lists == {
        "квест": ["Quest", "Quests"], "день": ["Tag", "Tage"]})
    check("строки не лезут в формы", "Сохранить" not in lists)

    # Реестр: правило числа берётся из Dart, а не из копии в скрипте.
    # Язык-источник записан константой — её тоже надо развернуть, иначе
    # `--lang ru` решит, что такого языка нет.
    reg = registry()
    check("реестр читается",
          reg.get("en") == "oneOrMany" and reg.get("ru") == "slavicPlural")
    check("селекторы известны", all(v in PLURAL_FORMS for v in reg.values()))
    # Имя файла и код языка различаются: `pt-BR.dart` не проходит `file_names`,
    # а report() по неверной обратной связке молча потерял бы язык.
    check("имя файла без дефиса", dict_file("pt-BR") == "pt_br"
          and dict_file("de") == "de")
    check("обратная связка файл -> код",
          file_codes().get("zh_cn") == "zh-CN" and "pt_br" in file_codes())
    # Порядок чанков: витрина раньше глубины редактора — кампания перевода не
    # заканчивается одним прогоном, и недопереведённое добирает английский.
    rows = english_rows()
    order = chunk_order(rows)
    check("чанки идут по приоритету",
          {rows[order[0]][2], rows[order[1]][2]} == {"common"}
          or rows[order[0]][2] in PRIORITY)
    check("порядок чанков — перестановка, не потеря",
          sorted(order) == list(range(len(rows))) and len(order) == len(rows))

    # JSONL переносит самое противное: перевод строки, табуляцию, кавычку.
    nasty_row = json.dumps({"i": 1, "t": "Строка\nвторой\tтаб \"кавычка\" {x}"})
    back = json.loads(nasty_row)
    check("jsonl круг перевода строки",
          back["t"] == "Строка\nвторой\tтаб \"кавычка\" {x}"
          and "\n" not in nasty_row[1:-1].replace(chr(92) + "n", ""))

    check("лемм английского 13", len(english_plurals()) == 13)
    check("английское правило — две формы", plural_form_count("en") == 2)

    # Английский словарь читается целиком: 3830 ключей —
    # ровно столько, сколько насчитывает Dart (`enStrings.length`).
    # Плюс 2 ключа #331 («Язык квеста», «Не указан»).
    entries = english_entries()
    check("ключей 3830", len(entries) == 3830)
    check("нет пустых переводов",
          all(v.strip() for _, v in entries))

    # Сдвиг ключей посреди кампании перевода. Переводчик возвращает индекс из
    # своего чанка, а `en_*.dart` с момента раскладки изменились. Без перекладки
    # через ключ перевода уезжает в чужую строку, и qa-гард этого не видит: он
    # сверяет плейсхолдеры с тем же чанком.
    work_saved, entries_saved = WORK, globals()["english_entries"]
    with tempfile.TemporaryDirectory() as tmp:
        globals()["WORK"] = tmp
        lang_dir = os.path.join(tmp, "de")
        os.makedirs(lang_dir)

        def dump(name, records):
            with open(os.path.join(lang_dir, name), "w", encoding="utf-8") as h:
                for rec in records:
                    h.write(json.dumps(rec, ensure_ascii=False) + "\n")

        dump("chunk_01.jsonl", [
            {"i": 0, "en": "Alpha", "ru": "Альфа"},
            {"i": 1, "en": "Beta", "ru": "Бета"},
        ])
        dump("out_01.jsonl", [{"i": 0, "t": "Alpha-DE"}, {"i": 1, "t": "Beta-DE"}])
        # В словаре впереди встал новый ключ — индексы сдвинулись на единицу.
        shifted = [("Гамма", "Gamma"), ("Альфа", "Alpha"), ("Бета", "Beta")]
        globals()["english_entries"] = lambda: shifted
        remapped, broken = read_outputs("de")
        check("сдвиг индексов: перевод по своему ключу",
              remapped == {1: "Alpha-DE", 2: "Beta-DE"} and not broken)

        # Негативный контроль: тот же out_ без снимка чанков даёт наивный
        # маппинг, и «Alpha-DE» достаётся ключу «Гамма».
        for suffix in ("chunk_01.jsonl",):
            os.rename(os.path.join(lang_dir, suffix),
                      os.path.join(lang_dir, suffix + ".bak"))
        naive, _ = read_outputs("de")
        check("без снимка чанков индекс указал бы не на тот ключ",
              naive == {0: "Alpha-DE", 1: "Beta-DE"}
              and shifted[sorted(naive)[0]][0] == "Гамма")
        for suffix in ("chunk_01.jsonl",):
            os.rename(os.path.join(lang_dir, suffix + ".bak"),
                      os.path.join(lang_dir, suffix))

        # Выдуманный индекс и ушедший ключ должны быть видны, а не проглочены.
        dump("out_02.jsonl", [{"i": 99, "t": "Ghost-DE"}])
        with open(os.path.join(lang_dir, "chunk_01.jsonl"), "a",
                  encoding="utf-8") as h:
            h.write(json.dumps({"i": 2, "en": "Delta", "ru": "Дельта"},
                               ensure_ascii=False) + "\n")
        dump("out_03.jsonl", [{"i": 2, "t": "Delta-DE"}])
        _, problems = read_outputs("de")
        check("индекс вне чанков не теряется",
              any("99" in p for p in problems))
        check("ушедший ключ помечен",
              any("Дельта" in p for p in problems))

        # Хвост доводки лезет в занятый индекс: если снимок строится простым
        # присваиванием, второй чанк перетирает первый, и перевод «Альфа»
        # уезжает в «Дюбель». Гард держит первый чанк и громко ругается.
        dump("chunk_02.jsonl", [{"i": 0, "en": "Dowel", "ru": "Дюбель"}])
        snap2, dups = chunk_snapshot("de")
        check("двойной индекс помечен",
              any("Дюбель" in d for d in dups))
        check("спорный индекс оглушён, а не перетёрт",
              snap2.get(0) == "")
        naive_snap = {}
        for _path, rec in read_records(lang_dir, "chunk_"):
            naive_snap[rec["i"]] = rec["ru"]
        check("без гарда второй чанк перетёр бы индекс",
              naive_snap.get(0) == "Дюбель")
        dump("out_04.jsonl", [{"i": 0, "t": "Dowel-DE"}])
        moved, problems = read_outputs("de")
        check("со спорного индекса перевод не кладётся",
              "Alpha-DE" not in moved.values()
              and "Dowel-DE" not in moved.values()
              and any("Дюбель" in p for p in problems))

        globals()["WORK"] = work_saved
        globals()["english_entries"] = entries_saved

    print(f"selftest: проверок {checks}, провалов {len(failures)}")
    for name in failures:
        print(f"  - {name}")
    return len(failures)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command",
                        choices=["export", "chunks", "merge", "report",
                                 "selftest"])
    parser.add_argument("--lang")
    parser.add_argument("--native", default="")
    parser.add_argument("--size", type=int, default=700)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    if args.command == "selftest":
        raise SystemExit(1 if selftest() else 0)
    if args.command == "export":
        os.makedirs(WORK, exist_ok=True)
        entries = english_entries()
        with open(os.path.join(WORK, "en.tsv"), "w", encoding="utf-8") as handle:
            for index, (ru, en) in enumerate(entries):
                handle.write(f"{index}\t{encode(ru)}\t{encode(en)}\n")
        print(f"{len(entries)} ключей -> {WORK}/en.tsv")
        return
    if args.command == "chunks":
        if not args.lang:
            parser.error("--lang обязателен для chunks")
        write_chunks(args.lang, args.size, args.force)
    elif args.command == "merge":
        if not args.lang:
            parser.error("--lang обязателен для merge")
        merge(args.lang, args.native or args.lang)
    else:
        report()


if __name__ == "__main__":
    main()
