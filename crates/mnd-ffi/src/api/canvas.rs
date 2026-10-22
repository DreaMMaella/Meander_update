pub fn canvas_build_connections(
    nodes_json: String,
    config_json: String,
    scripts_json: String,
) -> String {
    mnd_core::canvas::canvas_build_connections(&nodes_json, &config_json, &scripts_json)
}

pub fn canvas_visible_nodes(nodes_json: String, viewport_json: String) -> String {
    mnd_core::canvas::canvas_visible_nodes(&nodes_json, &viewport_json)
}

pub fn canvas_visible_subset(
    nodes_json: String,
    connections_json: String,
    viewport_json: String,
) -> String {
    mnd_core::canvas::canvas_visible_subset(&nodes_json, &connections_json, &viewport_json)
}

pub fn canvas_tidy_layout(nodes_json: String, connections_json: String) -> String {
    mnd_core::canvas::canvas_tidy_layout(&nodes_json, &connections_json)
}
