//! Тесты на behaviours (ContentTrigger): evaluate_visibility + execute_behaviour.
//! Живут отдельно, чтобы не раздувать engine.rs тестовый модуль.

#[cfg(test)]
mod behaviour_tests {
    use std::collections::HashMap;

    use serde_json::Value;

    use mnd_core::engine::{GameEngine, GameEngineConfig};
    use mnd_core::models::{ContentItem, Quest, SavedNode};

    fn config(quest_id: &str) -> Quest {
        Quest::from_json(&serde_json::json!({
            "id": quest_id,
            "title": "Test",
            "startNodeId": "n1",
        }))
    }

    fn simple_engine(nodes: Vec<SavedNode>) -> GameEngine {
        GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig::default(),
        )
    }

    fn text_node(node_id: &str, items: Vec<Value>) -> SavedNode {
        SavedNode::from_json(&serde_json::json!({
            "id": node_id,
            "title": "Node",
            "content": { "items": items },
        }))
    }

    // =========================================================================
    // evaluate_visibility: legacy scriptTriggers
    // =========================================================================

    #[test]
    fn visibility_true_when_no_onappear() {
        let nodes = vec![text_node(
            "n1",
            vec![serde_json::json!({"type": "text", "id": "t1", "text": "Hi"})],
        )];
        let mut engine = simple_engine(nodes);
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!(
            {"type": "text", "id": "t1", "text": "Hi"}
        ));
        assert!(engine.evaluate_visibility(&item, false));
    }

    #[test]
    fn visibility_true_when_no_condition_in_script() {
        let nodes = vec![text_node(
            "n1",
            vec![serde_json::json!({
                "type": "text",
                "id": "t2",
                "text": "Visible",
                "scriptTriggers": {"onAppear": "scripts/show.json"}
            })],
        )];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/show.json".into(),
                    serde_json::json!({
                        "name": "show",
                        "blocks": [{
                            "type": "event",
                            "eventType": "onContentAppear",
                            "children": [
                                {"type": "condition", "expression": "1==1", "then_blocks": [], "else_blocks": []}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "text", "id": "t2",
            "scriptTriggers": {"onAppear": "scripts/show.json"}
        }));
        // 1==1 → visible
        assert!(engine.evaluate_visibility(&item, false));
    }

    #[test]
    fn visibility_false_when_condition_fails() {
        let nodes = vec![text_node(
            "n1",
            vec![serde_json::json!({
                "type": "text",
                "id": "hidden_text",
                "scriptTriggers": {"onAppear": "scripts/hidden.json"}
            })],
        )];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/hidden.json".into(),
                    serde_json::json!({
                        "name": "hidden",
                        "blocks": [{
                            "type": "event",
                            "eventType": "onContentAppear",
                            "children": [
                                {"type": "condition", "expression": "1==0", "then_blocks": [], "else_blocks": []}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "text", "id": "hidden_text",
            "scriptTriggers": {"onAppear": "scripts/hidden.json"}
        }));
        // 1==0 → not visible
        assert!(!engine.evaluate_visibility(&item, false));
    }

    // =========================================================================
    // evaluate_visibility: new behaviours format
    // =========================================================================

    #[test]
    fn visibility_with_behaviours_kind_visibility() {
        let nodes = vec![text_node(
            "n1",
            vec![serde_json::json!({
                "type": "text",
                "id": "t1",
                "behaviours": [
                    {"event": "onAppear", "script": "scripts/vis.json", "kind": "visibility"}
                ]
            })],
        )];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/vis.json".into(),
                    serde_json::json!({
                        "name": "vis",
                        "blocks": [{
                            "type": "event",
                            "eventType": "onContentAppear",
                            "children": [
                                {"type": "condition", "expression": "0==0", "then_blocks": [], "else_blocks": []}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "text", "id": "t1",
            "behaviours": [
                {"event": "onAppear", "script": "scripts/vis.json", "kind": "visibility"}
            ]
        }));
        assert!(engine.evaluate_visibility(&item, false));
    }

    #[test]
    fn visibility_with_behaviours_and_legacy_falls_back() {
        // When behaviours is present but doesn't have visibility triggers,
        // legacy onAppear should still work
        let nodes = vec![text_node(
            "n1",
            vec![serde_json::json!({
                "type": "text",
                "id": "t1",
                "behaviours": [
                    {"event": "onPress", "script": "scripts/btn.json"}
                ],
                "scriptTriggers": {"onAppear": "scripts/vis.json"}
            })],
        )];
        // Если behaviours есть и непусты, legacy НЕ используется (resolved_behaviours
        // возвращает behaviours). Но legacy onAppear всё равно должен работать
        // через evaluate_visibility (фильтр по event=onAppear).
        // В нашем случае behaviours содержит только onPress — значит item
        // видим всегда (нет onAppear ни в behaviours, ни в legacy fallback).
        let mut engine = simple_engine(nodes);
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "text", "id": "t1",
            "behaviours": [
                {"event": "onPress", "script": "scripts/btn.json"}
            ],
            "scriptTriggers": {"onAppear": "scripts/vis.json"}
        }));
        // behaviours present and non-empty → resolved_behaviours = behaviours
        // behaviours doesn't have onAppear → no visibility filter → always visible
        assert!(engine.evaluate_visibility(&item, false));
    }

    fn function_visibility_engine(expression: &str) -> GameEngine {
        let nodes = vec![text_node(
            "n1",
            vec![serde_json::json!({
                "type": "button",
                "id": "b1",
                "behaviours": [
                    {"event": "onAppear", "script": "scripts/can_show.json#fn=can_show",
                     "kind": "visibility"}
                ]
            })],
        )];
        GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/can_show.json".into(),
                    serde_json::json!({
                        "name": "can_show",
                        "blocks": [{
                            "type": "event",
                            "eventType": "function",
                            "functionName": "can_show",
                            "children": [
                                {"type": "condition", "expression": expression,
                                 "then_blocks": [], "else_blocks": []}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        )
    }

    fn visibility_behaviour_item() -> ContentItem {
        ContentItem::from_json(&serde_json::json!({
            "type": "button", "id": "b1",
            "behaviours": [
                {"event": "onAppear", "script": "scripts/can_show.json#fn=can_show",
                 "kind": "visibility"}
            ]
        }))
    }

    #[test]
    fn visibility_function_ref_hides_when_condition_false() {
        let mut engine = function_visibility_engine("1==0");
        engine.start_new(Some("n1")).unwrap();

        // Автор привязал к видимости функцию, а не onAppear-блок: движок
        // обязан вызвать её, иначе элемент появляется всегда («фантомная кнопка»).
        assert!(!engine.evaluate_visibility(&visibility_behaviour_item(), false));
    }

    #[test]
    fn visibility_function_ref_shows_when_condition_true() {
        let mut engine = function_visibility_engine("1==1");
        engine.start_new(Some("n1")).unwrap();

        assert!(engine.evaluate_visibility(&visibility_behaviour_item(), false));
    }

    /// Регрессия (7dba26d): legacy `scriptTriggers` с function-ссылкой
    /// (`#fn=`) в onAppear — тот же путь, что и у `kind: visibility`.
    /// До unified-behaviours старый Dart-движок резолвил её в EventType::Function.
    #[test]
    fn visibility_legacy_scripttrigger_function_ref_hides_when_false() {
        let nodes = vec![text_node(
            "n1",
            vec![serde_json::json!({
                "type": "button",
                "id": "b1",
                "scriptTriggers": {"onAppear": "scripts/can_show.json#fn=can_show"}
            })],
        )];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/can_show.json".into(),
                    serde_json::json!({
                        "name": "can_show",
                        "blocks": [{
                            "type": "event",
                            "eventType": "function",
                            "functionName": "can_show",
                            "children": [
                                {"type": "condition", "expression": "1==0",
                                 "then_blocks": [], "else_blocks": []}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "button", "id": "b1",
            "scriptTriggers": {"onAppear": "scripts/can_show.json#fn=can_show"}
        }));
        assert!(!engine.evaluate_visibility(&item, false));
    }

    // =========================================================================
    // Lua triggers
    // =========================================================================

    #[test]
    fn visibility_lua_trigger_is_always_true() {
        let item = ContentItem::from_json(&serde_json::json!({
            "type": "button",
            "id": "b1",
            "scriptTriggers": {"onAppear": "scripts/btn.lua"}
        }));

        let mut engine = simple_engine(vec![]);
        let _ = engine.start_new(Some("n1"));

        // Lua-триггеры всегда видны (нет condition-блоков)
        // Но без asset_store файл не резолвится — результат: true (продолжаем цикл)
        assert!(engine.evaluate_visibility(&item, false));
    }

    // =========================================================================
    // execute_behaviour: onPress
    // =========================================================================

    #[test]
    fn execute_onpress_with_json_script() {
        let nodes = vec![
            text_node(
                "n1",
                vec![serde_json::json!({
                    "type": "button",
                    "id": "b1",
                    "scriptTriggers": {"onPress": "scripts/btn.json"}
                })],
            ),
            text_node(
                "n2",
                vec![serde_json::json!({"type": "text", "id": "t2", "text": "Page 2"})],
            ),
        ];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/btn.json".into(),
                    serde_json::json!({
                        "name": "btn",
                        "blocks": [{
                            "type": "event",
                            "eventType": "onPress",
                            "children": [
                                {"type": "go_to_node", "node_id": "n2"}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "button", "id": "b1",
            "scriptTriggers": {"onPress": "scripts/btn.json"}
        }));
        let transition = engine.execute_behaviour(&item, "onPress");
        assert_eq!(transition.as_deref(), Some("n2"));
    }

    #[test]
    fn execute_onpress_with_behaviours() {
        let nodes = vec![
            text_node(
                "n1",
                vec![serde_json::json!({
                    "type": "button",
                    "id": "b1",
                    "behaviours": [
                        {"event": "onPress", "script": "scripts/btn.json"}
                    ]
                })],
            ),
            text_node(
                "n2",
                vec![serde_json::json!({"type": "text", "id": "t2", "text": "Page 2"})],
            ),
        ];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/btn.json".into(),
                    serde_json::json!({
                        "name": "btn",
                        "blocks": [{
                            "type": "event",
                            "eventType": "onPress",
                            "children": [
                                {"type": "go_to_node", "node_id": "n2"}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "button", "id": "b1",
            "behaviours": [
                {"event": "onPress", "script": "scripts/btn.json"}
            ]
        }));
        let transition = engine.execute_behaviour(&item, "onPress");
        assert_eq!(transition.as_deref(), Some("n2"));
    }

    // =========================================================================
    // execute_behaviour: onReveal
    // =========================================================================

    #[test]
    fn execute_onreveal_matches_onappear_behaviour() {
        let nodes = vec![
            text_node(
                "n1",
                vec![serde_json::json!({
                    "type": "button",
                    "id": "b1",
                    "scriptTriggers": {"onAppear": "scripts/reveal.json"}
                })],
            ),
            text_node(
                "n2",
                vec![serde_json::json!({"type": "text", "id": "t2", "text": "Page 2"})],
            ),
        ];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/reveal.json".into(),
                    serde_json::json!({
                        "name": "reveal",
                        "blocks": [{
                            "type": "event",
                            "eventType": "onContentAppear",
                            "children": [
                                {"type": "go_to_node", "node_id": "n2"}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "button", "id": "b1",
            "scriptTriggers": {"onAppear": "scripts/reveal.json"}
        }));
        // onReveal matches legacy onAppear with kind=action
        let transition = engine.execute_behaviour(&item, "onReveal");
        assert_eq!(transition.as_deref(), Some("n2"));
    }

    // =========================================================================
    // execute_behaviour: fallback chain
    // =========================================================================

    #[test]
    fn execute_onpress_falls_back_to_declared_event() {
        // Скрипт объявлен как onNodeEnter, но вызывается onPress.
        let nodes = vec![
            text_node(
                "n1",
                vec![serde_json::json!({
                    "type": "button",
                    "id": "b1",
                    "scriptTriggers": {"onPress": "scripts/multi.json"}
                })],
            ),
            text_node(
                "n2",
                vec![serde_json::json!({"type": "text", "id": "t2", "text": "Page 2"})],
            ),
        ];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/multi.json".into(),
                    serde_json::json!({
                        "name": "multi",
                        "blocks": [{
                            "type": "event",
                            "eventType": "onNodeEnter",
                            "children": [
                                {"type": "go_to_node", "node_id": "n2"}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "button", "id": "b1",
            "scriptTriggers": {"onPress": "scripts/multi.json"}
        }));
        let transition = engine.execute_behaviour(&item, "onPress");
        // onPress не находит блоков → fallback к onNodeEnter → находит
        assert_eq!(transition.as_deref(), Some("n2"));
    }

    #[test]
    fn execute_onpress_no_matching_blocks_returns_none() {
        let nodes = vec![text_node(
            "n1",
            vec![serde_json::json!({
                "type": "button",
                "id": "b1",
                "scriptTriggers": {"onPress": "scripts/empty.json"}
            })],
        )];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/empty.json".into(),
                    serde_json::json!({
                        "name": "empty",
                        "blocks": [{
                            "type": "event",
                            "eventType": "onContentAppear",
                            "children": [
                                {"type": "condition", "expression": "0==0", "then_blocks": [], "else_blocks": []}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "button", "id": "b1",
            "scriptTriggers": {"onPress": "scripts/empty.json"}
        }));
        // onPress → нет onPress-блоков. onContentAppear → только condition без go_to_node → None.
        let transition = engine.execute_behaviour(&item, "onPress");
        assert!(transition.is_none());
    }

    // =========================================================================
    // execute_behaviour: function-ref (#fn=)
    // =========================================================================

    #[test]
    fn execute_onpress_with_function_ref() {
        let nodes = vec![
            text_node(
                "n1",
                vec![serde_json::json!({
                    "type": "button",
                    "id": "b1",
                    "scriptTriggers": {"onPress": "scripts/fns.json#fn=go"}
                })],
            ),
            text_node(
                "n2",
                vec![serde_json::json!({"type": "text", "id": "t2", "text": "Page 2"})],
            ),
        ];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/fns.json".into(),
                    serde_json::json!({
                        "name": "fns",
                        "blocks": [{
                            "type": "event",
                            "eventType": "function",
                            "functionName": "go",
                            "children": [
                                {"type": "go_to_node", "node_id": "n2"}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "button", "id": "b1",
            "scriptTriggers": {"onPress": "scripts/fns.json#fn=go"}
        }));
        let transition = engine.execute_behaviour(&item, "onPress");
        assert_eq!(transition.as_deref(), Some("n2"));
    }

    // =========================================================================
    // handle_interaction backwards compat (legacy, unchanged by behaviours)
    // =========================================================================

    #[test]
    fn handle_interaction_still_works_with_legacy_trigger_ref() {
        let nodes = vec![
            text_node(
                "n1",
                vec![serde_json::json!({
                    "type": "button",
                    "id": "b1",
                    "scriptTriggers": {"onPress": "scripts/btn.json"}
                })],
            ),
            text_node(
                "n2",
                vec![serde_json::json!({"type": "text", "id": "t2", "text": "Page 2"})],
            ),
        ];
        let mut engine = GameEngine::new(
            "q1".to_string(),
            config("q1"),
            nodes,
            vec![],
            GameEngineConfig {
                embedded_scripts: HashMap::from([(
                    "scripts/btn.json".into(),
                    serde_json::json!({
                        "name": "btn",
                        "blocks": [{
                            "type": "event",
                            "eventType": "onPress",
                            "children": [
                                {"type": "go_to_node", "node_id": "n2"}
                            ]
                        }]
                    }),
                )]),
                ..Default::default()
            },
        );
        engine.start_new(Some("n1")).unwrap();

        let item = ContentItem::from_json(&serde_json::json!({
            "type": "button", "id": "b1",
            "scriptTriggers": {"onPress": "scripts/btn.json"}
        }));
        let transition = engine.handle_interaction(&item, "scripts/btn.json");
        assert_eq!(transition.as_deref(), Some("n2"));
    }
}
