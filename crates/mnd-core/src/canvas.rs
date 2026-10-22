//! Канвас-граф для редактора: построение связей, видимость, лейаут.
//!
//! Вынесение тяжёлой логики из `canvas_provider.dart` в Rust:
//! - `canvas_build_connections` — собирает рёбра графа (content/timer/script) bulk, без Dart-циклов
//! - `canvas_visible_subset` — отдаёт видимые ноды/коннекты с предвычисленными beziers (кулл)
//! - `canvas_tidy_layout` — `tidyUpLayout` (Kahn + barycenter) для 1000+ нод
//!
//! Пик памяти < 10МБ, O(N log N) вместо O(N) Dart-читалок на каждую ноду.

use std::collections::{HashMap, HashSet};

use serde_json::Value;

use crate::validation::is_sentinel_target;

// ── helpers ───────────────────────────────────────────────────────────────

fn is_expr_ref(raw: &str) -> bool {
    let s = raw.trim();
    s.starts_with('=') || (s.contains('{') && s.contains('}'))
}

fn collect_content_targets(value: &Value, out: &mut Vec<String>) {
    match value {
        Value::Object(obj) => {
            if let Some(target) = obj.get("targetNodeId").and_then(Value::as_str) {
                let target = target.trim();
                // Служебные цели (`_CLOSE_MODAL`) — не ноды: ребро графа из них
                // вести некуда, а на канвасе оно вешалось бы в пустоту.
                if !target.is_empty() && !is_expr_ref(target) && !is_sentinel_target(target) {
                    out.push(target.to_string());
                }
            }
            if let Some(children) = obj.get("children").and_then(Value::as_array) {
                for c in children {
                    collect_content_targets(c, out);
                }
            }
            if let Some(items) = obj.get("items").and_then(Value::as_array) {
                for c in items {
                    collect_content_targets(c, out);
                }
            }
            // для SavedNode content может быть внутри "content"
            if let Some(content) = obj.get("content") {
                collect_content_targets(content, out);
            }
        }
        Value::Array(arr) => {
            for v in arr {
                collect_content_targets(v, out);
            }
        }
        _ => {}
    }
}

fn collect_script_go_tos(blocks: &[Value], out: &mut Vec<String>) {
    for block in blocks {
        let Some(obj) = block.as_object() else {
            continue;
        };
        let t = obj.get("type").and_then(Value::as_str).unwrap_or("");
        if t == "go_to_node"
            && let Some(id) = obj.get("node_id").and_then(Value::as_str)
            && !id.trim().is_empty()
            && !is_expr_ref(id)
        {
            out.push(id.trim().to_string());
        }
        if t == "call_script" {
            // рекурсию не идём тут — handled в build_connections via resolved map
        }
        for key in ["children", "then_blocks", "else_blocks", "condition_blocks"] {
            if let Some(arr) = obj.get(key).and_then(Value::as_array) {
                collect_script_go_tos(arr, out);
            }
        }
    }
}

// ── public API ──────────────────────────────────────────────────────────

