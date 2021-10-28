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
    export_file_generation_error: "Ladattavan tiedoston luonti epäonnistui:",
    invalid_json: "Virheellinen JSON-data",
    temporary_mode: "Taulukko on väliaikaisessa tilassa. Asetuksia ei tallenneta pysyvästi (sivun lataus uudelleen hukkaa ne). Paina \"Poistu väliaikaisesta tilasta\" -nappia Työkalut -välilehdellä poistuaksesi tästä tilasta. Väliaikaisesta tilasta poistuminen korvaa nykyiset tallentamasi asetukset, joten ole varovainen.",
    help: "Ohje...",

    tabs: {
        // TOOLS
        tools: {
            title: "Työkalut",
            reload: "Päivitä taulukko",
            exit_temporary_mode: "Poistu väliaikaisesta tilasta",
            export: {
                title: "Lataa taulukon sisältö",
                as_csv: "Lataa taulukko CSV-tiedostona",
                as_json: "Lataa taulukko JSON-tiedostona",
                only_visible_rows: "Vain näkyvät rivit",
                only_visible_rows_help: "Sisällytä tiedostoon vain ne rivit jotka nykyinen suodatin näyttää. Muutoin tiedosto sisältää kaikki rivit.",
                only_visible_cols: "Vain näkyvät sarakkeet",
                only_visible_cols_help: "Sisällytä tiedostoon vain näkyvissä olevat sarakkeet. Muutoin tiedosto sisältää kaikkien sarakkeiden tiedot.",
            },
            store: {
                title: "Näkymän tallennus ja lataus",
                json_explanation: "Seuraava tekstilaatikko sisältää nykyisen taulukon sarakkeet ja niiden järjestyksen, sekä suodattimen asetukset JSON-muodossa. Sen sisällön kopioimalla voit helposti kopioida nykyiset asetukset toiseen taulukkoon. Voit ylläpitää itselläsi tekstitiedostossa isoakin kirjastoa erilaisista valmiista asetuksista. Jos et halua tallentaa (tai ladata) esimerkiksi sarakkeiden järjestystä tai lajittelua, voit poistaa sen kopioidusta JSONista käsin. Voit myös muokata sitä halutessasi suoraan, niin kauan kun pität JSON-rakenteen ehjänä.",
                json_load: "Lataa asetukset",
                json_load_help: "Ota nämä asetukset käyttöön",
                url_explanation: "Seuraava laatikko sisältää samat tiedot, mutta tässä ne tallennetaan URLiin. Voit lähettää linkin toiselle henkilölle haluamallasi tavalla ja hän voi sitä klikkaamalla avata saman näkymän. Huomaa, että tämän linkin avaaminen asettaa taulukon ns. \"väliaikaiseen\" tilaan, jossa muutoksia ei oikeasti tallenneta. Tämä siksi, että avattava linkki ei tuhoaisi avaajan jo mahdollisia käytössä olevia asetuksia. Väliaikaisesta tilasta voi poistua milloin tahansa.",
                copy_help: "Kopioi laatikossa oleva URL leikepöydälle",
                url_link: "Yllä oleva osoite klikattavana linkkinä"
            }
        },

        // COLUMNS
        columns: {
            title: "Sarakkeet",
            help: "Voit järjestellä sarakkeita raahaamalla niiden otsakkeita taulukossa hiirellä. Klikkaus = lajittele, raahaus = järjestele.",
            selected: "Valittu",
            total: "saraketta",
            search: "Etsi...",
            save: "Tallenna muutokset",
            defaults: "Oletukset",
            all: "Valitse kaikki näkyvät",
            none: "Epävalitse kaikki näkyvät",
            sort: "Lajittele sarakkeet<br>oletusjärjestykseen",
        },

        // FILTERS
        filtering: {
            title: "Suodatus",
            enabled: "Suodatus päällä",
            reverse: "Käänteinen täsmäys",
            advanced: "Käytä laajennettua suodatinta",

            delete_all: "Poista kaikki suodattimet",
            delete_all_title: "Poistaa kaikki listatut suodattimet",
            delete_all_confirm: "Oletko varma että haluat poistaa kaikki suodattimet?",
            show_json: "Näytä JSON-editori",
            hide_json: "Piilota JSON-editori",
            toggle_json_title: "Näytä/piilota JSON-editori",
            save_json: "Tallenna JSON-suodatin",
            save_json_title: "Korvaa nykyiset suodattimet JSON-kentän sisällöllä",
            save_json_confirm: "Korvaa nykyiset suodattimet tekstikentän sisällöllä?",
            json_title: "Suodattimien tiedot JSON-muodossa",
            new_filter: "Lisää uusi suodatin...",

            duplicate: "Monista",
            duplicate_title: "Monista tämä suodatinrivi",
            remove: "Poista",
            remove_title: "Poista tämä suodatinrivi",
            active_title: "Onko tämä suodatin aktiivinen?",
            click_to_edit_title: "Klikkaa muokataksesi suodatinta",

            edit_column_title: "Mitä saraketta suodatin koskee",
            edit_operator_title: "Millä tavalla sarakkeen arvoa verrataan?",

            save: "Tallenna",
            clear: "Tyhjennä",
            convert: "Kopioi ja muunna perinteinen suodatin",
            cancel: "Peruuta",
            unsaved: "muutettu, ei tallennettu",

            expression_title: "Suodatinlauseke",
            messages_title: "Käännösviestit",
            type: "Tyyppi",
            row: "Rivi",
            column: "Sarake",
            message: "Viesti",

            error: "Virhe",
            warning: "Varoitus",

            expression_placeholder: "Syötä suodatinlauseke tähän",
            no_messages: "(Suodatinlausekkeesta ei löytynyt ongelmia)",

            traditional_filter_is_empty: "Perinteinen suodatin on tyhjä.",

            messages: {
                column_not_visible: "Sarake ei ole näkyvissä. Varo, ettei suodatin näytä tai piilota rivejä joita sen ei pitäisi.",
                expected_column_name: "Tässä oletettiin olevan sarakkeen nimi (tuntematon sarake?)",
                expected_operator: "Tässä oletettiin olevan verailuoperaattori",
                expected_value_rpar: "Tässä oletettiin olevan joko vertailtava arvo tai ')'",
                incompatible_operator: "Tätä operaattoria ei voi käyttää tämän saraketyypin kanssa",
                invalid_operator: "Virheellinen vertailuoperaattori",
                invalid_regexp: "Virheellinen regexp-jono",
                invalid_sign: "Virheellinen etumerkki",
                invalid_storage_unit: "Virheellinen tallennustilan yksikkö",
                invalid_time_unit: "Virheellinen aikayksikkö",
                not_a_number: "Virheellinen numero",
                missing_time_unit: "Puuttuva aikayksikkö, oletetaan sekunneiksi (ei ehkä mitä tarkoitit)",
                syntax_error: "Syntaksivirhe",
                unbalanced_nesting: "Sulkeiden määrä ei ole parillinen",
                unexpected_column_name: "Sarakkeen nimeä ei odotettu tässä kohdassa",
                unexpected_end: "Syöte päättyi kesken",
                unexpected_lpar: "Odottamaton ')'",
                unexpected_negation: "Odottamaton '!'",
                unexpected_rpar: "Odottamaton ')'",
                unknown_column: "Tuntematon sarake",
                unknown_error: "Tuntematon virhe :-(",
                unknown_operator: "Tuntematon operaattori",
                unparseable_time: "Aikaa ei voida tulkita absoluuttisena eikä suhteellisena aikana",
                unterminated_string: "Päättämätön tekstijono",
            },

            presets: {
                title: "Valmiit suodatinmallit",
                click_to_add: "Lataa suodatinmalli klikkaamalla sen nimeä alla olevassa listassa. Voit valita korvaako uusi suodatin kaikki, vai lisätäänkö sen sisältö olemassaolevien loppuun. Näin voit koota isojakin suodattimia pienistä paloista. Jos et ole varma mitä malli tekee, kopioi olemassaoleva suodatin talteen JSON-muodossa ennen lisäämistä. Jos mallin lisäys ei tuottanut haluttua tulosta, voit kumota sen kopioimalla talteen otetun JSON-suodattimen takaisin tekstilaatikkoon.",
                instructions: "Alla olevassa taulukossa on valmiiksi kirjoitettuja suodatinmalleja. Klikkaa haluamasi mallin nimeä kopioidaksesi sen lausekkeen tekstilaatikkoon. Voit valita korvaako malli laatikon sisällön kokonaan vai lisätäänkö malli jo olemassaolevan sisällön loppuun. Koska suodatinlausekkeessa voi käyttää sulkuja ja loogisia &&, || ja ! -operaatioita, voit halutessasi lisätä mallin ympärille sulut samalla kun se kopioidaan laatikkoon. Näin voit koota palasista vaikka kuinka monimutkaisen suodattimen helposti. Voit myös kopioida lausekkeen suoraan taulukosta mikäli kumpikaan lisäystapa ei ole sopiva.",
                append: "Lisää loppuun, älä korvaa kokonaan",
                add_parenthesis: "Lisää lausekkeen ympärille sulut",
                name: "Mallin nimi",
                expression: "Lauseke",
            },

            column_list: {
                title: "Sarakelista",
                hidden_warning: "Joidenkin sarakkeiden sisältö voi olla tietokannassa kokonaan tyhjä (NULL), ja niiden puuttuva arvo voi siksi vaikuttaa arvaamattomasti sisältövertailuissa. Sarakkeet jotka voivat olla tyhjiä on merkitty taulukkoon; näiden sarakkeiden kanssa kannattaa käyttää <code>!!</code> -operaattoria testamaan että niille oikeasti on (tai ei ole) annettu arvo ennenkuin varsinaisesti vertailet niiden sisältöä. Näin vältyt yllätyksiltä.",
                pretty_name: "Kohdesarake",
                database_name: "Lausekkeen vastaavavat nimet<br>(klikkaa lisätäksesi)",
                type: "Tyyppi",
                operators: "Käytössä olevat operaattorit",
                nullable: "Voi olla tyhjä?",

                type_bool: "Totuusarvo",
                type_numeric: "Numeerinen",
                type_unixtime: "Aika",
                type_string: "Teksti",
                is_nullable: "Kyllä",
            },

            url: {
                button: "linkki...",
                title: "Kopioitava linkki",
                explanation: "Voit kopioida nykyisen suodattimen toiseen välilehteen tai selaimeen avaamalla seuraavan linkin toisessa selaimessa. Tämä kopioitu linkki ei korvaa avaajan senhetkistä suodatinta jollei sitä erikseen tallenneta. Huomaa, että \"Käänteinen täsmäys\" -asetus ei välity linkin kautta, joten suunnittele suodatinlauseke sitä silmällä pitäen.",
                copy: "Kopioi",
            },

            pretty: {
                empty: "(tyhjä)",
                or: "tai",
                nor: "eikä",
                interval: "väliltä",
                not_interval: "ei väliltä",
            },

            ed: {
                closed: "Määritä väli jonka sisällä arvon on oltava. Alku- ja loppuarvo sisältyvät alueeseen.",
                open: "Määritä väli jonka sisällä arvo ei saa olla. Alku- ja loppuarvo eivät sisälly alueeseen.",
                invalid_interval: "Määritä kunnollinen pienin ja suurin arvo.",

                single: "Valittu vertailu kelpuuttaa vain yhden arvon.",
                multiple: "Voit määrittää useita arvoja.",
                one_hit_is_enough: "Yksikin osuma riittää.",
                no_hits_allowed: "Mikään niistä ei saa osua.",
                regexp: "Kaikki vertailut ovat regexp-vertailuja jotka eivät välitä kirjainkoosta. Muistathan, että jos etsimässäsi tekstissä esiintyy merkkejä jotka tarkoittavat jotain regexp-lauseissa, sinun on eskapoitava (\\) ne.",
                no_values: "Et määrittänyt yhtään vertailtavaa arvoa.",

                bool: {
                    t: "Kyllä",
                    f: "Ei",
                },

                numeric: {
                    nan: "ei ole numero.",
                    negative_storage: "Negatiiviset tallennustilat eivät ole sallittuja.",
                },

                time: {
                    invalid: "ei ole absoluuttinen eikä suhteellinen aika.",
                    help_link: "Näytä ohje siitä miten ajat määritetään",
                    help: `Käytettävissä on kaksi aikamuotoa: absoluuttinen ja suhteellinen.\n\nAbsoluuttinen aika on muotoa VVVV-KK-PP TT:MM:SS. Mitä useamman osan kirjoitat, sitä tarkempi aika on. Poisjätetyt päivä ja kuukausi ovat 1, ja poisjätetyt tunti, minuutti ja sekunti ovat 0. "2021" tarkoittaa "2021-01-01 00:00:00", "2021-09" tarkoittaa "2021-09-01 00:00:00", "2021-09-22 13" tarkoittaa "2021-09-22 13:00:00" ja niin edelleen. Kellonaika on aina 24-tuntinen. Vuosilukujen on oltava väliltä 2000 ja 2050.\n\nSuhteellinen aika ilmaisee ajan sekunteina suhteessa hetkeen jolloin taulukko päivitetään. Negatiiviset luvut osoittavat menneisyyteen, positiiviset tulevaisuuteen. Luvun perään kirjoitetaan yksikkö, ne ovat: "s" (sekunti), "h" (tunti), "d" (päivä), "w" (viikko), "m" (30-päiväinen kuukausi), "y" (365-päiväinen vuosi). Esimerkiksi "-2h" tarkoittaa "tasan 2 tuntia sitten", "-1d" tarkoittaa "tasan yksi päivä sitten" (eli -86400 sekuntia) ja "-8m" tarkoittaa "tasan kahdeksan kuukautta sitten". Käytännössä käytät negatiivisia aikoja lähes aina.`,
                }
            },
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
            mass_row_title: "Massavalitse rivejä...",
            mass_row_help: "Syötä yksi tai useampi nimi, lyhenne, ID, tai jokin muu yksilöllinen tunniste. Valitse sitten niiden tyyppi, ja paina \"Valitse\" tai \"Poista valinnat\". Rivit jotka eivät täsmänneet mihinkään muutetaan <span class=\"unmatchedRow\">eri väriseksi</span>. Voit muokata niitä ja suorittaa valinnan uudelleen. Duplikaatit ja tyhjät rivit poistetaan.",
            mass_row_type: "Tyyppi:",
            mass_row_select: "Valitse",
            mass_row_deselect: "Poista valinnat",
            mass_row_status: "%{total} riviä, %{match} täsmäsi, %{unmatched} ei täsmännyt",
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

    // PAGINATION
    paging: {
        rows_per_page: "Rivejä/sivu:",
        rows_per_page_title: "Montako riviä näytetään per sivu",
        first_title: "Ensimmäinen sivu",
        prev_title: "Edellinen sivu",
        next_title: "Seuraava sivu",
        last_title: "Viimeinen sivu",
        jump_to_page_title: "Hyppää suoraan sivulle",
    },
});
