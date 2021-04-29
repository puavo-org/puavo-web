I18n.translations || (I18n.translations = {});

I18n.translations["fi"] = I18n.extend((I18n.translations["fi"] || {}),
{
    // MISCELLANEOUS
    column_actions: "Toiminnot",
    empty_table: "Tyhjä taulukko",
    empty: "(tyhjä)",
    selected: "(Valitse)",
    see_console_for_details: "Katso selaimen konsolista lisätietoja.",
    are_you_sure: "Oletko varma?",
    network_error: "Verkkovirhe: ",
    network_connection_error: "Verkkoyhteysongelma!",
    csv_generation_error: "CSV-tiedoston luonti epäonnistui:",
    filter_conversion_failed: "Suodattimien muuntaminen epäonnistui:",
    new_filters_not_applied: "Uusia suodattimia ei otettu käyttöön.",
    help: "Ohje...",

    tabs: {
        // TOOLS
        tools: {
            title: "Työkalut",
            reload: "Päivitä taulukko",
            csv: "Lataa CSV",
            csv_only_visible: "Vain näkyvät rivit",
        },

        // COLUMNS
        columns: {
            title: "Sarakkeet",
            help: "Ruksaa haluamasi sarakkeet ja paina \"Tallenna\" muuttaaksesi näkyviä sarakkeita. Paina \"Oletukset\" jos haluat nollata sarakkeet oletuksiin. Voit järjestellä sarakkeita raahaamalla niiden otsakkeita taulukossa hiirellä. Huomaa, että näkyvien sarakkeiden muutto hakee taulukon sisällön uudelleen. Lisäksi suodattimet jotka koskevat sarakkeita jotka eivät ole näkyvissä jätetään huomioimatta. Voit palauttaa sarakkeet sisäiseen \"oletusjärjestykseen\" painamalla \"Lajittele sarakkeet oletusjärjestykseen\" -painiketta.",
            selected: "Valittu",
            total: "saraketta",
            unsaved_changes: "(Tallentamattomia muutoksia on tehty)",
            save: "Tallenna muutokset",
            defaults: "Oletukset",
            all: "Valitse kaikki",
            sort: "Lajittele sarakkeet<br>oletusjärjestykseen",
        },

        // FILTERS
        filtering: {
            title: "Suodatus",
            enabled: "Suodatus päällä",
            reverse: "Käänteinen täsmäys",
            presets: "Suodatinpohjia",
        },

        // MASS TOOLS
        mass: {
            title: "Massatoiminnot",
            rows_title: "Rivit",
            select_all: "Valitse kaikki rivit",
            deselect_all: "Epävalitse kaikki rivit",
            deselect_successfull: "Epävalitse onnistuneesti käsitellyt rivit",
            invert_selection: "Käänteinen valinta",
            operation_title: "Operaatio",
            proceed: "Suorita",
            settings_title: "Operaation asetukset",
        },
    },

    // STATUS TEXT
    status: {
        updating: "Päivitetään...",
        total_rows: "riviä yhteensä",
        visible_rows: "näkyvissä",
        filtered_rows: "suodatettu pois",
        selected_rows: "valittu",
        successfull_rows: "onnistui",
        failed_rows: "epäonnistui",
    },

    // THE FILTER EDITOR
    filter_editor: {
        // Filter list
        delete_all: "Poista kaikki",
        delete_all_title: "Poista kaikki nykyiset suodattimet",
        show_json: "Näytä JSON-editori",
        hide_json: "Piilota JSON-editori",
        toggle_json_title: "Näytä/piilota JSON-editori",
        save_json: "Tallenna JSON-suodatin",
        save_json_title: "Korvaa nykyiset suodattimet JSON-kentän sisällöllä",

        // JSON validation
        invalid_json: "Virheellinen JSON-data:",
        not_an_array: "JSON-datan täytyy olla taulukko, jossa on nolla tai useampi elementti.",
        data_requirements: "Jokaisen suodatinelementin on oltava objekti, joka sisältää vähintään 'column', 'operator' ja 'value' -kentät.",
        invalid_column: "Virheellinen sarake \"%{column}\".",
        invalid_operator: "Virheellinen operaattori \"%{operator}\".",
        column_type_mismatch: "Operaattoria \"%{operator}\" (%{title}) ei voi käyttää sarakkeen \"%{column}\" vertailuissa.",
        use_regexps: "Käytä regexpin | -syntaksia määrittääksesi useamman arvon. Taulukkot eivät toimi.",
        only_one_value: "%{type} -tyyppiset suodattimet tukevat vain yhtä arvoa. Taulukkot eivät toimi.",

        list: {
            explanation_broken: "Suodatin on rikki",
            explanation_broken_hover: "Tämä suodatin on jollain tavalla rikki, joten sitä ei voi käyttää. Korjaa tai poista suodatin.",
            explanation_column_not_visible: "Kohdesarake ei näkyvissä",
            explanation_column_not_visible_hover: "Tämä suodatin koskee saraketta joka ei ole näkyvissä, joten sitä ei voi oikeasti aktivoida.",
            explanation_is_active: "Onko tämä suodatinrivi aktiivinen?",
            explanation_click_to_edit: "Klikkaa muokataksesi tätä suodatinta",
            explanation_unknown_column: "Tuntematon sarake",
            duplicate_row: "Monista",
            remove_row: "Poista",
            new_row: "Lisää uusi suodatin...",
        },

        // Filter editor popup
        popup: {
            title_new: "Uusi suodatin",
            title_edit: "Muokkaa suodatinta",
            target_title: "Kohdesarake:",
            target_warning: "Tähdellä (*) merkityt sarakkeet eivät ole juuri nyt näkyvissä. Piilotettuja sarakkeita koskevia suodattimia ei käytetä, vaikka ne olisi ruksattu aktiiviseksi.",
            operator_title: "Operaattori:",
            operator_warning: "Kaikkia vertailutyyppejä ei voi käyttää kaikkien saraketyyppien kanssa.",
            comparison_title: "Vertailtava arvo:",
            save: "Tallenna",
            cancel: "Peruuta",
        },

        // Type-specific editors
        editor: {
            bool_true: "Tosi",
            bool_false: "Epätosi",
            integer_missing_value: "Anna vähintään yksi vertailtava arvo.",
            string_help: "Jos kenttä on tyhjä, se korvataan sisäisesti arvolla \"^$\" joka täsmää tyhjään tekstijonoon. Kaikki regexp-vertailut tehdään aina välittämättä kirjainkoosta. Kuten regexp-lausekkeissa yleensäkin, voit antaa useita arvoja jos erotat ne | -merkillä.",
            integer_help: "Numeerista arvoa ei tarkisteta. Jos kirjoitat tähän kirjaimia tai muuten vaan virheellisen numeron, voi vertailun lopputulos olla ihan mitä tahansa. Yhtäsuuruus (=) ja erisuuruus (≠) -vertailuissa voit määrittää useita arvoja jos erotat ne toisistaan | merkillä, esimerkiksi 12345|67890. Muissa vertailuissa käytetään vain ensimmäistä arvoa.",

            time_absolute: "Absoluuttinen (tietty hetki ajassa)",
            time_relative: "Suhteellinen (nykyhetkeen verrattuna)",
            time_placeholder: "VVVV-KK-PP TT:MM:SS",
            time_absolute_help: "Kirjoita aika muodossa VVVV-KK-PP TT:MM:SS. Aika on sitä tarkempi, mitä enemmän osia siitä kirjoitat kenttään. Puuttuva kuukausi ja päivä oletetaan ykkösiksi, ja puuttuvat kellonajat ovat nollia.\n\nEsimerkiksi \"2021\" tarkoittaa 1.1.2021 kello 00:00:00 ja \"2021-02-16 13\" tarkoittaa 16.02.2021 kello 13:00. Kellonajat ovat aina 24-tuntisia.",
            time_relative_title: "Ero nykyhetkeen sekunneissa:",
            time_presets: "Valmiita aikoja:",
            time_direction: "Määrittää eron nykyhetkeen sekunneissa. Negatiiviset luvut osoittavat menneisyyteen, positiiviset tulevaisuuteen. Koska aika on aina suhteellinen nykyhetkeen, se muuttuu koko ajan. Jos jätät sivun auki tunniksi ja päivität sen sitten, muuttuu myös suodattimenkin kohdeaika yhdellä tunnilla.",
            time_dst_warning: "UTC- ja paikallisaikojen muutokset, erityisesti kesä-/talviaikojen muutosten yli, voi aiheuttaa vertailuihin tunnin virheitä suuntaan tai toiseen.",
            time_missing_absolute: "Syötä absoluuttisen ajan arvo",
            time_invalid_absolute: "Absoluuttinen aika on virheellinen",
            time_invalid_absolute_year: "Absoluuttisen ajan vuosiluvun on oltava väliltä %{min}-%{max}.",
            time_missing_relative: "Syötä suhteellisen ajan arvo",
            time_invalid_relative: "Suhteellinen aika on virheellinen",
            time_invalid_relative_year: "Syötetty suhteellinen aika tuottaa vuosiluvun %{full}, mutta vuosilukujen on oltava väliltä %{min}-%{max}.",

            time_preset: {
                hours1: "-1 tunti",
                hours12: "-12 tuntia",
                day1: "-1 päivä",
                week1: "-1 viikko",
                days30: "-30 päivää",
                days60: "-60 päivää",
                days90: "-90 päivää",
                days180: "-180 päivää",
                days270: "-270 päivää",
                days365: "-365 päivää",
            }
        },
    },
});