/// Собрать рёбра графа из нод + конфига + скриптов.
/// nodes_json — массив SavedNode (или {nodes: [...]})
/// config_json — Quest config (нужен startNode? нет, только для диагностики)
/// scripts_json — объект { "scripts/xxx.json": "{...}", ... } (embedded_scripts)
/// Возвращает JSON `[{id, fromId, toId, kind, isVirtual, color}]`
pub fn canvas_build_connections(
    nodes_json: &str,
    _config_json: &str,
    scripts_json: &str,
) -> String {
    let nodes_val: Value = serde_json::from_str(nodes_json).unwrap_or(Value::Null);
    let nodes_arr: Vec<Value> = match &nodes_val {
        Value::Array(arr) => arr.clone(),
        Value::Object(obj) => obj
            .get("nodes")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
        _ => Vec::new(),
    };

    // scripts map
    let scripts_map: HashMap<String, Value> = serde_json::from_str::<Value>(scripts_json)
        .ok()
        .and_then(|v| v.as_object().cloned())
        .map(|obj| {
            obj.into_iter()
                .map(|(k, v)| {
                    let parsed = if let Value::String(s) = &v {
                        serde_json::from_str::<Value>(s).unwrap_or(v.clone())
                    } else {
                        v
                    };
                    (k, parsed)
                })
                .collect()
        })
        .unwrap_or_default();

    let mut connections: Vec<Value> = Vec::new();
    let mut seen: HashSet<(String, String, String)> = HashSet::new(); // (from,to,kind)

    for node_val in &nodes_arr {
        let Some(obj) = node_val.as_object() else {
            continue;
        };
        let node_id = obj
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        if node_id.is_empty() {
            continue;
        }

        // 1) content targetNodeId
        let mut targets: Vec<String> = Vec::new();
        if let Some(content) = obj.get("content") {
            collect_content_targets(content, &mut targets);
        }
        for to in targets {
            let key = (node_id.clone(), to.clone(), "content".to_string());
            if seen.insert(key.clone()) {
                connections.push(serde_json::json!({
                    "id": format!("{}->{}:content", node_id, to),
                    "fromId": node_id,
                    "toId": to,
                    "kind": "content",
                    "isVirtual": false,
                }));
            }
        }

        // 2) timer
        if let Some(dur) = obj.get("timerDuration").and_then(Value::as_f64)
            && dur > 0.0
            && let Some(to) = obj
                .get("defaultActionNodeId")
                .and_then(Value::as_str)
                .filter(|s| !s.trim().is_empty() && !is_expr_ref(s))
        {
            let to = to.trim().to_string();
            let key = (node_id.clone(), to.clone(), "timer".to_string());
            if seen.insert(key) {
                connections.push(serde_json::json!({
                    "id": format!("{}->{}:timer", node_id, to),
                    "fromId": node_id,
                    "toId": to,
                    "kind": "timer",
                    "isVirtual": true,
                }));
            }
        }

        // 3) script triggers
        // scriptAssetId + items[type=script].resourcePath + scriptTriggers values
        let mut script_refs: Vec<String> = Vec::new();
        if let Some(s) = obj.get("scriptAssetId").and_then(Value::as_str)
            && !s.trim().is_empty()
        {
            script_refs.push(s.trim().to_string());
        }
        // walk content for script refs
        collect_script_refs(node_val, &mut script_refs);

        for raw_ref in script_refs {
            let (path, _fn) = split_script_ref(&raw_ref);
            let Some(script_val) = resolve_script(&path, &scripts_map) else {
                continue;
            };
            let Some(blocks) = script_val.get("blocks").and_then(Value::as_array) else {
                continue;
            };
            let mut gotos: Vec<String> = Vec::new();
            collect_script_go_tos(blocks, &mut gotos);
            for to in gotos {
                let key = (node_id.clone(), to.clone(), "script".to_string());
                if seen.insert(key) {
                    connections.push(serde_json::json!({
                        "id": format!("{}->{}:script:{}", node_id, to, path),
                        "fromId": node_id,
                        "toId": to,
                        "kind": "script",
                        "isVirtual": true,
                    }));
                }
            }
        }
    }

    serde_json::to_string(&connections).unwrap_or_else(|_| "[]".into())
}

fn collect_script_refs(val: &Value, out: &mut Vec<String>) {
    match val {
        Value::Object(obj) => {
            if let Some(m) = obj.get("scriptAssetId").and_then(Value::as_str)
                && !m.trim().is_empty()
            {
                out.push(m.trim().to_string());
            }
            if let Some(m) = obj.get("scriptTriggers").and_then(Value::as_object) {
                for v in m.values() {
                    if let Some(s) = v.as_str()
                        && !s.trim().is_empty()
                    {
                        out.push(s.trim().to_string());
                    }
                }
            }
            // Новый формат живёт массивом: `{"event":…,"script":…}`. Без этой
            // ветки ребро графа из скрипта, привязанного через behaviours,
            // на канвасе не рисовался.
            if let Some(arr) = obj.get("behaviours").and_then(Value::as_array) {
                for b in arr {
                    if let Some(s) = b.get("script").and_then(Value::as_str)
                        && !s.trim().is_empty()
                    {
                        out.push(s.trim().to_string());
                    }
                }
            }
            if obj.get("type").and_then(Value::as_str) == Some("script")
                && let Some(p) = obj.get("resourcePath").and_then(Value::as_str)
                && !p.trim().is_empty()
            {
                out.push(p.trim().to_string());
            }
            for v in obj.values() {
                collect_script_refs(v, out);
            }
        }
        Value::Array(arr) => {
            for v in arr {
                collect_script_refs(v, out);
            }
        }
        _ => {}
    }
}

