use super::*;
use serde_json::{Value, json};

fn engine_with(
    quest: Quest,
    nodes: Vec<SavedNode>,
    embedded_scripts: HashMap<String, Value>,
) -> GameEngine {
    GameEngine::new(
        quest.id.clone(),
        quest,
        nodes,
        vec![],
        GameEngineConfig {
            platform: PlatformInfo::default(),
            embedded_scripts,
            asset_store: None,
            save_store: None,
        },
    )
}

fn node(id: &str, title: &str, items: Vec<Value>) -> SavedNode {
    SavedNode::from_json(&serde_json::json!({
        "id": id,
        "title": title,
        "content": { "items": items },
    }))
}

// ─── Баг 4: числовой формат через движок ───────────────────────────────

#[test]
fn bug4_engine_evaluate_expression_returns_int_json() {
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
    }));
    let mut engine = engine_with(quest, vec![node("node_1", "Start", vec![])], HashMap::new());
    engine.start_new(None).unwrap();

    assert_eq!(engine.evaluate_expression(&json!("12.0").to_string()), "12");
    assert_eq!(
        engine.evaluate_expression(&json!("2 + 3 * 4").to_string()),
        "14"
    );
    assert_eq!(
        engine.evaluate_expression(&json!("10 / 4").to_string()),
        "2.5"
    );
}

// ─── Цикл шаблона через контейнер (stack overflow guard) ─────────────

#[test]
fn resolve_item_tree_guards_template_cycle_through_container() {
    // Шаблон T: row → container → template-instance T. Самоцикл проходит
    // через НЕ-шаблонный контейнер: если дети контейнера резолвятся
    // новым visited-сетом, гард рвётся и рекурсия бесконечна.
    let template = TemplateItem::new(
        "tmpl-cycle".to_string(),
        "Cycle".to_string(),
        crate::models::TemplateKind::Row,
        serde_json::json!({
            "type": "row",
            "id": "$",
            "children": [{
                "type": "container",
                "id": "$-c",
                "children": [{
                    "type": "text",
                    "id": "$-c-1",
                    "templateRef": "tmpl-cycle",
                }],
            }],
        })
        .as_object()
        .unwrap()
        .clone(),
        None,
        None,
        None,
        vec![],
    );
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
    }));
    let items = vec![serde_json::json!({
        "type": "row",
        "id": "inst-1",
        "templateRef": "tmpl-cycle",
    })];
    let mut engine = GameEngine::new(
        "q1".to_string(),
        quest,
        vec![node("node_1", "Start", items)],
        vec![template],
        GameEngineConfig::default(),
    );
    engine.start_new(None).unwrap();

    // next_item должен вернуть элемент, не уходя в бесконечную рекурсию.
    let step = engine.next_item();
    assert!(
        matches!(step, NextStep::Item(_)) || matches!(step, NextStep::Done),
        "resolve_item_tree зациклился на шаблоне-самоцикле"
    );
}

// ─── Баги 1/2/3: wait через движок (боевой скрипт) ─────────────────────

