I18n.translations || (I18n.translations = {});

I18n.translations["en"] = I18n.extend((I18n.translations["en"] || {}),
{
    // MISCELLANEOUS
    column_actions: "Actions",
    empty_table: "Empty table",
    empty: "(empty)",
    selected: "(Select)",
    see_console_for_details: "See the browser console for details.",
    are_you_sure: "Are you sure?",
    network_error: "Network error: ",
    network_connection_error: "Network connection error!",
    csv_generation_error: "Failed to generate the CSV file:",
    filter_conversion_failed: "Filter conversion failed:",
    new_filters_not_applied: "New filters not applied.",
    help: "Help...",

    tabs: {
        // TOOLS
        tools: {
            title: "Tools",
            reload: "Refresh table",
            csv: "Load as CSV",
            csv_only_visible: "Only visible rows",
        },

        // COLUMNS
        columns: {
            title: "Columns",
            help: "Check the columns and press the \"Save\" button to alter the visible columns. Press \"Default\" if you want to reset the columns. You can reorder the columns by dragging their headers with the mouse. Please note that adding or removing visible columns will refresh the table contents. Also, filters that target columns that aren't visible are ignored. You can restore the columns to an internal \"default order\" by clicking the \"Sort the columns in default order\" button.",
            selected: "Selected",
            total: "columns",
            unsaved_changes: "(Unsaved changes present)",
            save: "Save changes",
            defaults: "Defaults",
            all: "Select all",
            sort: "Sort the columns<br>in default order",
        },

        // FILTERS
        filtering: {
            title: "Filtering",
            enabled: "Enable filtering",
            reverse: "Reverse matching",
            presets: "Presets",
        },

        // MASS TOOLS
        mass: {
            title: "Mass tools",
            rows_title: "Rows",
            select_all: "Select all rows",
            deselect_all: "Deselect all rows",
            deselect_successfull: "Deselect successfully processed rows",
            invert_selection: "Invert selection",
            operation_title: "Operation",
            proceed: "Proceed",
            settings_title: "Operation settings",
        },
    },

    // STATUS TEXT
    status: {
        updating: "Updating...",
        total_rows: "rows total",
        visible_rows: "visible",
        filtered_rows: "filtered",
        selected_rows: "selected",
        successfull_rows: "successfull",
        failed_rows: "failed",
    },

    // THE FILTER EDITOR
    filter_editor: {
        // Filter list
        delete_all: "Delete all",
        delete_all_title: "Delete all current filters",
        show_json: "Show the JSON editor",
        hide_json: "Hide the JSON editor",
        toggle_json_title: "Show/hide the JSON editor",
        save_json: "Save JSON filter data",
        save_json_title: "Replace the current filters with the JSON data",

        // JSON validation
        invalid_json: "Invalid JSON data:",
        not_an_array: "The JSON data must be an array with zero or more elements.",
        data_requirements: "Every filter element must be an object that contains 'column', 'operator' and 'value' fields.",
        invalid_column: "Invalid column \"%{column}\".",
        invalid_operator: "Invalid operator \"%{operator}\".",
        column_type_mismatch: "Operator \"%{operator}\" (%{title}) cannot be used with column \"%{column}\".",
        use_regexps: "Please use the regexp | syntax to specify more than one value. Arrays will not work.",
        only_one_value: "%{type} type filters only support one value. Arrays will not work.",

        list: {
            explanation_broken: "Filter is broken",
            explanation_broken_hover: "This filter is broken in some way, so it cannot be used nor activated. Either fix the filter or remove it.",
            explanation_column_not_visible: "Target column is not visible",
            explanation_column_not_visible_hover: "This filter targets column that isn't visible, so it cannot be actually activated.",
            explanation_is_active: "Is this filter row active?",
            explanation_click_to_edit: "Click to edit this filter",
            explanation_unknown_column: "Unknown column",
            duplicate_row: "Duplicate",
            remove_row: "Remove",
            new_row: "Add a new filter...",
        },

        // Filter editor popup
        popup: {
            title_new: "New Filter",
            title_edit: "Edit Filter",
            target_title: "Target column:",
            target_warning: "Columns marked with an asterisk (*) are not visible right now. Filters targeting hidden columns are ignored, even if they're activated",
            operator_title: "Operator:",
            operator_warning: "Some operators are not available for certain column types.",
            comparison_title: "Comparison value:",
            save: "Save",
            cancel: "Cancel",
        },

        // Type-specific editors
        editor: {
            bool_true: "True",
            bool_false: "False",
            integer_missing_value: "Please enter at least one value.",
            string_help: "If this field is empty, it will be internally replaced with value \"^$\" which matches to an empty string. All regexp comparisons ignore letter case. As usual, you can specify more than one value if you separate them with |.",
            integer_help: "Numeric values are not verified. If you put letters or some other invalid value here, the comparison result can be completely random. Equality (=) and inequality (≠) comparisons accept multiple values if you separate them with |. For example: 12345|67890. Other comparisons use only the first value.",
            time_absolute: "Absolute (exact moment in time)",
            time_relative: "Relative (to now)",
            time_placeholder: "YYYY-MM-DD HH:MM:SS",
            time_absolute_help: "Enter the time in YYYY-MM-DD HH:MM:SS format. The more parts of it you specify, the more accurate the interpreted time is. Omitted month and day are assumed to be 1, and omitted time parts are zeroes.\n\nFor example, \"2021\" means 2021-01-01 at 00:00:00, and \"2021-02-16 13\" means 2021-02-16 13:00:00. Only 24-hour clock is supported.",
            time_relative_title: "Difference to now:",
            time_presets: "Presets:",
            time_direction: "Specifies the relative difference to the current time in seconds. Negative numbers are in the past, positive in the future. Because the time is always relative, it constantly changes. If you leave the page open for an hour, then reload it, the filter's target moment will also change by one hour.",
            time_dst_warning: "Conversions between UTC and local times, especially if they happen to cross DST transitions, can cause filters to be off by one hour in either direction.",

            time_missing_absolute: "Enter the absolute time",
            time_invalid_absolute: "The absolute time is invalid",
            time_invalid_absolute_year: "The absolute time year must be between %{min}-%{max}.",
            time_missing_relative: "Enter relative time",
            time_invalid_relative: "The relative time is invalid",
            time_invalid_relative_year: "The entered relative time produces the year %{full}, but years must be between %{min}-%{max}.",

            time_preset: {
                hours1: "-1 hour",
                hours12: "-12 hours",
                day1: "-1 day",
                week1: "-1 week",
                days30: "-30 days",
                days60: "-60 days",
                days90: "-90 days",
                days180: "-180 days",
                days270: "-270 days",
                days365: "-365 days",
            }
        },
    },
});