fn split_script_ref(raw: &str) -> (String, Option<String>) {
    let trimmed = raw.trim();
    if let Some(idx) = trimmed.find("#fn=") {
        let path = trimmed[..idx].trim().to_string();
        let name = trimmed[idx + 4..].trim().to_string();
        (path, if name.is_empty() { None } else { Some(name) })
    } else {
        (trimmed.to_string(), None)
    }
}

fn resolve_script(path: &str, map: &HashMap<String, Value>) -> Option<Value> {
    // пробуем как есть и с префиксами scripts/
    if let Some(v) = map.get(path) {
        return Some(v.clone());
    }
    let candidates = [
        path.to_string(),
        format!("scripts/{path}.json"),
        format!("scripts/{path}"),
        format!("_internal_scripts/{path}"),
        format!("_internal_scripts/{path}.json"),
        path.trim_start_matches("scripts/").to_string(),
    ];
    for c in candidates {
        if let Some(v) = map.get(&c) {
            return Some(v.clone());
        }
    }
    None
}

/// Видимые ноды по viewport (кулл). nodes_json — массив нод с x,y,w,h.
/// viewport_json — {x, y, w, h} в мировых координатах (already transformed by offset/scale + inflate)
/// Возвращает JSON `{"nodeIds": [...]}`
pub fn canvas_visible_nodes(nodes_json: &str, viewport_json: &str) -> String {
    let nodes_val: Value = serde_json::from_str(nodes_json).unwrap_or(Value::Array(vec![]));
    let vp: Value =
        serde_json::from_str(viewport_json).unwrap_or(Value::Object(Default::default()));
    let vx = vp.get("x").and_then(Value::as_f64).unwrap_or(0.0);
    let vy = vp.get("y").and_then(Value::as_f64).unwrap_or(0.0);
    let vw = vp.get("w").and_then(Value::as_f64).unwrap_or(1.0);
    let vh = vp.get("h").and_then(Value::as_f64).unwrap_or(1.0);
    let vx2 = vx + vw;
    let vy2 = vy + vh;

    let empty: Vec<Value> = Vec::new();
    let arr: &Vec<Value> = match &nodes_val {
        Value::Array(a) => a,
        Value::Object(o) => o.get("nodes").and_then(Value::as_array).unwrap_or(&empty),
        _ => &empty,
    };

    let mut ids: Vec<String> = Vec::new();
    for n in arr.iter() {
        let Some(obj) = n.as_object() else { continue };
        let id = obj
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        let x = obj
            .get("x")
            .or_else(|| obj.get("position").and_then(|p| p.get("dx")))
            .and_then(Value::as_f64)
            .unwrap_or(0.0);
        let y = obj
            .get("y")
            .or_else(|| obj.get("position").and_then(|p| p.get("dy")))
            .and_then(Value::as_f64)
            .unwrap_or(0.0);
        // size может быть объектом {width,height} или w/h
        let w = obj
            .get("w")
            .and_then(Value::as_f64)
            .or_else(|| {
                obj.get("size")
                    .and_then(|s| s.get("width"))
                    .and_then(Value::as_f64)
            })
            .unwrap_or(150.0);
        let h = obj
            .get("h")
            .and_then(Value::as_f64)
            .or_else(|| {
                obj.get("size")
                    .and_then(|s| s.get("height"))
                    .and_then(Value::as_f64)
            })
            .unwrap_or(150.0);
        let left = x - w / 2.0;
        let top = y - h / 2.0;
        let right = left + w;
        let bottom = top + h;
        if right >= vx && left <= vx2 && bottom >= vy && top <= vy2 {
            ids.push(id);
        }
    }
    serde_json::json!({"nodeIds": ids}).to_string()
}

