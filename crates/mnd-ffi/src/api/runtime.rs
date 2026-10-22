//! FFI-слой для состояния рантайма.

use std::collections::HashMap;
use std::ops::{Deref, DerefMut};

use mnd_core::models::QuestTable;
use mnd_core::runtime::{InMemoryScriptRuntimeState, ScriptRuntime};

pub struct ScriptRuntimeState(InMemoryScriptRuntimeState);

impl ScriptRuntimeState {
    pub fn new() -> Self {
        Self(InMemoryScriptRuntimeState::default())
    }

    pub fn from_json(
        variables: HashMap<String, String>,
        tables: HashMap<String, HashMap<String, String>>,
    ) -> Self {
        let mut inner = InMemoryScriptRuntimeState::default();
        for (k, v) in variables {
            let value: serde_json::Value = serde_json::from_str(&v).unwrap_or_default();
            inner.set_variable(&k, value);
        }
        for (table_name, mut data) in tables {
            let full_json = data.remove("__table_full_json__");
            let table = if let Some(full_json) = full_json {
                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&full_json) {
                    let mut t = QuestTable::from_json(&parsed);
                    t.data.retain(|k, _| !k.starts_with("__"));
                    t
                } else {
                    let mut map = serde_json::Map::new();
                    for (k, v) in data {
                        if !k.starts_with("__") {
                            map.insert(k, serde_json::from_str(&v).unwrap_or_default());
                        }
                    }
                    QuestTable::new(table_name.clone(), vec![], vec![], map)
                }
            } else {
                let mut map = serde_json::Map::new();
                for (k, v) in data {
                    if !k.starts_with("__") {
                        map.insert(k, serde_json::from_str(&v).unwrap_or_default());
                    }
                }
                QuestTable::new(table_name.clone(), vec![], vec![], map)
            };
            inner.set_table(&table_name, table);
        }
        Self(inner)
    }

    pub fn get_variable_json(&self, key: String) -> Option<String> {
        self.0
            .get_variable(&key)
            .map(|v| serde_json::to_string(v).unwrap_or_default())
    }

    pub fn set_variable_json(&mut self, key: String, json_value: String) {
        let value: serde_json::Value = serde_json::from_str(&json_value).unwrap_or_default();
        self.0.set_variable(&key, value);
    }

    pub fn all_variables_json(&self) -> HashMap<String, String> {
        self.0
            .all_variables()
            .iter()
            .map(|(k, v)| (k.clone(), serde_json::to_string(v).unwrap_or_default()))
            .collect()
    }

    pub fn all_tables_json(&self) -> HashMap<String, HashMap<String, String>> {
        self.0
            .all_tables()
            .iter()
            .map(|(name, table)| {
                let mut data: HashMap<String, String> = table
                    .data
                    .iter()
                    .filter(|(k, _)| !k.starts_with("__"))
                    .map(|(k, v)| (k.clone(), serde_json::to_string(v).unwrap_or_default()))
                    .collect();
                let mut full_table_json = table.to_json();
                if let Some(data_obj) = full_table_json
                    .get_mut("data")
                    .and_then(|d| d.as_object_mut())
                {
                    data_obj.retain(|k, _| !k.starts_with("__"));
                }
                data.insert(
                    "__table_full_json__".to_string(),
                    serde_json::to_string(&full_table_json).unwrap_or_default(),
                );
                (name.clone(), data)
            })
            .collect()
    }
}

impl Default for ScriptRuntimeState {
    fn default() -> Self {
        Self::new()
    }
}

impl Deref for ScriptRuntimeState {
    type Target = InMemoryScriptRuntimeState;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for ScriptRuntimeState {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

impl ScriptRuntime for ScriptRuntimeState {
    fn all_variables(&self) -> &serde_json::Map<String, serde_json::Value> {
        self.0.all_variables()
    }

    fn all_tables(&self) -> &HashMap<String, QuestTable> {
        self.0.all_tables()
    }

    fn set_variable(&mut self, name: &str, value: serde_json::Value) {
        self.0.set_variable(name, value);
    }

    fn get_variable(&self, name: &str) -> Option<&serde_json::Value> {
        self.0.get_variable(name)
    }

    fn set_table(&mut self, table_name: &str, table: QuestTable) {
        self.0.set_table(table_name, table);
    }

    fn get_table(&self, table_name: &str) -> Option<&QuestTable> {
        self.0.get_table(table_name)
    }

    fn take_pacing_snapshot_variables(&mut self) -> Vec<(String, serde_json::Value)> {
        self.0.take_pacing_snapshot_variables()
    }

    fn take_pacing_snapshot_tables(&mut self) -> Vec<(String, serde_json::Value)> {
        self.0.take_pacing_snapshot_tables()
    }
}
