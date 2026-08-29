OPEN_P95_LIMIT_MS = 50.0
HIGHLIGHT_P95_LIMIT_MS = 33.334
MIN_RESOURCE_SAMPLES = 20
RSS_ABSOLUTE_GROWTH_ALLOWANCE_KB = 16 * 1024
RSS_RELATIVE_GROWTH_ALLOWANCE = 0.10
CPU_IDLE_ABSOLUTE_LIMIT = 5.0
CPU_IDLE_ACTIVE_RATIO = 0.25

OPEN_STAGE_COLUMNS = [
    "trigger_dispatch_ms",
    "main_preparation_ms",
    "session_directory_refresh_ms",
    "session_invalidation_ms",
    "session_state_reset_ms",
    "session_projection_ms",
    "session_recency_ms",
    "session_build_ms",
    "session_index_ms",
    "session_publish_ms",
    "session_load_wrapper_ms",
    "session_maintenance_request_ms",
    "session_controller_wrapper_ms",
    "screen_resolve_ms",
    "panel_size_ms",
    "panel_center_ms",
    "accessibility_sync_ms",
    "presentation_level_ms",
    "hide_non_panel_windows_ms",
    "initial_visibility_tracking_ms",
    "monitor_install_ms",
    "make_key_and_order_front_ms",
    "order_front_regardless_ms",
    "first_make_key_and_order_front_ms",
    "first_order_front_regardless_ms",
    "second_make_key_and_order_front_ms",
    "second_order_front_regardless_ms",
    "presentation_visibility_readback_ms",
    "auto_enter_schedule_ms",
    "presentation_wrapper_ms",
    "next_main_turn_ms",
    "layout_ms",
    "display_ms",
    "visibility_poll_wait_ms",
    "visibility_readback_ms",
    "visibility_wait_ms",
]

EVENT_STAGE_COLUMNS = [
    "command_return_ms",
    "first_content_draw_ms",
    "panel_expose_ms",
    "occlusion_visible_ms",
    "window_readiness_read_ms",
    "window_maintenance_wait_ms",
    "window_session_switch_ms",
    "window_content_draw_ms",
    "search_debounce_ms",
    "search_computation_ms",
    "search_results_publish_ms",
    "search_shell_draw_ms",
    "search_first_row_draw_ms",
]

OPEN_PREFLIGHT_STAGE_COLUMNS = [
    "trigger_dispatch_ms",
    "main_preparation_ms",
]

OPEN_DIAGNOSTIC_STAGE_COLUMNS = [
    "make_key_and_order_front_ms",
    "order_front_regardless_ms",
]

OPEN_PARTITION_STAGE_COLUMNS = [
    column
    for column in OPEN_STAGE_COLUMNS
    if column not in OPEN_PREFLIGHT_STAGE_COLUMNS
    and column not in OPEN_DIAGNOSTIC_STAGE_COLUMNS
]

OPEN_STAGE_GROUPS = {
    "session": [
        "session_directory_refresh_ms",
        "session_invalidation_ms",
        "session_state_reset_ms",
        "session_projection_ms",
        "session_recency_ms",
        "session_build_ms",
        "session_index_ms",
        "session_publish_ms",
        "session_load_wrapper_ms",
        "session_maintenance_request_ms",
        "session_controller_wrapper_ms",
    ],
    "geometry_accessibility": [
        "screen_resolve_ms",
        "panel_size_ms",
        "panel_center_ms",
        "accessibility_sync_ms",
    ],
    "window_presentation": [
        "presentation_level_ms",
        "hide_non_panel_windows_ms",
        "first_make_key_and_order_front_ms",
        "first_order_front_regardless_ms",
        "second_make_key_and_order_front_ms",
        "second_order_front_regardless_ms",
    ],
    "observers_scheduling": [
        "initial_visibility_tracking_ms",
        "monitor_install_ms",
        "presentation_visibility_readback_ms",
        "auto_enter_schedule_ms",
    ],
    "post_presentation_visibility": [
        "presentation_wrapper_ms",
        "next_main_turn_ms",
        "layout_ms",
        "display_ms",
        "visibility_poll_wait_ms",
        "visibility_readback_ms",
        "visibility_wait_ms",
    ],
}

SCENARIOS = {
    "realistic": {
        "app_count": 24,
        "opened_windows": 5,
        "highlighted_windows": 5,
    },
    "extreme": {
        "app_count": 120,
        "opened_windows": 100,
        "highlighted_windows": 5,
    },
    "local": {
        "app_count": None,
        "opened_windows": None,
        "highlighted_windows": None,
    },
}

FLOWS = {
    "application": {
        "interaction_gate": "highlight_p95_ms",
        "interaction_limit_ms": HIGHLIGHT_P95_LIMIT_MS,
    },
    "app-to-window": {
        "interaction_gate": "window_entry_p95_ms",
        "interaction_limit_ms": 35.0,
    },
    "search": {
        "interaction_gate": None,
        "interaction_limit_ms": None,
    },
}