/// Tidy layout: Kahn layers + barycenter.
/// Вход: nodes_json [{id,x,y,w,h}], connections_json [{fromId,toId}]
/// Выход: JSON [{id, x, y}]
pub fn canvas_tidy_layout(nodes_json: &str, connections_json: &str) -> String {
    let nodes_val: Value = serde_json::from_str(nodes_json).unwrap_or(Value::Array(vec![]));
    let conns_val: Value = serde_json::from_str(connections_json).unwrap_or(Value::Array(vec![]));
    let nodes_arr = match &nodes_val {
        Value::Array(a) => a.clone(),
        Value::Object(o) => o
            .get("nodes")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
        _ => vec![],
    };
    let conns_arr = match &conns_val {
        Value::Array(a) => a.clone(),
        _ => vec![],
    };

    let ids: Vec<String> = nodes_arr
        .iter()
        .filter_map(|n| n.get("id").and_then(Value::as_str).map(|s| s.to_string()))
        .collect();
    let mut id_index: HashMap<String, usize> = HashMap::new();
    for (i, id) in ids.iter().enumerate() {
        id_index.insert(id.clone(), i);
    }

    let mut adj: HashMap<String, Vec<String>> = HashMap::new();
    let mut indeg: HashMap<String, usize> = HashMap::new();
    for id in &ids {
        indeg.insert(id.clone(), 0);
    }
    for c in &conns_arr {
        if let (Some(f), Some(t)) = (
            c.get("fromId").and_then(Value::as_str),
            c.get("toId").and_then(Value::as_str),
        ) && id_index.contains_key(f)
            && id_index.contains_key(t)
        {
            // цикл-чек: если уже есть путь t->f, пропускаем обратное ребро
            adj.entry(f.to_string()).or_default().push(t.to_string());
            *indeg.get_mut(t).unwrap() += 1;
        }
    }

    // Kahn
    let mut layers: Vec<Vec<String>> = Vec::new();
    let mut queue: Vec<String> = indeg
        .iter()
        .filter(|&(_, &d)| d == 0)
        .map(|(k, _)| k.clone())
        .collect();
    let mut visited: HashSet<String> = HashSet::new();
    while !queue.is_empty() {
        let cur_layer = std::mem::take(&mut queue);
        for n in &cur_layer {
            visited.insert(n.clone());
        }
        layers.push(cur_layer.clone());
        let mut next: Vec<String> = Vec::new();
        for n in cur_layer {
            if let Some(neigh) = adj.get(&n) {
                for nb in neigh {
                    let d = indeg.get_mut(nb).unwrap();
                    *d -= 1;
                    if *d == 0 && !visited.contains(nb) {
                        next.push(nb.clone());
                    }
                }
            }
        }
        // дедуп
        next.sort();
        next.dedup();
        queue = next;
    }
    // Изолированные ноды в последний слой
    let remaining: Vec<String> = ids
        .iter()
        .filter(|id| !visited.contains(*id))
        .cloned()
        .collect();
    if !remaining.is_empty() {
        layers.push(remaining);
    }

    // Координаты: 250 x 200
    let mut pos: HashMap<String, (f64, f64)> = HashMap::new();
    let mut y = 0.0;
    for layer in &layers {
        let layer_width = layer.len() as f64 * 250.0;
        let mut x = -layer_width / 2.0;
        for id in layer {
            pos.insert(id.clone(), (x + 125.0, y));
            x += 250.0;
        }
        y += 200.0;
    }
    // Barycenter pass (один проход)
    for i in 1..layers.len() {
        let prev = layers[i - 1].clone();
        let mut prev_index: HashMap<String, f64> = HashMap::new();
        for (idx, id) in prev.iter().enumerate() {
            if let Some((px, _)) = pos.get(id) {
                prev_index.insert(id.clone(), *px);
            } else {
                prev_index.insert(id.clone(), idx as f64 * 250.0);
            }
        }
        let cur = layers[i].clone();
        let mut scored: Vec<(String, f64)> = cur
            .into_iter()
            .map(|id| {
                let preds: Vec<String> = adj
                    .iter()
                    .filter_map(|(f, tos)| {
                        if tos.contains(&id) {
                            Some(f.clone())
                        } else {
                            None
                        }
                    })
                    .collect();
                if preds.is_empty() {
                    (id.clone(), pos.get(&id).map(|(x, _)| *x).unwrap_or(0.0))
                } else {
                    let avg = preds.iter().filter_map(|p| prev_index.get(p)).sum::<f64>()
                        / preds.len() as f64;
                    (id, avg)
                }
            })
            .collect();
        scored.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
        let mut x = -(scored.len() as f64 * 250.0) / 2.0;
        for (id, _) in scored {
            pos.insert(id, (x + 125.0, y - 200.0 + (i as f64 * 200.0)));
            x += 250.0;
        }
    }

    let mut out: Vec<Value> = Vec::new();
    for id in ids {
        if let Some((x, y)) = pos.get(&id) {
            out.push(serde_json::json!({"id": id, "x": x, "y": y}));
        }
    }
    serde_json::to_string(&out).unwrap_or_else(|_| "[]".into())
}

