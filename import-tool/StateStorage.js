

export default function createStateStorage(stateKey) {
    return createStore => (reducer, initialState) => {
        const store = createStore(wrapReducer(reducer, stateKey), initialState);
        window.onbeforeunload = (e) => {
            store.dispatch(saveState());
        };
        store.dispatch(restoreState());
        return store;
    };
}

function wrapReducer(defaultReducer, stateKey) {
    var reseting = false;

    return (state, action) => {
        if (action.type === "RESET_STATE") {
            delete window.localStorage[stateKey];
            reseting = true;
            setTimeout(() => window.location.reload(), 1);
        }

        if (action.type === "RESTORE_STATE") {
            try {
                state = JSON.parse(window.localStorage[stateKey]);
            } catch(error) {
                console.warn("Invalid existing state", error.message);
            }
        }

        if (!reseting && action.type === "SAVE_STATE") {
            window.localStorage[stateKey] = JSON.stringify(state);
        }

        return defaultReducer(state, action);
    };
}

export function saveState() {
    return {type: "SAVE_STATE"};
}

export function restoreState() {
    return {type: "RESTORE_STATE"};
}

export function resetState() {
    return {type: "RESET_STATE"};
}
