
import R from "ramda";
import React from "react";
import {combineReducers, createStore, applyMiddleware, compose} from "redux";
import thunk from "redux-thunk";
import {Provider} from "react-redux";
import * as reducers from "./reducers";
import {connect} from "react-redux";
import {devTools, persistState} from "redux-devtools";
import {DevTools, DebugPanel, LogMonitor} from "redux-devtools/lib/react";

import {setImportData, startImport, changeColumnType, setCustomValue} from "./actions";

import {Sortable,  Column} from "./Sortable";
import ColumnTypeSelector from "./ColumnTypeSelector";
import AddColumn from "./AddColumn";


const createFinalStore = compose(
    applyMiddleware(thunk),
    devTools(),
    createStore
);

const combinedReducers = combineReducers(reducers);
const store = createFinalStore(combinedReducers);

// const store = createStoreWithMiddleware((state, action) => {
//     state = combinedReducers(state, action);
//     console.log("action", action);
//     return state;
// });

const defaultSortFirst = R.ifElse(R.equals(0), R.always({defaultSort: true}), R.always({}));

const demoData = `
Bob, Brown, bob@examle.com
Alice, Smith, alice@example.com
Charlie, Chaplin, charlie@exampl.com
`;

const getOriginalValue = R.path(["value", "originalValue"]);

class Cell extends React.Component {

    constructor(props) {
        super(props);
        this.state = {
            customValue: getOriginalValue(props),
            editing: false,
        };
    }

    dispatchCustomValue(e) {
        if (e.key !== "Enter") return;
        if (this.state.customValue !== getOriginalValue(this.props)) {
            this.props.dispatch(setCustomValue(this.props.rowIndex, this.props.columnIndex, this.state.customValue));
        }
        this.setState({editing: false});
    }

    changeCustomValue(e) {
        this.setState({customValue: e.target.value});
    }

    render() {
        return (
            <div>
                <pre>
                    {JSON.stringify(this.props.value)}
                </pre>

                {!this.state.editing &&
                    <a href="#" onClick={(e) => this.setState({editing: true})}>m</a>}

                {this.state.editing &&
                <input type="text"
                    value={this.state.customValue}
                    onChange={this.changeCustomValue.bind(this)}
                    onKeyUp={this.dispatchCustomValue.bind(this)} />
                }

            </div>
        );
    }
}

Cell.propTypes = {
    columnIndex: React.PropTypes.number.isRequired,
    rowIndex: React.PropTypes.number.isRequired,
    dispatch: React.PropTypes.func.isRequired,
    value: React.PropTypes.object.isRequired,
};

Cell = connect()(Cell);

class Hello extends React.Component {


    onParseCSV(e) {
        var el = React.findDOMNode(this.refs.textarea);
        this.props.dispatch(setImportData(el.value));
    }

    startImport() {
        this.props.dispatch(startImport(this.props.importData));
    }

    changeColumnType(columnIndex, typeId) {
        this.props.dispatch(changeColumnType(columnIndex, typeId));
    }

    render() {
        console.log("props", this.props);

        var columnCount = R.path(["importData", "rows", 0, "length"], this.props) || 0;

        return (
            <div>
                <textarea ref="textarea" defaultValue={demoData} />

                <button onClick={this.onParseCSV.bind(this)}>lue2</button>
                <AddColumn />

                {columnCount > 0 &&
                <Sortable rows={this.props.importData.rows}>
                    {this.props.importData.columns.map((columnType, columnIndex) => {
                        return (
                            <Column {...defaultSortFirst(columnIndex)}
                                render={(row, rowIndex) => <Cell value={row[columnIndex]} rowIndex={rowIndex} columnIndex={columnIndex} />} >
                                {columnType.attribute}
                                <ColumnTypeSelector
                                    value={columnType.attribute}
                                    onChange={e => this.changeColumnType(columnIndex, e.target.value)} />
                            </Column>
                        );
                    })}


                </Sortable>}

                <button onClick={this.startImport.bind(this)}>import</button>
            </div>
        );
    }
}

Hello.propTypes = {
    dispatch: React.PropTypes.func.isRequired,
    importData: React.PropTypes.object.isRequired,
};

function select(state) {
    return state;
}

var App = connect(select)(Hello);

var container = document.getElementById("import-tool");
container.innerHTML = "";
React.render(
    <div>
        <Provider store={store}>
            {() => <App />}
        </Provider>
        <DebugPanel top right bottom>
          <DevTools store={store}
                    monitor={LogMonitor} />
        </DebugPanel>
    </div>
, container);
