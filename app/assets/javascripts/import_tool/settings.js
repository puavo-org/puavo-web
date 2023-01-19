import { clampPasswordLength } from "./main.js";

// A crude mechanism for updating the saved settings
const EXPECTED_SETTINGS_VERSION = 3;

function loadDefaultSettings()
{
    return {
        version: EXPECTED_SETTINGS_VERSION,
        mainTab: 0,
        parser: {
            sourceTab: 0,
            infer: false,
            trim: true,
            separator: 0,   // 0=comma, 1=semicolon, 2=tab
        },
        import: {
            mode: 1,        // 0=full sync, 1=import new users only, 2=update existing users only
            overwrite: true,
            username: {
                umlauts: 0,
                first_first_only: true,
            },
            password: {
                randomize: true,
                uppercase: true,
                lowercase: true,
                numbers: true,
                punct: false,
                length: 12,
            },
        }
    };
}

// Try to save all settings to localhost
export function saveSettings(settings)
{
    try {
        localStorage.setItem("importSettings", JSON.stringify(settings));
    } catch (e) {
        console.error("saveSettings(): failed to save the settings:");
        console.error(e);
    }
}

// Try to restore all settings from localhost. If they cannot be loaded,
// resets them to defaults and saves them.
export function loadSettings()
{
    const defaults = loadDefaultSettings();

    const raw = localStorage.getItem("importSettings");

    if (!raw) {
        // Initialize new settings
        saveSettings(defaults);
        return defaults;
    }

    let settings = null;

    try {
        settings = JSON.parse(raw);
    } catch (e) {
        console.error("loadSettings(): can't parse the stored JSON:");
        console.error(e);
        saveSettings(defaults);

        return;
    }

    let out = {};

    if (settings.version === EXPECTED_SETTINGS_VERSION)
        out = {...defaults, ...settings};
    else {
        console.warn("Settings version number changed, reset everything");
        saveSettings(defaults);
    }

    out.import.password.length = clampPasswordLength(out.import.password.length);

    return out;
}