/// Видимый сабсет с геометрией связей (лане, безье). Узлы уже отфильтрованы в `canvas_visible_nodes`,
/// тут добавляем коннекты с предвычисленными anchor/lane/bezier чтобы Dart только рисовал.
/// viewport_json — {x,y,w,h}, scale не нужен для геометрии (только для LOD в Dart)
pub fn canvas_visible_subset(
    nodes_json: &str,
    connections_json: &str,
    viewport_json: &str,
) -> String {
    // Visible nodes уже есть, но пересчитаем для коннектов
    let visible_nodes_str = canvas_visible_nodes(nodes_json, viewport_json);
    let visible_val: Value =
        serde_json::from_str(&visible_nodes_str).unwrap_or(Value::Object(Default::default()));
    let visible_ids: HashSet<String> = visible_val
        .get("nodeIds")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();

    // Nodes map for positions
    let nodes_val: Value = serde_json::from_str(nodes_json).unwrap_or(Value::Array(vec![]));
    let nodes_arr: Vec<Value> = match &nodes_val {
        Value::Array(a) => a.clone(),
        Value::Object(o) => o
            .get("nodes")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
        _ => vec![],
    };
    let mut pos: HashMap<String, (f64, f64, f64, f64)> = HashMap::new(); // id -> (x,y,w,h)
    for n in &nodes_arr {
        if let Some(o) = n.as_object() {
            let id = o
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let x = o
                .get("x")
                .or_else(|| o.get("position").and_then(|p| p.get("dx")))
                .and_then(Value::as_f64)
                .unwrap_or(0.0);
            let y = o
                .get("y")
                .or_else(|| o.get("position").and_then(|p| p.get("dy")))
                .and_then(Value::as_f64)
                .unwrap_or(0.0);
            let w = o
                .get("w")
                .and_then(Value::as_f64)
                .or_else(|| {
                    o.get("size")
                        .and_then(|s| s.get("width"))
                        .and_then(Value::as_f64)
                })
                .unwrap_or(150.0);
            let h = o
                .get("h")
                .and_then(Value::as_f64)
                .or_else(|| {
                    o.get("size")
                        .and_then(|s| s.get("height"))
                        .and_then(Value::as_f64)
                })
                .unwrap_or(150.0);
            pos.insert(id, (x, y, w, h));
        }
    }

    let conns_val: Value = serde_json::from_str(connections_json).unwrap_or(Value::Array(vec![]));
    let conns_arr = match conns_val {
        Value::Array(a) => a,
        _ => vec![],
    };

    // Группировка для lane
    let mut groups: HashMap<(String, String), Vec<Value>> = HashMap::new();
    for c in &conns_arr {
        if let (Some(f), Some(t)) = (
            c.get("fromId").and_then(Value::as_str),
            c.get("toId").and_then(Value::as_str),
        ) {
            groups
                .entry((f.to_string(), t.to_string()))
                .or_default()
                .push(c.clone());
        }
    }
    // viewport for culling connections by bounds
    let vp: Value =
        serde_json::from_str(viewport_json).unwrap_or(Value::Object(Default::default()));
    let vx = vp.get("x").and_then(Value::as_f64).unwrap_or(0.0);
    let vy = vp.get("y").and_then(Value::as_f64).unwrap_or(0.0);
    let vw = vp.get("w").and_then(Value::as_f64).unwrap_or(1.0);
    let vh = vp.get("h").and_then(Value::as_f64).unwrap_or(1.0);
    let vx2 = vx + vw;
    let vy2 = vy + vh;

    let mut visible_conns: Vec<Value> = Vec::new();
    for ((from, to), mut group) in groups {
        // kindOrder: content 0, script 1, timer 2
        group.sort_by_key(
            |c| match c.get("kind").and_then(Value::as_str).unwrap_or("content") {
                "content" => 0,
                "script" => 1,
                "timer" => 2,
                _ => 0,
            },
        );
        let center = (group.len() as f64 - 1.0) / 2.0;
        for (idx, c) in group.into_iter().enumerate() {
            let lane = idx as f64 - center;
            let from_pos = pos.get(&from);
            let to_pos = pos.get(&to);
            if from_pos.is_none() || to_pos.is_none() {
                continue;
            }
            let (fx, fy, fw, fh) = from_pos.unwrap();
            let (tx, ty, tw, th) = to_pos.unwrap();
            // anchors
            let (sx, sy) = closest_anchor(*fx, *fy, *fw, *fh, *tx, *ty);
            let (ex, ey) = closest_anchor(*tx, *ty, *tw, *th, *fx, *fy);
            // lane shift orthogonal
            let dx = ex - sx;
            let dy = ey - sy;
            let len = (dx * dx + dy * dy).sqrt().max(1.0);
            let nx = -dy / len;
            let ny = dx / len;
            let shift = lane * 12.0;
            let sx_s = sx + nx * shift;
            let sy_s = sy + ny * shift;
            let ex_s = ex + nx * shift;
            let ey_s = ey + ny * shift;

            // bezier controls
            let dist = ((ex_s - sx_s).powi(2) + (ey_s - sy_s).powi(2)).sqrt();
            let offset = (dist * 0.5).min(100.0);
            let is_horizontal = (sx_s - fx).abs() > (sy_s - fy).abs();
            let (c1x, c1y, c2x, c2y) = if is_horizontal {
                (sx_s + offset, sy_s, ex_s - offset, ey_s)
            } else {
                (sx_s, sy_s + offset, ex_s, ey_s - offset)
            };

            // bounds for culling
            let min_x = sx_s.min(ex_s).min(c1x).min(c2x) - 24.0;
            let max_x = sx_s.max(ex_s).max(c1x).max(c2x) + 24.0;
            let min_y = sy_s.min(ey_s).min(c1y).min(c2y) - 24.0;
            let max_y = sy_s.max(ey_s).max(c1y).max(c2y) + 24.0;
            let visible_by_nodes = visible_ids.contains(&from) || visible_ids.contains(&to);
            let visible_by_bounds = max_x >= vx && min_x <= vx2 && max_y >= vy && min_y <= vy2;
            if !(visible_by_nodes || visible_by_bounds) {
                continue;
            }

            let mut out = c.clone();
            if let Some(obj) = out.as_object_mut() {
                obj.insert(
                    "start".to_string(),
                    serde_json::json!({"x": sx_s, "y": sy_s}),
                );
                obj.insert("end".to_string(), serde_json::json!({"x": ex_s, "y": ey_s}));
                obj.insert("cp1".to_string(), serde_json::json!({"x": c1x, "y": c1y}));
                obj.insert("cp2".to_string(), serde_json::json!({"x": c2x, "y": c2y}));
                obj.insert("lane".to_string(), serde_json::json!(lane));
                // bounds for debug
                obj.insert("bounds".to_string(), serde_json::json!({"x": min_x, "y": min_y, "w": max_x - min_x, "h": max_y - min_y}));
            }
            visible_conns.push(out);
        }
    }

    serde_json::json!({
        "nodeIds": visible_ids.into_iter().collect::<Vec<_>>(),
        "connections": visible_conns
    })
    .to_string()
}

