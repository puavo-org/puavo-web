const REDUX_DEV = !!window.localStorage.REDUX_DEV;

require("babel-runtime/core-js/promise").default = require("bluebird");
window.Promise = require("bluebird"); // extra override
import "babel/polyfill";

import React from "react";
import R from "ramda";
import {combineReducers, createStore, applyMiddleware, compose} from "redux";
import thunk from "redux-thunk";
import {Provider} from "react-redux";
import * as reducers from "./reducers";
import {devTools as createDevTools} from "redux-devtools";
import {DevTools, DebugPanel, LogMonitor} from "redux-devtools/lib/react";

import ImportTool from "./components/ImportTool";

const devTools = REDUX_DEV ? createDevTools() : R.identity;

const createFinalStore = compose(
    applyMiddleware(thunk),
    devTools,
    createStore
);

const combinedReducers = combineReducers(reducers);
const store = createFinalStore(combinedReducers);

var container = document.getElementById("import-tool");
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
