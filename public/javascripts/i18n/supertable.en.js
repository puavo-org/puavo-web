I18n.translations || (I18n.translations = {});

I18n.translations["en"] = I18n.extend((I18n.translations["en"] || {}),
{
    supertable: {
        empty: "(No entries to display)",

        control: {
            select_columns: "Select columns...",
            select_columns_title: "Select which columns are visible and in which order",
            download_csv: "Download as CSV...",
            download_csv_title: "Download the visible table contents as a CSV file",
            reload: "Reload",
            reload_title: "Reload the table contents without reloading the whole page",
            fetching: "Updating...",
            failed: "Failed!",
            network_error: "Network error?",
            server_error: "Server returned error ",
            timeout: "Timeout, try again later",
            json_fail: "JSON parse error, see console",
            status: "${total} ${itemName} total, ${filtered} filtered, ${visible} visible",
            select_placeholder: "(Select)",

            filtering_main_enabled: "Enable filtering",
            filtering_main_enabled_title: "Only show rows that match the specified criteria",
            filtering_main_reverse: "Reverse matching",
            filtering_main_reverse_title: "Only show rows that DON'T match the specified criteria",
            filtering_presets: "Presets:",
            filtering_presets_title: "Use a pre-built filter",
            filtering_reset: "(Clear)",

            filter: {
                placeholder_string: "Regexp string",
                placeholder_integer: "Number",
                title_boolean: "True",
                placeholder_unixtime_year: "YYYY",
                placeholder_unixtime_month: "MM",
                placeholder_unixtime_day: "DD",
                placeholder_unixtime_hour: "HH",
                placeholder_unixtime_minute: "MM",

                title_active: "Is this filter row active? If the checkbox is disabled, then the filter is incomplete or invalid and it will be ignored.",
                title_column: "Which column to match against",
                title_operator: "Match type",
                title_button_add: "Add a new filter row at the end",
                title_button_remove: "Remove this filter row",
            },

            mass_op: {
                title: "Mass Operations",
                select_operation: "Select a mass operation:",
                proceed: "Proceed",
                hidden_warning: "<strong>WARNING:</strong> The selected filter hides some of the selected rows! Check the filter and your selection before you proceed.",

                status: {
                    selected: "selected",
                    ok: "successfull",
                    failed: "failed",
                },

                confirm: "Are you sure?",
                filtered_confirm: "The current filter has hidden some of the selected rows. Are you sure you want to continue?",

                select_all_visible: "Select all visible rows",
                deselect_all_visible: "Deselect all visible rows",
                invert_visible: "Invert selection on visible rows",
                select_all: "Select all",
                deselect_all: "Deselect all",
                deselect_invisible: "Deselect invisible rows",
                deselect_successfull: "Deselect successfully processed rows",
            },
        },

        // Sadly we can't get these from the main translations YAML file
        actions: {
            title: "Actions",
            edit: "Edit...",
            remove_confirm: "Are you sure?",
            remove: "Delete",
        },

        column_editor: {
            title: "Select columns",
            save: "Save",
            cancel: "Cancel",
            moveUp: "Move up",
            moveDown: "Move down",
            reset: "Reset",
            visible: "Visible?",
            name: "Name",
        },

        misc: {
            unset_group_type: "(Missing / not set)",
        },
    },

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------

    filters_users: {
        locked_users: "Locked users",
        marked_for_deletion: "Is marked for deletion",
        marked_for_deletion_not_locked: "Is marked for deletion, but not locked",
        marked_3months: "Has been marked for removal for ≥ 90 days",
        marked_6months: "Has been marked for removal for ≥ 180 days",
        marked_9months: "Has been marked for removal for ≥ 270 days",
        marked_12months: "Has been marked for removal for ≥ 365 days",
    },

    massop_users: {
        locking: {
            title: "Account locking...",
            action: "Action:",
            lock: "Lock (if not locked yet)",
            unlock: "Unlock (if locked)",
        },

        marking: {
            title: "Mark account for deletion...",
            action: "Action:",
            mark: "Mark for deletion if not marked yet",
            mark_force: "Force-mark for deletion and reset the timestamp to now (ie. \"always mark\")",
            unmark: "Unmark",
        },

        deletion: {
            title: "Account removal",
        },
    },
});