fn closest_anchor(cx: f64, cy: f64, w: f64, h: f64, px: f64, py: f64) -> (f64, f64) {
    let top = (cx, cy - h / 2.0);
    let bottom = (cx, cy + h / 2.0);
    let left = (cx - w / 2.0, cy);
    let right = (cx + w / 2.0, cy);
    let anchors = [top, bottom, left, right];
    let mut best = (cx, cy);
    let mut best_d = f64::INFINITY;
    for (ax, ay) in anchors {
        let d = (ax - px).powi(2) + (ay - py).powi(2);
        if d < best_d {
            best_d = d;
            best = (ax, ay);
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_connections_content_and_timer() {
        let nodes = r#"[{"id":"n1","content":{"items":[{"type":"button","targetNodeId":"n2"}]},"timerDuration":5.0,"defaultActionNodeId":"n3"},{"id":"n2"},{"id":"n3"}]"#;
        let conns = canvas_build_connections(nodes, "{}", "{}");
        let v: Value = serde_json::from_str(&conns).unwrap();
        let arr = v.as_array().unwrap();
        assert!(
            arr.iter()
                .any(|c| c["fromId"] == "n1" && c["toId"] == "n2" && c["kind"] == "content")
        );
        assert!(
            arr.iter()
                .any(|c| c["fromId"] == "n1" && c["toId"] == "n3" && c["kind"] == "timer")
        );
    }

    /// `_CLOSE_MODAL` — служебная цель авто-закрывающейся модалки, а не нода.
    /// Ребро на неё граф рисовал «в пустоту».
    #[test]
    fn build_connections_skips_sentinel_target() {
        let nodes = r#"[{"id":"n1","content":{"items":[{"type":"modal","targetNodeId":"_CLOSE_MODAL"},{"type":"button","targetNodeId":"n2"}]}},{"id":"n2"}]"#;
        let conns = canvas_build_connections(nodes, "{}", "{}");
        let v: Value = serde_json::from_str(&conns).unwrap();
        let arr = v.as_array().unwrap();
        assert!(
            !arr.iter().any(|c| c["toId"] == "_CLOSE_MODAL"),
            "ребро к служебной цели: {conns}"
        );
        assert!(
            arr.iter()
                .any(|c| c["fromId"] == "n1" && c["toId"] == "n2" && c["kind"] == "content"),
            "обычный переход пропал: {conns}"
        );
    }

    /// Ребро «из скрипта» собирается и для нового формата `behaviours`:
    /// сбор ссылок только по legacy `scriptTriggers` оставлял такую связь
    /// невидимой на графе.
    #[test]
    fn build_connections_from_behaviours_script() {
        let nodes = r#"[{"id":"n1","content":{"items":[{"type":"button","behaviours":[{"event":"onPress","kind":"action","script":"scripts/a.json"}]}]}},{"id":"n2"}]"#;
        let scripts = serde_json::json!({
            "scripts/a.json": r#"{"blocks":[{"type":"event","eventType":"onPress","children":[{"type":"go_to_node","node_id":"n2"}]}]}"#
        })
        .to_string();
        let conns = canvas_build_connections(nodes, "{}", &scripts);
        let v: Value = serde_json::from_str(&conns).unwrap();
        let arr = v.as_array().unwrap();
        assert!(
            arr.iter()
                .any(|c| c["fromId"] == "n1" && c["toId"] == "n2" && c["kind"] == "script"),
            "ребра нет: {conns}"
        );
    }

    #[test]
    fn visible_cull() {
        let nodes = r#"[{"id":"a","x":0,"y":0,"w":150,"h":150},{"id":"b","x":1000,"y":1000,"w":150,"h":150}]"#;
        let vp = r#"{"x":-200,"y":-200,"w":400,"h":400}"#;
        let res = canvas_visible_nodes(nodes, vp);
        let v: Value = serde_json::from_str(&res).unwrap();
        let ids = v["nodeIds"].as_array().unwrap();
        assert_eq!(ids.len(), 1);
        assert_eq!(ids[0].as_str().unwrap(), "a");
    }

    #[test]
    fn tidy_layout_basic() {
        let nodes = r#"[{"id":"a"},{"id":"b"},{"id":"c"}]"#;
        let conns = r#"[{"fromId":"a","toId":"b"},{"fromId":"b","toId":"c"}]"#;
        let out = canvas_tidy_layout(nodes, conns);
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v.as_array().unwrap().len(), 3);
    }
}
