//! Runtime-состояние скриптов: переменные и таблицы.

use std::collections::{HashMap, HashSet};

use serde_json::{Map, Value};

use crate::models::QuestTable;

/// Ошибка runtime-состояния.
#[derive(Debug, thiserror::Error)]
pub enum RuntimeError {
    #[error("переменная не найдена: {0}")]
    VariableNotFound(String),
}

/// Переменные, которые пишет сам движок. Они не считаются «изменением данных»
/// для события `onDataChange`: иначе грубая подписка срабатывала бы на каждом
/// входе в ноду (там меняются `ID`/`LastID`) и превращалась бы в дубль
/// `onNodeEnter`. Всё служебное additionally начинается с `_`.
const ENGINE_OWNED_VARIABLES: [&str; 5] =
    ["ID", "LastID", "SAVE_DATE", "SAVE_TIME", "SAVE_DATETIME"];

/// Потолок одной пачки токенов изменений. Токены идут от грубого к точному,
/// поэтому при переполнении теряются самые детальные, а не подписка целиком.
const MAX_CHANGED_PATHS: usize = 512;

/// Потолок ячеек при диффе таблицы: свыше считаются только столбцы. Таблицы
/// квеста — ручная сетка, а не БД; ограничение страхует от квадратичного
/// обхода на гипотетической таблице в десятки тысяч строк.
const MAX_TABLE_DIFF_CELLS: usize = 400;

/// Префикс токена таблицы: `table.<имя>[.<ключ|столбец>[.<ряд>]]`.
pub const TABLE_TOKEN_PREFIX: &str = "table";

/// Считается ли имя переменной авторской данными (а не службой движка).
fn is_tracked_variable(name: &str) -> bool {
    let trimmed = name.trim();
    !trimmed.is_empty() && !trimmed.starts_with('_') && !ENGINE_OWNED_VARIABLES.contains(&trimmed)
}

