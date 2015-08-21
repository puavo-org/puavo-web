
import React from "react";
import {combineReducers, createStore, applyMiddleware, compose} from "redux";
import thunk from "redux-thunk";
import {Provider} from "react-redux";
import * as reducers from "./reducers";
import {devTools} from "redux-devtools";
import {DevTools, DebugPanel, LogMonitor} from "redux-devtools/lib/react";

import ImportTool from "./components/ImportTool";


const createFinalStore = compose(
    applyMiddleware(thunk),
    devTools(),
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
        <DebugPanel top right bottom>
          <DevTools store={store}
                    monitor={LogMonitor} />
        </DebugPanel>
    </div>
, container);
