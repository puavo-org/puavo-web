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
    invalid_json: "Invalid JSON data",
    temporary_mode: "This table is in a temporary mode. Settings will not be saved (reloading the page loses them). Click the \"Exit temporary mode\" button on the \"Tools\" page to exit the temporary mode. Exiting the temprary mode will replace your currently saved settings, so be careful.",
    help: "Help...",

    tabs: {
        // TOOLS
        tools: {
            title: "Tools",
            reload: "Refresh table",
            exit_temporary_mode: "Exit the temporary mode",
            export: {
                title: "Download table contents",
                as_csv: "Download as CSV file",
                only_visible_rows: "Only visible rows",
                only_visible_rows_help: "Include only the rows the current filter makes visible. Otherwise the file includes all rows.",
                only_visible_cols: "Only visible columns",
                only_visible_cols_help: "Include only the columns that are currently visible. Otherwise the file includes content from all columns.",
            },
            store: {
                title: "Save and load the view",
                json_explanation: "The following text box includes the currently visible columns and their order, and the current filter settings, in JSON format. By copying its contents, you can easily copy the current settings into another table. You can maintain a library of various premade settings in a text file. You can remove unneeded parts from it; for example, if you don't need to store columns and their order, simply remove them from the JSON. You can also edit the JSON and change the table settings directly, as long as you don't break the JSON structure.",
                json_load: "Load settings",
                json_load_help: "Apply these settings",
                url_explanation: "The following box contains the same settings, but here they're saved in a URL. You can send it to another person in any way you want and when they open it, they will see the exact same view you're seeing. Please note that opening this link sets the table in a so-called \"temporary mode\". In temporary mode, settings are not saved. This ensures the settings in the URL do not replace the already saved settings of the person who opens the link. The temporary mode can be exited at any time.",
                copy_help: "Copy the URL to clipboard",
                url_link: "The address above as a clickable link"
            }
        },

        // COLUMNS
        columns: {
            title: "Columns",
            help: "You can reorder the columns by dragging their headers with the mouse. Click = sort, drag = reorder.",
            selected: "Selected",
            total: "columns",
            save: "Save changes",
            defaults: "Defaults",
            all: "Select all",
            sort: "Sort the columns<br>in default order",
        },

        // FILTERS
        filtering: {
            title: "Filtering",
            enabled: "Enable filtering",
            reverse: "Reverse match",
            advanced: "Use advanced filter",

            delete_all: "Delete all filters",
            delete_all_title: "Delete all filter rows",
            delete_all_confirm: "Are you sure you want to remove all filters?",
            show_json: "Show the JSON editor",
            hide_json: "Hide the JSON editor",
            toggle_json_title: "Show/hide the JSON editor",
            save_json: "Save JSON filter data",
            save_json_title: "Replace the current filters with the JSON data",
            save_json_confirm: "Replace the current filters with the JSON format filters?",
            json_title: "Filters in JSON format",
            new_filter: "Add a new filter...",

            duplicate: "Duplicate",
            duplicate_title: "Duplicate this filter row",
            remove: "Remove",
            remove_title: "Remove this filter row",
            active_title: "Is this filter active?",
            click_to_edit_title: "Click to edit filter",

            edit_column_title: "What column this filter targets?",
            edit_operator_title: "How is the column contents compared?",

            save: "Save",
            clear: "Clear",
            cancel: "Cancel",
            unsaved: "changed, not saved",

            expression_title: "Filter string",
            messages_title: "Compilation messages",
            type: "Type",
            row: "Row",
            column: "Column",
            message: "Messages",

            error: "Error",
            warning: "Warning",

            expression_placeholder: "Enter the filter string here",
            no_messages: "(No problems were found in the filter string)",

            messages: {
                column_not_visible: "Column is not visible. Be careful, it can show or hide rows it should not.",
                expected_column_name: "Expected a column name here (unknown column name?)",
                expected_operator: "Expected a comparison operator here",
                expected_value_rpar: "Expected a comparison value or ')' here",
                incompatible_operator: "This operator cannot be used with this column type",
                invalid_operator: "Invalid comparison operator",
                invalid_regexp: "Invalid regexp string",
                invalid_sign: "Invalid sign",
                invalid_storage_unit: "Invalid storage unit specifier",
                invalid_time_unit: "Invalid time unit",
                not_a_number: "Invalid number",
                missing_time_unit: "Missing time unit, assuming seconds (probably not what you meant)",
                syntax_error: "Syntax error",
                unbalanced_nesting: "Unbalanced parenthesis",
                unexpected_column_name: "Did not expect a column name here",
                unexpected_end: "Unexpected end of input",
                unexpected_lpar: "Unexpected ')'",
                unexpected_negation: "Unexpected '!'",
                unexpected_rpar: "Unexpected ')'",
                unknown_column: "Unknown column",
                unknown_error: "Unknown error :-(",
                unknown_operator: "Unknown operator",
                unparseable_time: "This string cannot be interpreted as an absolute nor relative time",
                unterminated_string: "Unterminated string",
            },

            presets: {
                title: "Filter Templates",
                click_to_add: "Load a filter preset by clicking its name on the list below. You can choose if the new filter should replace the existing one, or if its contents should be appended at the end. This way, you can build large filters by combining smaller parts. If you're unsure of what the preset does, make a copy of the existing filter in JSON format first. Then, if adding the preset did not accomplish what you wanted, you can undo the addition by putting the copied filter back in the JSON text box.",
                instructions: "The table below lists premade filter templates. Click the title of the template to copy it into the filter text box. You can select whether the template replaces the existing filter string, or if it's merely appended at the end. Because you can use parenthesis and logical operators (&&, || and !) for grouping, you can have the inserted template to be automatically surrounded with parenthesis. This way, you can piece together multiple expressions and construct complex filters easily. You can of course select and copy the filter expression directly from the table if neither insertion method suits your needs.",
                append: "Append at the end, don't replace",
                add_parenthesis: "Surround the expression with parenthesis",
                name: "Template name",
                expression: "Expression",
            },

            column_list: {
                title: "Column List",
                hidden_warning: "Certain columns can be completely empty (NULL) in the database, and their completely missing values can mess up comparisons. These columns have been also marked on the table; it is recommended that you use the <code>!!</code> operator to test that they actually have (or don't have) a value before you compare their contents. This way you avoid surprises.",
                pretty_name: "Column name",
                database_name: "Equivalent names in filters<br>(click to add)",
                type: "Type",
                operators: "Available operators",
                nullable: "Can be empty?",

                type_bool: "Boolean",
                type_numeric: "Numeric",
                type_unixtime: "Time/date",
                type_string: "Text",
                is_nullable: "Yes",
            },

/*
            url: {
                explanation: "Voit kopioida nykyisen suodattimen toiseen välilehteen tai selaimeen avaamalla seuraavan linkin toisessa selaimessa. Tämä kopioitu linkki ei korvaa avaajan senhetkistä suodatinta jollei sitä erikseen tallenneta. Huomaa, että \"Käänteinen täsmäys\" -asetus ei välity linkin kautta, joten suunnittele suodatinlauseke sitä silmällä pitäen.",
                copy: "Copy",
            },
*/

            pretty: {
                empty: "(empty)",
                or: "or",
                nor: "nor",
                interval: "between",
                not_interval: "not between",
            },

            ed: {
                include: "Specify an interval the value must be inside of.",
                exclude: "Specify an interval the value must not be inside of.",
                interval: " The interval is closed, so the minimum and maximum values are included in in.",
                invalid_interval: "Specify valid minimum and maximum values.",

                single: "This operator accepts only one value.",
                multiple: "You can specify multiple values.",
                one_hit_is_enough: "A single match is enough.",
                no_hits_allowed: "None of the values must match.",
                regexp: "All comparisons are done using regular expressions that ignore character case. Remember that if you're searching for characters that have special meaning in regexps, you must escape (\\) them.",
                no_values: "You did not specify any comparison values.",

                bool: {
                    t: "Yes",
                    f: "No",
                },

                numeric: {
                    nan: "is not a number.",
                    negative_storage: "Negative storage sizes are not permitted.",
                },

                time: {
                    invalid: "is neither absolute nor relative time.",
                    help_link: "Show instructions on how dates and times are specified",
                    help: `There are two formats available: absolute and relative.\n\nAbsolute times are formatted as YYYY-MM-DD HH:MM:SS. The more parts you specify, the more accurate it becomes. Omitted day and month are assumed to be 1, and omitted hours, minutes and seconds are 0. "2021" means "2021-01-01 00:00:00", "2021-09" means "2021-09-01 00:00:00", "2021-09-22 13" means "2021-09-22 13:00:00" and so on. All times are in 24-hour format. The year must be between 2000 and 2050.\n\nRelative time specifies the time relatively, in seconds, to the moment when the table is updated. Negative numbers point to the past, positive to the future. After the number comes the unit, they are: "s" (second), "h" (hour), "d" (day), "w" (week), "m" (30-day month), "y" (365-day year). For example, "-2h" means "exactly two hours ago", "-1d" means "exactly 1 day (86400 seconds) ago", and "-8m" means "exactly 8 months ago". In practice, you'll be using negative numbers almost always.`,
                }
            },
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
});