#[test]
fn bug123_engine_battle_script_waits_land_in_state_delta() {
    let battle = serde_json::json!({
        "name": "battle",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "assign_variable", "variable": "stance", "value": "1"},
                {"type": "wait", "expression": "500"},
                {"type": "assign_variable", "variable": "hp", "value": "hp - 10"},
                {"type": "wait", "expression": "250"},
                {"type": "assign_variable", "variable": "stance", "value": "0"}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("battle.json".to_string(), battle);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "hp", "defaultValue": 100}],
    }));
    let nodes = vec![SavedNode::from_json(&serde_json::json!({
        "id": "node_1",
        "title": "Start",
        "content": { "items": [] },
        "scriptAssetId": "battle.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    // Очередь шагов: каждый несёт ms + снапшот промежуточного состояния.
    let queue = engine
        .state
        .get_variable("_internal_delay_queue")
        .cloned()
        .expect("delay queue");
    let queue = queue.as_array().expect("array");
    assert_eq!(queue.len(), 2);
    assert_eq!(queue[0]["ms"], 500);
    assert_eq!(queue[0]["variables"]["stance"], "1");
    assert_eq!(queue[1]["ms"], 250);
    assert_eq!(queue[1]["variables"]["hp"], "90");
    assert_eq!(engine.state.get_variable("stance"), Some(&json!(0)));
    assert_eq!(engine.state.get_variable("hp"), Some(&json!(90)));

    // Очередь доезжает до клиента через state-дельту и полный drain.
    let delta = engine.drain_state_delta();
    let queue_json = delta
        .variables
        .get("_internal_delay_queue")
        .expect("queue in delta");
    let parsed: Value = serde_json::from_str(queue_json).unwrap();
    assert_eq!(parsed.as_array().unwrap().len(), 2);
    let steps = engine.drain_delay_steps();
    assert_eq!(steps.len(), 2);
    assert_eq!(steps[0]["variables"]["stance"], "1");
}

#[test]
fn drain_delay_queue_returns_ms_and_clears() {
    let battle = serde_json::json!({
        "name": "battle",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "wait", "expression": "500"},
                {"type": "wait", "expression": "250"},
                {"type": "go_to_node", "node_id": "node_2"}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("battle.json".to_string(), battle);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
    }));
    let nodes = vec![
        SavedNode::from_json(&serde_json::json!({
            "id": "node_1",
            "title": "Start",
            "content": { "items": [] },
            "scriptAssetId": "battle.json",
        })),
        node("node_2", "Next", vec![]),
    ];
    let mut engine = engine_with(quest, nodes, scripts);
    let view = engine.start_new(None).unwrap();
    // Переход возвращается сразу — задержка покрывается очередью.
    assert_eq!(view.transition.as_deref(), Some("node_2"));

    assert_eq!(engine.drain_delay_queue(), vec![500, 250]);
    // Повторный drain — пусто (очередь очищается).
    assert_eq!(engine.drain_delay_queue(), Vec::<i64>::new());

    // Задержка не всплывает в сейв-слоте как стейл-состояние.
    let slot = engine.to_save_slot("test").unwrap();
    assert_eq!(
        slot.variables.get("_internal_delay_queue"),
        Some(&json!([]))
    );
}

#[test]
fn wait_steps_carry_intermediate_state_snapshots() {
    // Паритет Dart-эталона: assign → wait → assign → wait.
    // Клиент обязан видеть ПРОМЕЖУТОЧНЫЕ values на каждом шаге —
    // именно на этом строятся анимации «смена кадров» через условные
    // видимости картинок. Плюс: звук до `wait` прибит к шагу.
    let battle = serde_json::json!({
        "name": "battle",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "assign_variable", "variable": "frame", "value": "1"},
                {"type": "play_sound", "audio_id": "swing.mp3"},
                {"type": "wait", "expression": "500"},
                {"type": "assign_variable", "variable": "frame", "value": "2"},
                {"type": "wait", "expression": "250"},
                {"type": "assign_variable", "variable": "frame", "value": "0"}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("battle.json".to_string(), battle);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
    }));
    let nodes = vec![SavedNode::from_json(&serde_json::json!({
        "id": "node_1",
        "title": "Start",
        "content": { "items": [] },
        "scriptAssetId": "battle.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    let steps = engine.drain_delay_steps();
    assert_eq!(steps.len(), 2);

    assert_eq!(steps[0]["ms"], 500);
    assert_eq!(steps[0]["variables"]["frame"], "1");
    assert_eq!(
        steps[0]["audio"],
        json!([{"type": "playSound", "id": "swing.mp3", "volume": 1.0}])
    );

    assert_eq!(steps[1]["ms"], 250);
    assert_eq!(steps[1]["variables"]["frame"], "2");
    assert_eq!(steps[1]["audio"], json!([]));

    // После всех шагов состояние — финальное.
    assert_eq!(engine.state.get_variable("frame"), Some(&json!(0)));
    // Повторный drain пуст.
    assert!(engine.drain_delay_steps().is_empty());
}

// ─── Таймер-цикл (energy → wait → energy): тики через run_scheduled_timer ──
#[test]
fn bug_energy_timer_ticks_via_scheduled_timer() {
    let enter = serde_json::json!({
        "name": "блок",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "call_function", "function_id": "energy", "function_entry": "energy"}
            ]}
        ]
    });
    let energy = serde_json::json!({
        "name": "energy",
        "blocks": [
            {"type": "event", "eventType": "function", "functionName": "energy", "children": [
                {"type": "condition", "expression": "{энергия}<100", "then_blocks": [
                    {"type": "assign_variable", "variable": "энергия", "value": "{энергия}+1"}
                ]},
                {"type": "wait", "expression": "2000"},
                {"type": "call_function", "function_id": "energy", "function_entry": "energy"}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("scripts/enter.json".to_string(), enter);
    scripts.insert("scripts/energy.json".to_string(), energy);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "энергия", "defaultValue": 10}],
    }));
    let nodes = vec![SavedNode::from_json(&serde_json::json!({
        "id": "node_1",
        "title": "Start",
        "content": { "items": [] },
        "scriptAssetId": "scripts/enter.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    // Первый тик сделан синхронно, рекурсия не пошла (энергия = 11, не 74).
    assert_eq!(engine.state.get_variable("энергия"), Some(&json!(11)));
    let timers = engine.pending_timers();
    assert_eq!(timers.len(), 1);
    assert_eq!(timers[0].script_path, "scripts/energy.json");
    assert_eq!(timers[0].entry, "energy");
    assert_eq!(timers[0].ms, 2000);

    // Клиент ждёт 2000 мс и дёргает тик: +1 энергия, следующий тик в расписании.
    for expected in [12, 13, 14] {
        let transition = engine.run_scheduled_timer("scripts/energy.json", "energy");
        assert_eq!(transition, None);
        assert_eq!(engine.state.get_variable("энергия"), Some(&json!(expected)));
        assert_eq!(engine.pending_timers().len(), 1);
    }

    // Очередь задержек тика покрыта таймером — она не растёт.
    assert_eq!(
        engine.state.get_variable("_internal_delay_queue"),
        Some(&serde_json::json!([]))
    );
}

// ─── Вторичный баг: коэрция "false"→bool в условии `{первый вход}==false` ──
#[test]
fn bug_config_string_false_matches_bool_literal_in_condition() {
    let tables_script = serde_json::json!({
        "name": "таблицы",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "condition", "expression": "{первый вход}==false", "then_blocks": [
                    {"type": "assign_variable", "variable": "Копатель.копатель1.уровень", "value": "1"},
                    {"type": "assign_variable", "variable": "цена.мызыка", "value": "true"},
                    {"type": "assign_variable", "variable": "текст.мызыка", "value": "Включен"},
                    {"type": "assign_variable", "variable": "первый вход", "value": "true"}
                ], "else_blocks": []}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("scripts/tables.json".to_string(), tables_script);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "первый вход", "defaultValue": "false"}],
    }));
    let nodes = vec![SavedNode::from_json(&serde_json::json!({
        "id": "node_1",
        "title": "Start",
        "content": { "items": [] },
        "scriptAssetId": "scripts/tables.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    // Ветка «первый вход» сработала: set'ы таблиц и текст включены.
    assert_eq!(
        engine.state.get_variable("Копатель.копатель1.уровень"),
        Some(&json!(1))
    );
    assert_eq!(engine.state.get_variable("цена.мызыка"), Some(&json!(true)));
    assert_eq!(
        engine.state.get_variable("текст.мызыка"),
        Some(&json!("Включен"))
    );
    assert_eq!(engine.state.get_variable("первый вход"), Some(&json!(true)));

    // Повторный вход ноды: первый вход уже true — init не повторяется.
    engine.load_node("node_1");
    assert_eq!(engine.state.get_variable("цена.мызыка"), Some(&json!(true)));
}

// ─── Баг 6: звуки по нажатию триггерятся заново ────────────────────────

#[test]
fn bug6_engine_repeated_press_play_sound_retriggers() {
    let btn = serde_json::json!({
        "name": "btn",
        "blocks": [
            {"type": "event", "eventType": "onPress", "children": [
                // Формат, который встречается в импортированных скриптах.
                {"type": "play_sound", "audioId": "sfx/click.wav", "volume": "0.9"}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("scripts/btn.json".to_string(), btn);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
    }));
    let nodes = vec![node("node_1", "Start", vec![])];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    let item = ContentItem::from_json(&serde_json::json!({
        "type": "button",
        "id": "b1",
        "scriptTriggers": {"onPress": "scripts/btn.json"}
    }));

    // Первое нажатие.
    assert_eq!(engine.handle_interaction(&item, "scripts/btn.json"), None);
    let d1 = engine.drain_audio_commands();
    assert_eq!(
        d1.commands,
        vec![json!({"type": "playSound", "id": "sfx/click.wav", "volume": 0.9})]
    );
    // Повторный drain — пусто (команда одноразовая).
    let d1b = engine.drain_audio_commands();
    assert!(d1b.commands.is_empty());

    // Второе нажатие — звук должен триггериться заново.
    assert_eq!(engine.handle_interaction(&item, "scripts/btn.json"), None);
    let d2 = engine.drain_audio_commands();
    assert_eq!(
        d2.commands,
        vec![json!({"type": "playSound", "id": "sfx/click.wav", "volume": 0.9})]
    );
}

// ─── Баг 7: фоновая музыка главы не перезапускается ───────────────────

fn chapter_quest(nodes: Vec<SavedNode>, scripts: HashMap<String, Value>) -> GameEngine {
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "tags": [
            {"id": "ch1", "name": "Глава 1", "backgroundAudioId": "chapter_music.mp3"}
        ],
    }));
    engine_with(quest, nodes, scripts)
}

#[test]
fn bug7_chapter_bgm_present_in_view_and_no_restart_commands() {
    let n1 = SavedNode::from_json(&serde_json::json!({
        "id": "node_1", "title": "Start", "chapterId": "ch1",
        "content": { "items": [{"type": "text", "id": "a", "text": "one"}] },
    }));
    let n2 = SavedNode::from_json(&serde_json::json!({
        "id": "node_2", "title": "Next", "chapterId": "ch1",
        "content": { "items": [{"type": "text", "id": "b", "text": "two"}] },
    }));
    let mut engine = chapter_quest(vec![n1, n2], HashMap::new());

    let view1 = engine.start_new(None).unwrap();
    let audio1 = view1.background_audio.expect("музыка главы в NodeView");
    assert_eq!(audio1.audio_id, "chapter_music.mp3");
    assert_eq!(audio1.volume, 1.0);

    // Движок не эмитит play/stop для фоновой музыки ноды/главы —
    // рестарт на стороне клиента решается сравнением id.
    let d = engine.drain_audio_commands();
    assert!(d.commands.is_empty());

    // Переход на соседнюю ноду той же главы — та же музыка.
    let view2 = engine.load_node("node_2").unwrap();
    let audio2 = view2.background_audio.expect("музыка главы в NodeView");
    assert_eq!(audio2.audio_id, "chapter_music.mp3");
    // Никаких команд стоп/плей — клиент НЕ должен рестартовать трек.
    let d2 = engine.drain_audio_commands();
    assert!(d2.commands.is_empty());
}

#[test]
fn bug7_node_own_bgm_overrides_chapter_audio() {
    let n1 = SavedNode::from_json(&serde_json::json!({
        "id": "node_1", "title": "Start", "chapterId": "ch1",
        "backgroundAudioId": "own_music.mp3", "backgroundAudioVolume": 0.5,
        "content": { "items": [] },
    }));
    let mut engine = chapter_quest(vec![n1], HashMap::new());
    let view = engine.start_new(None).unwrap();
    let audio = view.background_audio.expect("своя музыка ноды");
    assert_eq!(audio.audio_id, "own_music.mp3");
    assert_eq!(audio.volume, 0.5);
}

// ─── Баг 8: crossfade должен доходить до drain_audio_commands ──────────

// РЕГРЕССИЯ: старый Dart-движок выставлял _internal_crossfade_fade_out/in,
// их читает drain_audio_commands → клиент анимирует fade. Rust-порт пишет
// только в _internal_audio_queue, поэтому crossfadeFadeOutMs всегда None —
// клиентская кроссфейд-анимация не запускается.
#[test]
fn bug8_engine_crossfade_drain_returns_fade_times() {
    let cf = serde_json::json!({
        "name": "cf",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "crossfade", "duration": "1.5", "children": []}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("cf.json".to_string(), cf);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
    }));
    let nodes = vec![SavedNode::from_json(&serde_json::json!({
        "id": "node_1", "title": "Start",
        "content": { "items": [] },
        "scriptAssetId": "cf.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    let delta = engine.drain_audio_commands();
    assert_eq!(
        delta.commands,
        vec![
            json!({"type": "fadeOut", "ms": 1500}),
            json!({"type": "fadeIn", "ms": 1500}),
        ]
    );
}

// ─── Баг 9: мутация onContentAppear ровно один раз ─────────────────────

#[test]
fn bug9_engine_on_content_appear_mutation_happens_exactly_once() {
    let gacha = serde_json::json!({
        "name": "gacha",
        "blocks": [
            {"type": "event", "eventType": "onContentAppear", "children": [
                {"type": "assign_variable", "variable": "Примогемы", "value": "Примогемы - 160"}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("scripts/gacha.json".to_string(), gacha);
    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "Примогемы", "defaultValue": 200}],
    }));
    let nodes = vec![node(
        "node_1",
        "Start",
        vec![
            serde_json::json!({"type": "script", "id": "s1", "resourcePath": "scripts/gacha.json"}),
            serde_json::json!({"type": "text", "id": "t1", "text": "Результат"}),
        ],
    )];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();
    assert_eq!(engine.state.get_variable("Примогемы"), Some(&json!(200)));

    // Раскрытие script-айтема выполняет onContentAppear — мутация 1 раз.
    match engine.next_item() {
        NextStep::Item(item) => assert_eq!(item.item_type, "text"),
        other => panic!("expected text item, got {other:?}"),
    }
    assert_eq!(engine.state.get_variable("Примогемы"), Some(&json!(40)));

    // Дальнейшие шаги не мутируют повторно (нет x2).
    matches!(engine.next_item(), NextStep::Done);
    assert_eq!(engine.state.get_variable("Примогемы"), Some(&json!(40)));

    // В дельте одно финальное значение, повторный drain пуст.
    let delta = engine.drain_state_delta();
    assert_eq!(
        delta.variables.get("Примогемы").map(String::as_str),
        Some("40")
    );
    let delta2 = engine.drain_state_delta();
    assert!(!delta2.variables.contains_key("Примогемы"));
}

// ─── Cycle-guard: циклические ссылки шаблонов не зависают ──────────────

#[test]
fn template_cycle_self_reference_terminates() {
    // Шаблон A ссылается сам на себя через своего же payload-ребёнка.
    // Без `visited`-гарда рекурсия ушла бы в бесконечность.
    let template = TemplateItem::from_json(&json!({
        "id": "tplA",
        "name": "A",
        "kind": "column",
        "payload": {
            "type": "column",
            "children": [
                {"type": "column", "templateRef": "tplA"}
            ]
        }
    }));
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
    }));
    let nodes = vec![node(
        "node_1",
        "Start",
        vec![json!({
            "type": "column",
            "id": "inst1",
            "templateRef": "tplA"
        })],
    )];
    let mut engine = GameEngine::new(
        "q1".to_string(),
        quest,
        nodes,
        vec![template],
        GameEngineConfig {
            platform: PlatformInfo::default(),
            embedded_scripts: HashMap::new(),
            asset_store: None,
            save_store: None,
        },
    );
    engine.start_new(None).unwrap();

    match engine.next_item() {
        NextStep::Item(item) => {
            assert_eq!(item.id, "inst1");
            // Ребёнок-цикл оборван гардом (id не tpl_*, рекурсия прервана).
            let child = item.children.as_ref().unwrap().first().unwrap();
            assert_eq!(child.template_ref.as_deref(), Some("tplA"));
        }
        other => panic!("expected item, got {other:?}"),
    }
}

// ─── While: простые режимы (count / range / loop_var) ──────────────────

fn counter_script(count_block: Value) -> Value {
    json!({
        "name": "counter",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                count_block
            ]}
        ]
    })
}

