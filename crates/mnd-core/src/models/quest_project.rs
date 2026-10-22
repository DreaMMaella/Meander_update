//! `QuestProject`: квест + ноды + таблицы.

use std::collections::BTreeMap;

use serde_json::{Value, json};

/// Паритет: `packages/mnd_core/lib/models/quest_project.dart`.
#[derive(Debug, Clone, PartialEq)]
pub struct QuestProject {
    pub quest: super::quest_descriptor::Quest,
    pub nodes: Vec<super::saved_node::SavedNode>,
    pub tables: BTreeMap<String, super::quest_table::QuestTable>,
}

impl QuestProject {
    pub fn from_json(json: &Value) -> Self {
        let obj = json.as_object().cloned().unwrap_or_default();
        let quest =
            super::quest_descriptor::Quest::from_json(obj.get("quest").unwrap_or(&Value::Null));
        let nodes = obj
            .get("nodes")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .map(super::saved_node::SavedNode::from_json)
                    .collect()
            })
            .unwrap_or_default();
        let tables = obj
            .get("tables")
            .and_then(Value::as_object)
            .map(|o| {
                o.iter()
                    .map(|(k, v)| (k.clone(), super::quest_table::QuestTable::from_json(v)))
                    .collect()
            })
            .unwrap_or_default();
        QuestProject {
            quest,
            nodes,
            tables,
        }
    }

    pub fn to_json(&self) -> Value {
        let tables = self
            .tables
            .iter()
            .map(|(k, v)| (k.clone(), v.to_json()))
            .collect::<BTreeMap<_, _>>();
        json!({
            "quest": self.quest.to_json(),
            "nodes": self.nodes.iter().map(|n| n.to_json()).collect::<Vec<_>>(),
            "tables": tables,
        })
    }
}