/// Компонент пути из ключа/индекса.
fn path_component(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

/// Токен изменённой переменной: имя целиком.
///
/// Имя не режется по точкам — переменную автор может назвать `набор.слов`, и
/// это один ключ состояния. Подписка нормализует свой путь так, чтобы
/// совпадение работало и с цельным именем, и с разбитым.
fn variable_token(name: &str) -> Vec<String> {
    vec![name.trim().to_string()]
}

/// Формы пути из блока подписки, которые надо сравнить с токеном изменения.
///
/// Автор пишет `Золото`, `лавка.цена` или `table.лавка.цена.3` — а переменные
/// и таблицы живут в разных хранилищах и могут быть названы с точкой. Поэтому
/// путь разкладывается несколькими способами: разбитый по точкам и скобкам
/// (через тот же `parse_path`, что и блоки «Данные»), цельным именем, и с
/// табличным префиксом. Совпадение с любой формой считается подпиской.
pub fn watch_path_forms(raw: &str) -> Vec<Vec<String>> {
    let trimmed = raw.trim();
    if trimmed.is_empty() || trimmed == "*" {
        return Vec::new();
    }
    let parts: Vec<String> = crate::executor::parse_path(trimmed)
        .iter()
        .map(path_component)
        .collect();
    let mut forms: Vec<Vec<String>> = Vec::new();
    let push = |forms: &mut Vec<Vec<String>>, form: Vec<String>| {
        if !form.is_empty() && !forms.contains(&form) {
            forms.push(form);
        }
    };
    if parts.is_empty() {
        push(&mut forms, variable_token(trimmed));
        return forms;
    }
    push(&mut forms, parts.clone());
    if parts.len() > 1 {
        push(&mut forms, variable_token(trimmed));
    }
    if parts.first().map(String::as_str) != Some(TABLE_TOKEN_PREFIX) {
        let mut table_form = vec![TABLE_TOKEN_PREFIX.to_string()];
        table_form.extend(parts.iter().cloned());
        push(&mut forms, table_form);
        if parts.len() > 1 {
            push(
                &mut forms,
                vec![TABLE_TOKEN_PREFIX.to_string(), trimmed.to_string()],
            );
        }
    }
    forms
}

/// Совпадает ли форма подписки с токеном изменения.
///
/// Сравнение — префикс по компонентам в обе стороны: подписка на `лавка`
/// ловит изменение ячейки `лавка.цена.3`, а подписка на `лавка.цена` ловит
/// пачку, где движок смог определить только саму таблицу (или только её
/// сетку — тогда в токене стоит `*`).
pub fn watch_path_matches(form: &[String], token: &[String]) -> bool {
    if form.is_empty() || token.is_empty() {
        return false;
    }
    let shorter = form.len().min(token.len());
    form[..shorter]
        .iter()
        .zip(token[..shorter].iter())
        .all(|(a, b)| a == b || a == "*" || b == "*")
}

/// Токены изменённой таблицы: дифф старого и нового содержимого.
///
/// Движок отдаёт наружу таблицу целиком (так работает блок «Данные»), поэтому
/// «что именно изменилось» восстанавливается сравнением. Без этого подписка на
/// один столбец срабатывала бы на любое касание таблицы.
///
/// Токен заводим только на ту глубину, до которой дошёл дифф: промежуточные
/// ступени (таблица целиком рядом с ячейками, столбец рядом с рядами)
/// совпадали бы с любой более точной подпиской префиксом и обнуляли бы
/// фильтрацию. Грубый токен остаётся страховкой — когда дифф ряды не локализовал.
fn table_tokens(name: &str, old: &QuestTable, new: &QuestTable) -> Vec<Vec<String>> {
    if old == new {
        return Vec::new();
    }
    let table = name.trim().to_string();
    let mut out: Vec<Vec<String>> = Vec::new();

    let mut keys: Vec<&String> = old.data.keys().chain(new.data.keys()).collect();
    keys.sort();
    keys.dedup();
    for key in keys {
        if old.data.get(key) == new.data.get(key) {
            continue;
        }
        out.push(vec![
            TABLE_TOKEN_PREFIX.to_string(),
            table.clone(),
            key.clone(),
        ]);
    }

    let rows_changed = old.rows != new.rows;
    let cells = old
        .rows
        .iter()
        .chain(new.rows.iter())
        .map(|r| r.len())
        .sum::<usize>();
    if rows_changed && cells <= MAX_TABLE_DIFF_CELLS {
        let mut columns: Vec<&String> = old.columns.iter().chain(new.columns.iter()).collect();
        columns.sort();
        columns.dedup();
        let row_count = old.rows.len().max(new.rows.len());
        for column in columns {
            for index in 0..row_count {
                let before = old.rows.get(index).and_then(|r| r.get(column));
                let after = new.rows.get(index).and_then(|r| r.get(column));
                if before == after {
                    continue;
                }
                out.push(vec![
                    TABLE_TOKEN_PREFIX.to_string(),
                    table.clone(),
                    column.clone(),
                    (index + 1).to_string(),
                ]);
            }
        }
    } else if rows_changed {
        // Сетка слишком велика, чтобы перебирать ячейки: подписка получает
        // только факт, что ряды таблицы изменились.
        out.push(vec![TABLE_TOKEN_PREFIX.to_string(), table.clone()]);
    }
    if old.columns != new.columns {
        // Столбцы добавили/убрали/переименовали — сетка изменилась целиком.
        out.push(vec![
            TABLE_TOKEN_PREFIX.to_string(),
            table.clone(),
            "*".to_string(),
        ]);
    }
    if out.is_empty() {
        out.push(vec![TABLE_TOKEN_PREFIX.to_string(), table]);
    }
    out
}

/// Контракт состояния выполнения скриптов.
///
/// Паритет: `ScriptRuntimeState` из
/// `packages/mnd_core/lib/contracts/script_runtime.dart`.
pub trait ScriptRuntime {
    fn all_variables(&self) -> &Map<String, Value>;
    fn all_tables(&self) -> &HashMap<String, QuestTable>;

    fn set_variable(&mut self, name: &str, value: Value);
    fn get_variable(&self, name: &str) -> Option<&Value>;

    fn set_table(&mut self, table_name: &str, table: QuestTable);
    fn get_table(&self, table_name: &str) -> Option<&QuestTable>;

    /// Pacing-checkpoint: забрать переменные, изменённые с предыдущего
    /// checkpoint'а (блок `wait`), вместе со значениями. Снапшот
    /// прикрепляется к записи `_internal_delay_queue`, чтобы клиент
    /// опубликовал промежуточное состояние ПЕРЕД ожиданием (паритет:
    /// Dart-эталон мутировал state между `await Future.delayed`).
    fn take_pacing_snapshot_variables(&mut self) -> Vec<(String, Value)> {
        Vec::new()
    }

    /// Pacing-checkpoint: забрать таблицы, изменённые с предыдущего
    /// checkpoint'а, вместе с полным JSON таблицы.
    fn take_pacing_snapshot_tables(&mut self) -> Vec<(String, Value)> {
        Vec::new()
    }
}

/// In-memory реализация счётчика выполнения.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct InMemoryScriptRuntimeState {
    variables: Map<String, Value>,
    tables: HashMap<String, QuestTable>,
    /// Имена переменных, изменённых с момента последнего `drain_*`.
    dirty_variables: HashSet<String>,
    /// Имена таблиц, изменённых с момента последнего `drain_*`.
    dirty_tables: HashSet<String>,
    /// Имена переменных, изменённых с последнего pacing-checkpoint
    /// (блок `wait`). Снапшоты этих значений попадают в `_internal_delay_queue`,
    /// чтобы клиент публиковал ПРОМЕЖУТОЧНЫЕ состояния между задержками
    /// (паритет: Dart-эталон мутировал state между `await Future.delayed`,
    /// UI перевычислял видимости на каждом чихе).
    pacing_dirty_variables: HashSet<String>,
    pacing_dirty_tables: HashSet<String>,
    /// Сохранённые оригинальные значения переменных, перезаписанных через
    /// `apply_external_variables` (pacing-снапшоты). `None` = переменной
    /// не существовало до оверлея. Восстанавливаются через `restore_after_pacing`.
    pacing_overrides: HashMap<String, Option<Value>>,
    /// Пачка токенов изменений для события `onDataChange` (см. `note_change`).
    changed_paths: Vec<Vec<String>>,
}

