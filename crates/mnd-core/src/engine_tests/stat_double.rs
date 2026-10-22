use super::super::*;
use crate::engine::{GameEngine, GameEngineConfig, PlatformInfo};
use crate::models::{ContentItem, Quest, SavedNode};
use std::collections::HashMap;

#[test]
fn stat_plus_adds_one_not_two() {
    let script_sila = serde_json::json!({
        "id": "60a149a4-c959-40f5-a2b8-7f73d94fd64b",
        "name": "Сила+",
        "blocks": [{
            "type": "event",
            "id": "294678fc-03bf-4c25-9d50-2f5e6010cb2c",
            "eventType": "onNodeEnter",
            "children": [{
                "type": "condition",
                "id": "49f9b030-8d1d-4ea2-8c14-a5c9711f6566",
                "expression": "{SkP}>0",
                "then_blocks": [
                    {"type": "assign_variable", "id": "76f31809-4834-44db-bddc-8ac616b64973", "variable": "ST", "value": "{ST}+1"},
                    {"type": "assign_variable", "id": "68641f86-0f2b-4fe8-b7ab-d55f2f20e572", "variable": "SkP", "value": "{SkP}-1"},
                    {"type": "assign_variable", "id": "769cac55-c9a8-4a1f-939c-1910be72f61a", "variable": "ST+", "value": "{ST+}+1"},
                    {"type": "call_script", "id": "81059866-f35e-4c9d-bf06-5730b1479743", "script_id": "491fe0fd-0f9a-468a-9229-95b99e4c101c", "script_name": "Звук кнопка"}
                ],
                "else_blocks": [],
                "collapsed": false
            }],
            "collapsed": false
        }]
    });
    let script_zvuk = serde_json::json!({
        "id": "491fe0fd-0f9a-468a-9229-95b99e4c101c",
        "name": "Звук кнопка",
        "blocks": [{
            "type": "event",
            "id": "e1",
            "eventType": "onNodeEnter",
            "children": [
                {"type": "play_sound", "id": "ps", "audio_id": "click.mp3", "volume": "1.0", "children": []}
            ],
            "collapsed": false
        }]
    });
    let mut scripts = HashMap::new();
    scripts.insert(
        "scripts/60a149a4-c959-40f5-a2b8-7f73d94fd64b.json".to_string(),
        script_sila,
    );
    scripts.insert(
        "scripts/491fe0fd-0f9a-468a-9229-95b99e4c101c.json".to_string(),
        script_zvuk,
    );

    let quest = Quest::from_json(&serde_json::json!({
        "id": "q1", "title": "Q", "version": "1.0", "startNodeId": "n1"
    }));
    let node = SavedNode::from_json(&serde_json::json!({
        "id": "n1", "title": "1_7 Статы", "chapterId": "ch1",
        "content": { "items": [
            {"id": "8ee9b672-7cde-4897-8021-0d22405bc08f", "type": "button", "text": "+", "scriptTriggers": {"onPress": "scripts/60a149a4-c959-40f5-a2b8-7f73d94fd64b.json"}}
        ]}
    }));
    let mut engine = GameEngine::new(
        quest.id.clone(),
        quest,
        vec![node],
        vec![],
        GameEngineConfig {
            platform: PlatformInfo::default(),
            embedded_scripts: scripts,
            asset_store: None,
            save_store: None,
        },
    );
    let _view = engine.start_new(None).unwrap();
    engine.state.set_variable("ST", serde_json::json!(3));
    engine.state.set_variable("SkP", serde_json::json!(5));
    engine.state.set_variable("ST+", serde_json::json!(0));

    let item = ContentItem::from_json(&serde_json::json!({
        "id": "8ee9b672-7cde-4897-8021-0d22405bc08f", "type": "button", "text": "+", "scriptTriggers": {"onPress": "scripts/60a149a4-c959-40f5-a2b8-7f73d94fd64b.json"}
    }));
    let _ = engine.handle_interaction(&item, "scripts/60a149a4-c959-40f5-a2b8-7f73d94fd64b.json");
    let st = engine.state.get_variable("ST").unwrap().clone();
    let skp = engine.state.get_variable("SkP").unwrap().clone();
    let stp = engine.state.get_variable("ST+").unwrap().clone();
    assert_eq!(
        st,
        serde_json::json!(4),
        "ST should increment by 1, got {:?}",
        st
    );
    assert_eq!(
        skp,
        serde_json::json!(4),
        "SkP should decrement by 1, got {:?}",
        skp
    );
    assert_eq!(
        stp,
        serde_json::json!(1),
        "ST+ should increment by 1, got {:?}",
        stp
    );
}
