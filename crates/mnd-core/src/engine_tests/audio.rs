use super::*;

#[test]
fn drain_audio_commands_queue_multiple_sounds() {
    let mut engine = GameEngine::new(
        "q1".into(),
        Quest::from_json(&serde_json::Value::Null),
        vec![],
        vec![],
        GameEngineConfig::default(),
    );
    // Два звука + стоп-музыки за одно исполнение — ничего не теряется.
    engine.state.set_variable(
        "_internal_audio_queue",
        json!([
            {"type": "play_sound", "audio_id": "boom.mp3", "volume": 0.5},
            {"type": "play_sound", "audio_id": "hit.mp3", "volume": 1.0},
            {"type": "stop_music"}
        ]),
    );

    let delta = engine.drain_audio_commands();
    assert_eq!(
        delta.commands,
        vec![
            json!({"type": "playSound", "id": "boom.mp3", "volume": 0.5}),
            json!({"type": "playSound", "id": "hit.mp3", "volume": 1.0}),
            json!({"type": "stopMusic"}),
        ]
    );
    // очищено
    assert_eq!(
        engine.state.get_variable("_internal_audio_queue"),
        Some(&Value::Array(vec![]))
    );
    // второй вызов — пусто
    let delta2 = engine.drain_audio_commands();
    assert!(delta2.commands.is_empty());
}

fn engine_with_save_store() -> GameEngine {
    GameEngine::new(
        "q1".to_string(),
        Quest::from_json(&serde_json::json!({
            "id": "q1",
            "title": "Test Quest",
            "version": "2.0.0",
            "startNodeId": "node_1",
        })),
        vec![SavedNode::from_json(&serde_json::json!({
            "id": "node_1",
            "title": "Start",
            "content": { "items": [{ "type": "text", "id": "it1", "text": "Hi" }] },
        }))],
        vec![],
        GameEngineConfig {
            save_store: Some(std::sync::Arc::new(
                crate::contracts::InMemorySaveStore::new(),
            )),
            ..GameEngineConfig::default()
        },
    )
}

#[test]
fn save_slot_persists_current_state() {
    let mut engine = engine_with_save_store();
    engine.start_new(None).unwrap();
    engine.state.set_variable("hp", Value::from(42.0));

    let slot = engine.save_current_slot("Мой слот").unwrap();
    assert_eq!(slot.quest_id, "q1");
    assert_eq!(slot.slot_name, "Мой слот");
    assert_eq!(slot.current_node_id, "node_1");
    assert_eq!(slot.variables.get("hp"), Some(&Value::from(42.0)));

    let read = engine.read_save(&slot.id).unwrap();
    assert_eq!(read, slot);
}

#[test]
fn autosave_writes_system_slot() {
    let mut engine = engine_with_save_store();
    engine.start_new(None).unwrap();

    let slot = engine.perform_autosave().unwrap();
    assert_eq!(slot.id, "_autosave");
    assert_eq!(slot.current_node_id, "node_1");
    assert_eq!(engine.list_saves().len(), 1);
    assert!(engine.read_save("_autosave").is_some());

    engine.delete_save("_autosave");
    assert!(engine.read_save("_autosave").is_none());
    assert!(engine.list_saves().is_empty());
}

#[test]
fn save_slot_none_without_store_or_start() {
    let engine = GameEngine::new(
        "q1".to_string(),
        Quest::from_json(&serde_json::json!({
            "id": "q1",
            "title": "Test Quest",
            "version": "2.0.0",
            "startNodeId": "node_1",
        })),
        vec![],
        vec![],
        GameEngineConfig::default(),
    );
    assert!(engine.save_current_slot("x").is_none());
    assert!(engine.perform_autosave().is_none());
    assert!(engine.list_saves().is_empty());
}
