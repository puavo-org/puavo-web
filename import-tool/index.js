const REDUX_DEV = !!window.localStorage.REDUX_DEV;

const STATE_KEY = [
    "import-tool",
    window.location.toString(),
    /* global __webpack_hash__ */
    process.env.NODE_ENV === "production" ? __webpack_hash__ : "DEV",
].join(":");

require("babel-runtime/core-js/promise").default = require("bluebird");
window.Promise = require("bluebird"); // extra override
import "babel/polyfill";

import React from "react";
import R from "ramda";
import {combineReducers, createStore, applyMiddleware, compose} from "redux";
import createLogger from "redux-logger";
import thunk from "redux-thunk";
import {Provider} from "react-redux";
import * as reducers from "./reducers";
import {devTools as createDevTools} from "redux-devtools";
import {DevTools, DebugPanel, LogMonitor} from "redux-devtools/lib/react";

import createStateStorage from "./StateStorage";

import ImportTool from "./components/ImportTool";

const devTools = REDUX_DEV ? createDevTools() : R.identity;

const logger = createLogger();



const createFinalStore = compose(
    createStateStorage(STATE_KEY),
    applyMiddleware(thunk, logger),
    devTools
)(createStore);

const combinedReducers = combineReducers(reducers);

function createImportTool(containerId, schoolDn) {
    var container = document.getElementById(containerId);
    const store = createFinalStore(combinedReducers);
    store.dispatch({
        type: "SET_DEFAULT_SCHOOL",
        schoolDn,
    });

    container.innerHTML = "";
    React.render(
        <div>
            <Provider store={store}>
                {() => <ImportTool />}
            </Provider>
            {REDUX_DEV &&
            <DebugPanel top right bottom>
              <DevTools store={store}
                        monitor={LogMonitor} />
            </DebugPanel>}
        </div>
    , container);
}

window.createImportTool = createImportTool;
