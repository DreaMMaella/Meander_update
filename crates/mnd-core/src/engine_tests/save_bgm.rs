//! Регрессия: после загрузки из сохранения музыка главы должна продолжать
//! играть (NodeView.background_audio должен быть заполнен как и при новой
//! игре).

use super::*;

fn bgm_quest(nodes: Vec<SavedNode>) -> GameEngine {
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "tags": [
            {"id": "ch1", "name": "Глава 1", "backgroundAudioId": "chapter_music.mp3"}
        ],
    }));
    GameEngine::new(
        quest.id.clone(),
        quest,
        nodes,
        vec![],
        GameEngineConfig {
            platform: PlatformInfo::default(),
            embedded_scripts: HashMap::new(),
            asset_store: None,
            save_store: None,
        },
    )
}

fn chapter_node(id: &str, title: &str) -> SavedNode {
    SavedNode::from_json(&serde_json::json!({
        "id": id, "title": title, "chapterId": "ch1",
        "content": { "items": [] },
    }))
}

#[test]
fn save_restore_keeps_chapter_bgm() {
    let mut engine = bgm_quest(vec![
        chapter_node("node_1", "Start"),
        chapter_node("node_2", "Next"),
    ]);

    let view = engine.start_new(None).expect("start_new");
    assert_eq!(
        view.background_audio.as_ref().unwrap().audio_id,
        "chapter_music.mp3",
        "новая игра: музыка главы присутствует"
    );

    engine.load_node("node_2").unwrap();
    let save = engine.to_save_slot("s1").expect("to_save_slot");
    assert_eq!(save.current_node_id, "node_2");

    // Новый движок — как при повторном запуске приложения / загрузке сейва.
    let mut engine2 = bgm_quest(vec![
        chapter_node("node_1", "Start"),
        chapter_node("node_2", "Next"),
    ]);
    let view2 = engine2.start_from_save(&save).expect("start_from_save");
    assert_eq!(view2.node_id, "node_2");
    assert!(
        view2.background_audio.is_some(),
        "после загрузки сейва музыка главы должна быть в NodeView"
    );
    assert_eq!(
        view2.background_audio.as_ref().unwrap().audio_id,
        "chapter_music.mp3"
    );
}

#[test]
fn script_play_music_persists_in_save() {
    // Скрипт запускает play_music (onNodeEnter), затем делаем сейв.
    // После загрузки сейва трек должен возобновиться: id/loop/volume
    // персистируются в переменных (_internal_active_script_bgm_*).
    let script = serde_json::json!({
        "name": "s1",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "play_music", "audio_id": "script_track.mp3", "loop": "true", "volume": "0.7", "children": []}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("s1.json".to_string(), script);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
    }));
    let n1 = SavedNode::from_json(&serde_json::json!({
        "id": "node_1", "title": "Start",
        "content": { "items": [] },
        "scriptAssetId": "s1.json",
    }));

    let mk_engine = || {
        GameEngine::new(
            quest.id.clone(),
            quest.clone(),
            vec![n1.clone()],
            vec![],
            GameEngineConfig {
                platform: PlatformInfo::default(),
                embedded_scripts: scripts.clone(),
                asset_store: None,
                save_store: None,
            },
        )
    };

    let mut engine = mk_engine();
    engine.start_new(None).unwrap();
    // Скрипт стартанул музыку. Дельта уходит клиенту в его контракте:
    // camelCase-тип и ключ `id` (см. `normalize_audio_command`).
    let d = engine.drain_audio_commands();
    let play = d
        .commands
        .iter()
        .find(|c| c.get("type").and_then(Value::as_str) == Some("playMusic"))
        .expect("playMusic в очереди");
    assert_eq!(
        play.get("id").and_then(Value::as_str),
        Some("script_track.mp3")
    );

    let save = engine.to_save_slot("s1").expect("to_save_slot");
    assert_eq!(
        save.variables.get("_internal_active_script_bgm_id"),
        Some(&Value::String("script_track.mp3".into())),
        "активная скриптовая музыка должна попасть в сейв"
    );

    // Новый движок — старт из сейва.
    let mut engine2 = mk_engine();
    let view = engine2.start_from_save(&save).unwrap();
    assert!(
        view.background_audio.is_none(),
        "у ноды нет своей/главовой музыки — NodeView без background_audio"
    );
    let snap = engine2.current_state_snapshot();
    assert_eq!(
        snap.variables
            .get("_internal_active_script_bgm_id")
            .cloned()
            .unwrap_or_default(),
        "\"script_track.mp3\"",
        "переменная восстановлена из сейва — клиент возобновит трек"
    );
}

#[test]
fn script_stop_music_clears_persisted_bgm() {
    let script = serde_json::json!({
        "name": "s1",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "play_music", "audio_id": "script_track.mp3", "children": []},
                {"type": "stop_music", "children": []}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("s1.json".to_string(), script);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
    }));
    let n1 = SavedNode::from_json(&serde_json::json!({
        "id": "node_1", "title": "Start",
        "content": { "items": [] },
        "scriptAssetId": "s1.json",
    }));
    let mut engine = GameEngine::new(
        quest.id.clone(),
        quest,
        vec![n1],
        vec![],
        GameEngineConfig {
            platform: PlatformInfo::default(),
            embedded_scripts: scripts,
            asset_store: None,
            save_store: None,
        },
    );
    engine.start_new(None).unwrap();
    let _ = engine.drain_audio_commands();

    let save = engine.to_save_slot("s1").unwrap();
    assert_eq!(
        save.variables.get("_internal_active_script_bgm_id"),
        Some(&Value::Null),
        "после stop_music в сейве не должно быть активного трека"
    );
}

#[test]
fn save_restore_keeps_node_bgm() {
    let n1 = SavedNode::from_json(&serde_json::json!({
        "id": "node_1", "title": "Start",
        "backgroundAudioId": "own_music.mp3", "backgroundAudioVolume": 0.4,
        "content": { "items": [] },
    }));
    let mut engine = bgm_quest(vec![n1.clone()]);
    let _ = engine.start_new(None).unwrap();
    let save = engine.to_save_slot("s1").expect("to_save_slot");

    let mut engine2 = bgm_quest(vec![n1]);
    let view2 = engine2.start_from_save(&save).unwrap();
    let audio = view2
        .background_audio
        .expect("музыка ноды после загрузки сейва");
    assert_eq!(audio.audio_id, "own_music.mp3");
    assert_eq!(audio.volume, 0.4);
}