#[test]
fn while_count_repeats_and_sets_loop_var() {
    let script = counter_script(json!({
        "type": "while", "count": 3, "loop_var": "i",
        "children": [
            {"type": "assign_variable", "variable": "тест", "value": "{тест} + 1"},
            {"type": "assign_variable", "variable": "last_i", "value": "{i}"}
        ]
    }));
    let mut scripts = HashMap::new();
    scripts.insert("scripts/counter.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "тест", "defaultValue": 0}],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start", "content": {"items": []},
        "scriptAssetId": "scripts/counter.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    assert_eq!(engine.state.get_variable("тест"), Some(&json!(3)));
    assert_eq!(engine.state.get_variable("last_i"), Some(&json!(3)));
}

#[test]
fn while_range_ascending_with_step_and_loop_var() {
    let script = counter_script(json!({
        "type": "while", "from": 1, "to": 5, "step": 2, "loop_var": "i",
        "children": [
            {"type": "assign_variable", "variable": "тест", "value": "{тест} + 1"},
            {"type": "assign_variable", "variable": "last_i", "value": "{i}"}
        ]
    }));
    let mut scripts = HashMap::new();
    scripts.insert("scripts/counter.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "тест", "defaultValue": 0}],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start", "content": {"items": []},
        "scriptAssetId": "scripts/counter.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    // 1, 3, 5 → три итерации, счётчик остановился на 5.
    assert_eq!(engine.state.get_variable("тест"), Some(&json!(3)));
    assert_eq!(engine.state.get_variable("last_i"), Some(&json!(5)));
}

#[test]
fn while_range_descending() {
    let script = counter_script(json!({
        "type": "while", "from": 5, "to": 1, "step": -2,
        "children": [
            {"type": "assign_variable", "variable": "тест", "value": "{тест} + 1"}
        ]
    }));
    let mut scripts = HashMap::new();
    scripts.insert("scripts/counter.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "тест", "defaultValue": 0}],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start", "content": {"items": []},
        "scriptAssetId": "scripts/counter.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    assert_eq!(engine.state.get_variable("тест"), Some(&json!(3)));
}

#[test]
fn while_expression_has_priority_over_count() {
    let script = counter_script(json!({
        "type": "while", "expression": "false", "count": 5,
        "children": [
            {"type": "assign_variable", "variable": "тест", "value": "{тест} + 1"}
        ]
    }));
    let mut scripts = HashMap::new();
    scripts.insert("scripts/counter.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "тест", "defaultValue": 0}],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start", "content": {"items": []},
        "scriptAssetId": "scripts/counter.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    assert_eq!(engine.state.get_variable("тест"), Some(&json!(0)));
}

#[test]
fn while_without_any_mode_skips() {
    let script = counter_script(json!({
        "type": "while",
        "children": [
            {"type": "assign_variable", "variable": "тест", "value": "{тест} + 1"}
        ]
    }));
    let mut scripts = HashMap::new();
    scripts.insert("scripts/counter.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "тест", "defaultValue": 0}],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start", "content": {"items": []},
        "scriptAssetId": "scripts/counter.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    assert_eq!(engine.state.get_variable("тест"), Some(&json!(0)));
}

#[test]
fn while_count_capped_by_max_iterations() {
    let script = counter_script(json!({
        "type": "while", "count": 100000, "max_iterations": 50,
        "children": [
            {"type": "assign_variable", "variable": "тест", "value": "{тест} + 1"}
        ]
    }));
    let mut scripts = HashMap::new();
    scripts.insert("scripts/counter.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "тест", "defaultValue": 0}],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start", "content": {"items": []},
        "scriptAssetId": "scripts/counter.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    assert_eq!(engine.state.get_variable("тест"), Some(&json!(50)));
}

// ─── Inline content-script: пользовательский сценарий end-to-end ───────

#[test]
fn inline_content_script_runs_on_node_enter() {
    // Ровно сценарий из багрепорта: контент-айтем type=script с resourcePath,
    // внутри — простой цикл повторений с присвоением переменной.
    let script = counter_script(json!({
        "type": "while", "count": 100, "loop_var": "i",
        "children": [
            {"type": "assign_variable", "variable": "тест", "value": "{тест} + 1"}
        ]
    }));
    let mut scripts = HashMap::new();
    scripts.insert("scripts/531a7645.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "тест", "defaultValue": 0}],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start",
        "content": {"items": [
            {"id": "it1", "type": "script", "resourcePath": "scripts/531a7645.json"},
            {"id": "it2", "type": "text", "text": "{тест}"}
        ]},
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    assert_eq!(engine.state.get_variable("тест"), Some(&json!(100)));
}

// ─── Багрепорт: count строкой «3» исполнялся как бесконечный цикл ──────
// Старый код имел string_field(expression, "1 == 1") — при отсутствии
// expression цикл становился вечным и упирался в лимит 2000 шагов
// (~999 итераций вместо 3). Тест — ТОЧНЫЙ JSON из багрепорта.

#[test]
fn while_count_as_string_runs_exactly_n_times() {
    // Дословно блок while из скрипта пользователя (id сохранены).
    let script = json!({
        "id": "531a7645-0103-42c8-913a-157c6df82b68",
        "name": "Скрипт 2",
        "blocks": [
            {
                "type": "event",
                "id": "578cc2ae-c7b4-4a6e-8780-a81243ced52a",
                "eventType": "onNodeEnter",
                "children": [
                    {
                        "type": "while",
                        "id": "3d38b77f-9a44-4f5a-bd59-541d74010bd0",
                        "count": "3",
                        "children": [
                            {
                                "type": "assign_variable",
                                "id": "b531a8d9-f880-4a7b-b0b5-04576d0536a4",
                                "variable": "тест",
                                "value": "{тест}+1"
                            }
                        ],
                        "collapsed": false,
                        "max_iterations": 10000
                    }
                ],
                "collapsed": false
            }
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("scripts/531a7645.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "variables": [{"name": "тест", "defaultValue": 0}],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start",
        "content": {"items": [
            {"id": "it1", "type": "script", "resourcePath": "scripts/531a7645.json"},
            {"id": "it2", "type": "text", "text": "{тест}"}
        ]},
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    // Раньше здесь было 999 + "script limit exceeded (max 2000 steps)".
    assert_eq!(engine.state.get_variable("тест"), Some(&json!(3)));
}

// ─── table_operation: remove и contains (раньше были тихим no-op) ──────

#[test]
fn table_operation_remove_and_contains() {
    let script = json!({
        "name": "tables_ops",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "table_operation", "operation": "add",
                 "tableName": "инвентарь", "path": "items", "value": "'меч'"},
                {"type": "table_operation", "operation": "add",
                 "tableName": "инвентарь", "path": "items", "value": "'щит'"},
                {"type": "table_operation", "operation": "contains",
                 "tableName": "инвентарь", "path": "items", "value": "'щит'",
                 "targetVariable": "есть_щит"},
                {"type": "table_operation", "operation": "remove",
                 "tableName": "инвентарь", "path": "items[0]"},
                {"type": "table_operation", "operation": "contains",
                 "tableName": "инвентарь", "path": "items", "value": "'меч'",
                 "targetVariable": "есть_меч"},
                {"type": "table_operation", "operation": "get",
                 "tableName": "инвентарь", "path": "items[0]",
                 "targetVariable": "первый_предмет"}
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("scripts/ops.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "tables": [
            {"name": "инвентарь", "columns": [], "rows": [], "data": {}}
        ],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start", "content": {"items": []},
        "scriptAssetId": "scripts/ops.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    assert_eq!(engine.state.get_variable("есть_щит"), Some(&json!(true)));
    assert_eq!(engine.state.get_variable("есть_меч"), Some(&json!(false)));
    // После удаления items[0]="меч" первым стал "щит".
    assert_eq!(
        engine.state.get_variable("первый_предмет"),
        Some(&json!("щит"))
    );
}

// ─── table_operation: «Удалить значение» и пустой путь (#220) ──────────

#[test]
fn table_operation_remove_value_and_empty_path() {
    let script = json!({
        "name": "tables_delete",
        "blocks": [
            {"type": "event", "eventType": "onNodeEnter", "children": [
                {"type": "table_operation", "operation": "add",
                 "tableName": "инвентарь", "path": "items", "value": "'лук'"},
                {"type": "table_operation", "operation": "add",
                 "tableName": "инвентарь", "path": "items", "value": "'меч'"},
                {"type": "table_operation", "operation": "add",
                 "tableName": "инвентарь", "path": "items", "value": "'топор'"},
                {"type": "table_operation", "operation": "remove_value",
                 "tableName": "инвентарь", "path": "items", "value": "'меч'"},
                {"type": "table_operation", "operation": "get",
                 "tableName": "инвентарь", "path": "items",
                 "targetVariable": "остаток"},
                // Пустого пути в редакторе не видно (поле выключено), а движок
                // разворачивал "" в ключ «null»: запись уезжала в призрачный
                // ключ, «Очистить» ничего не чистил.
                {"type": "table_operation", "operation": "set",
                 "tableName": "счётчик", "path": "", "value": "7"},
                {"type": "table_operation", "operation": "contains",
                 "tableName": "сундук", "path": "", "value": "'ключ'",
                 "targetVariable": "есть_ключ"},
                {"type": "table_operation", "operation": "clear",
                 "tableName": "сундук", "path": ""},
            ]}
        ]
    });
    let mut scripts = HashMap::new();
    scripts.insert("scripts/delete.json".to_string(), script);
    let quest = Quest::from_json(&json!({
        "id": "q1", "title": "Q", "version": "2.0.0", "startNodeId": "node_1",
        "tables": [
            {"name": "инвентарь", "columns": [], "rows": [], "data": {}},
            {"name": "счётчик", "columns": [], "rows": [], "data": {}},
            {"name": "сундук", "columns": [], "rows": [],
             "data": {"а": "ключ", "б": "верёвка"}}
        ],
    }));
    let nodes = vec![SavedNode::from_json(&json!({
        "id": "node_1", "title": "Start", "content": {"items": []},
        "scriptAssetId": "scripts/delete.json",
    }))];
    let mut engine = engine_with(quest, nodes, scripts);
    engine.start_new(None).unwrap();

    assert_eq!(
        engine.state.get_variable("остаток"),
        Some(&json!(["лук", "топор"])),
        "«Удалить значение» должен убрать одно совпадение из списка"
    );
    let phantom = engine.state.get_table("счётчик").expect("таблица на месте");
    assert!(
        !phantom.data.contains_key("null"),
        "запись без пути не должна плодить служебный ключ: {:?}",
        phantom.data
    );
    assert_eq!(
        engine.state.get_table("сундук").unwrap().data,
        Map::new(),
        "«Очистить» без пути чистит всю таблицу"
    );
    assert_eq!(engine.state.get_variable("есть_ключ"), Some(&json!(true)));
}