impl InMemoryScriptRuntimeState {
    pub fn new(
        variables: Option<Map<String, Value>>,
        tables: Option<HashMap<String, QuestTable>>,
    ) -> Self {
        InMemoryScriptRuntimeState {
            variables: variables.unwrap_or_default(),
            tables: tables.unwrap_or_default(),
            dirty_variables: HashSet::new(),
            dirty_tables: HashSet::new(),
            pacing_dirty_variables: HashSet::new(),
            pacing_dirty_tables: HashSet::new(),
            pacing_overrides: HashMap::new(),
            changed_paths: Vec::new(),
        }
    }

    /// Парсинг из flat JSON-объектов (как Dart `fromJson`).
    pub fn from_json(
        variables: Option<Map<String, Value>>,
        tables: Option<Map<String, Value>>,
    ) -> Self {
        let parsed_tables = tables
            .unwrap_or_default()
            .into_iter()
            .map(|(key, value)| (key, QuestTable::from_json(&value)))
            .collect::<HashMap<_, _>>();

        InMemoryScriptRuntimeState {
            variables: variables.unwrap_or_default(),
            tables: parsed_tables,
            dirty_variables: HashSet::new(),
            dirty_tables: HashSet::new(),
            pacing_dirty_variables: HashSet::new(),
            pacing_dirty_tables: HashSet::new(),
            pacing_overrides: HashMap::new(),
            changed_paths: Vec::new(),
        }
    }

    pub fn variables(&self) -> &Map<String, Value> {
        &self.variables
    }

    pub fn tables(&self) -> &HashMap<String, QuestTable> {
        &self.tables
    }

    pub fn clear(&mut self) {
        self.variables.clear();
        self.tables.clear();
        self.dirty_variables.clear();
        self.dirty_tables.clear();
        self.pacing_dirty_variables.clear();
        self.pacing_dirty_tables.clear();
        self.pacing_overrides.clear();
        self.changed_paths.clear();
    }

    /// Собрать и очистить имена изменённых переменных.
    pub fn drain_dirty_variables(&mut self) -> HashSet<String> {
        std::mem::take(&mut self.dirty_variables)
    }

