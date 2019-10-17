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
            filtering_main_enabled: "Enable filtering",
            filtering_main_enabled_title: "Only show rows that match the specified criteria",
            filtering_main_reverse: "Reverse matching",
            filtering_main_reverse_title: "Only show rows that DON'T match the specified criteria",
            filtering_presets: "Presets:",
            filtering_presets_title: "Use a pre-made filter",
            filtering_select: "(Select)",
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
    }
});
