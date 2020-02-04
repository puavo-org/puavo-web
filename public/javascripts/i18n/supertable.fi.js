I18n.translations || (I18n.translations = {});

I18n.translations["fi"] = I18n.extend((I18n.translations["fi"] || {}),
{
    supertable: {
        empty: "(Ei mitään näytettävää)",

        control: {
            select_columns: "Valitse sarakkeet...",
            select_columns_title: "Valitse näkyvät sarakkeet ja missä järjestyksessä",
            download_csv: "Lataa CSV...",
            download_csv_title: "Lataa näkyvän taulukon sisältö CSV-tiedostona",
            reload: "Päivitä",
            reload_title: "Päivitä taulukon sisältö ilman että koko sivu ladataan uudelleen",
            fetching: "Päivitetään...",
            failed: "Epäonnistui!",
            network_error: "Verkkovirhe?",
            server_error: "Palvelin palautti virheen ",
            timeout: "Aikakatkaisu, yritä uudelleen myöhemmin",
            json_fail: "JSONin tulkkaus epäonnistui, katso konsolia",
            status: "${total} ${itemName} yhteensä, ${filtered} suodatettu, ${visible} näkyvissä",
            select_placeholder: "(Valitse)",

            filtering_main_enabled: "Suodatus päällä",
            filtering_main_enabled_title: "Näytä vain tietyn kriteerin täyttävät rivit",
            filtering_main_reverse: "Käänteinen täsmäys",
            filtering_main_reverse_title: "Näytä vain rivit jotka EIVÄT täsmää annettuihin kriteereihin",
            filtering_presets: "Pohjat:",
            filtering_presets_title: "Käytä valmiiksi luotuja suodattimia",
            filtering_reset: "(Tyhjennä)",

            filter: {
                placeholder_string: "Regexp-tekstijono",
                placeholder_integer: "Numero",
                title_boolean: "Tosi",
                placeholder_unixtime_year: "VVVV",
                placeholder_unixtime_month: "KK",
                placeholder_unixtime_day: "PP",
                placeholder_unixtime_hour: "TT",
                placeholder_unixtime_minute: "MM",

                title_active: "Onko suodatinrivi aktiivinen? Jos ruksi on harmaa, suodatin on virheellinen/vajaa ja sitä ei käytetä.",
                title_column: "Mihin kenttään täsmäys kohdistetaan",
                title_operator: "Vertailun tyyppi",
                title_button_add: "Lisää uusi suodatinrivi listan loppuun",
                title_button_remove: "Poista tämä suodatinrivi",
            },

            mass_op: {
                title: "Massatoiminnot",
                select_operation: "Valitse massatoiminto:",
                proceed: "Suorita",
                hidden_warning:
                    "<strong>VAROITUS:</strong> Valittu suodatin piilottaa joitain " +
                     "valittuja rivejä! Tarkista suodatin ja valinnat ennen kuin suoritat " +
                     "massaoperaation.",

                status: {
                    selected: "valittu",
                    ok: "onnistui",
                    failed: "epäonnistui",
                },

                confirm: "Oletko varma?",
                filtered_confirm: "Nykyinen suodatin on piilottanut osan valituista riveistä. Haluatko jatkaa?",

                select_all_visible: "Valitse kaikki näkyvät rivit",
                deselect_all_visible: "Epävalitse näkyvät rivit",
                invert_visible: "Käänteinen valinta näkyvistä riveistä",
                select_all: "Valitse kaikki",
                deselect_all: "Epävalitse kaikki",
                deselect_invisible: "Epävalitse ei-näkyvät rivit",
                deselect_successfull: "Epävalitse onnistuneet rivit",
            },
        },

        // Sadly we can't get these from the main translations YAML file
        actions: {
            title: "Toiminnot",
            edit: "Muokkaa...",
            remove_confirm: "Oletko varma?",
            remove: "Poista",
        },

        column_editor: {
            title: "Valitse sarakkeet",
            save: "Tallenna",
            cancel: "Peruuta",
            moveUp: "Siirrä ylös",
            moveDown: "Siirrä alas",
            reset: "Oletukset",
            all: "Ruksaa kaikki",
            visible: "Näytä?",
            name: "Nimi",
        },

        misc: {
            unset_group_type: "(Puuttuu / ei asetettu)",
        },
    },

    // ---------------------------------------------------------------------------------------------
    // ---------------------------------------------------------------------------------------------

    filters_users: {
        locked_users: "Lukitut käyttäjät",
        marked_for_deletion: "Merkitty poistettavaksi",
        marked_for_deletion_not_locked: "Merkitty poistettavaksi, ei lukittu",
        marked_3months: "Merkitty poistettavaksi ≥ 90 päivää",
        marked_6months: "Merkitty poistettavaksi ≥ 180 päivää",
        marked_9months: "Merkitty poistettavaksi ≥ 270 päivää",
        marked_12months: "Merkitty poistettavaksi ≥ 365 päivää",
    },

    massop_users: {
        locking: {
            title: "Tunnuksen lukitus...",
            action: "Toiminto:",
            lock: "Lukitse (jos ei lukittu)",
            unlock: "Avaa (jos on lukittu)",
        },

        marking: {
            title: "Merkitse poistettavaksi...",
            action: "Toiminto:",
            mark: "Merkitse poistettavaksi jos ei ole jo",
            mark_force: "Merkitse poistettavaksi ja nollaa aikaleima nykyhetkeen (ts. \"pakota merkintä aina\")",
            unmark: "Poista merkintä",
        },

        deletion: {
            title: "Tunnuksen poisto",
        },
    },

    massop_groups: {
        deletion: {
            title: "Poista",
        },
    },
});