    /// Собрать и очистить имена изменённых таблиц.
    pub fn drain_dirty_tables(&mut self) -> HashSet<String> {
        std::mem::take(&mut self.dirty_tables)
    }

    /// Имена переменных, изменённых с последнего pacing-checkpoint.
    pub fn drain_pacing_dirty_variables(&mut self) -> HashSet<String> {
        std::mem::take(&mut self.pacing_dirty_variables)
    }

    /// Имена таблиц, изменённых с последнего pacing-checkpoint.
    pub fn drain_pacing_dirty_tables(&mut self) -> HashSet<String> {
        std::mem::take(&mut self.pacing_dirty_tables)
    }

    /// Доступ к переменным движка (mutable, без dirty-трекинга).
    pub fn variables_mut(&mut self) -> &mut Map<String, Value> {
        &mut self.variables
    }

    /// Записать токен изменения (дедуп + потолок пачки).
    fn note_change(&mut self, token: Vec<String>) {
        if token.is_empty() || self.changed_paths.len() >= MAX_CHANGED_PATHS {
            return;
        }
        if !self.changed_paths.contains(&token) {
            self.changed_paths.push(token);
        }
    }

    /// Забрать и очистить пачку токенов изменений — вход диспетчера
    /// `onDataChange` в конце игрового шага.
    pub fn drain_changed_paths(&mut self) -> Vec<Vec<String>> {
        std::mem::take(&mut self.changed_paths)
    }

    /// Забыть накопленные изменения: инициализация состояния (дефолты квеста,
    /// загрузка сейва) — не «изменение данных», иначе подписка срабатывала бы
    /// на старте ноды без участия игрока.
    pub fn reset_changed_paths(&mut self) {
        self.changed_paths.clear();
    }

    /// Сохранённые оригиналы для отката pacing-оверлеев.
    pub fn pacing_overrides_mut(&mut self) -> &mut HashMap<String, Option<Value>> {
        &mut self.pacing_overrides
    }
}

impl ScriptRuntime for InMemoryScriptRuntimeState {
    fn all_variables(&self) -> &Map<String, Value> {
        &self.variables
    }

    fn all_tables(&self) -> &HashMap<String, QuestTable> {
        &self.tables
    }

    fn set_variable(&mut self, name: &str, value: Value) {
        // Токен только при реальной смены значения: присваивание того же числа
        // не должно гонять диспетчер по кругу.
        let changed = is_tracked_variable(name)
            && self
                .variables
                .get(name)
                .map(|previous| previous != &value)
                .unwrap_or(true);
        let token = changed.then(|| variable_token(name));
        self.variables.insert(name.to_string(), value);
        self.dirty_variables.insert(name.to_string());
        self.pacing_dirty_variables.insert(name.to_string());
        if let Some(token) = token {
            self.note_change(token);
        }
    }

    fn get_variable(&self, name: &str) -> Option<&Value> {
        self.variables.get(name)
    }

    fn set_table(&mut self, table_name: &str, table: QuestTable) {
        let previous = self.tables.get(table_name).cloned().unwrap_or_else(|| {
            QuestTable::new(table_name.to_string(), Vec::new(), Vec::new(), Map::new())
        });
        let tokens = table_tokens(table_name, &previous, &table);
        self.tables.insert(table_name.to_string(), table);
        self.dirty_tables.insert(table_name.to_string());
        self.pacing_dirty_tables.insert(table_name.to_string());
        for token in tokens {
            self.note_change(token);
        }
    }

    fn get_table(&self, table_name: &str) -> Option<&QuestTable> {
        self.tables.get(table_name)
    }

    fn take_pacing_snapshot_variables(&mut self) -> Vec<(String, Value)> {
        let mut out = Vec::new();
        for name in self.drain_pacing_dirty_variables() {
            if let Some(value) = self.variables.get(&name) {
                out.push((name, value.clone()));
            }
        }
        out
    }

    fn take_pacing_snapshot_tables(&mut self) -> Vec<(String, Value)> {
        let mut out = Vec::new();
        for name in self.drain_pacing_dirty_tables() {
            if let Some(table) = self.tables.get(&name) {
                out.push((name, table.to_json()));
            }
        }
        out
    }
}
