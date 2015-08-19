
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
import {getCellValue} from "./utils";

import ColumnTypeSelector from "./ColumnTypeSelector";
import AddColumn from "./AddColumn";


const createFinalStore = compose(
    applyMiddleware(thunk),
    devTools(),
    createStore
);

const combinedReducers = combineReducers(reducers);
const store = createFinalStore(combinedReducers);

const demoData = `
Bob, Brown, bob@examle.com
Alice, Smith, alice@example.com
Charlie, Chaplin, charlie@exampl.com
`;




class Cell extends React.Component {

    constructor(props) {
        super(props);
        this.state = {
            customValue: getCellValue(props.value),
            editing: false,
        };
    }

    dispatchCustomValue(e) {
        if (e.key !== "Enter") return;
        if (this.state.customValue !== getCellValue(this.props.value)) {
            this.props.dispatch(setCustomValue(this.props.rowIndex, this.props.columnIndex, this.state.customValue));
        }
        this.setState({editing: false});
    }

    changeCustomValue(e) {
        this.setState({customValue: e.target.value});
    }

    startEdit(e) {
        if (e) e.preventDefault();
        this.setState({editing: true});
    }

    render() {
        return (
            <div>
                <pre>
                    {JSON.stringify(this.props.value)}
                </pre>

                {!this.state.editing &&
                    <a href="#" onClick={this.startEdit.bind(this)}>m</a>}

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

        // var columnCount = R.keys(R.path(["importData", "rows", 0], this.props)).length;
        var {columns, rows} = this.props.importData;

        console.log("rendering rows", this.props.importData.rows);
        return (
            <div>
                <textarea ref="textarea" defaultValue={demoData} />

                <button onClick={this.onParseCSV.bind(this)}>lue2</button>
                <AddColumn />

                <pre>
                    {JSON.stringify(this.props, null, "  ")}
                </pre>

                {rows.length > 0 &&
                <table>
                    <thead>
                        <tr>
                            {columns.map((columnType, columnIndex) => {
                                return (
                                    <th>
                                        {columnType.attribute}
                                        <ColumnTypeSelector
                                            value={columnType.attribute}
                                            onChange={e => this.changeColumnType(columnIndex, e.target.value)} />
                                    </th>
                                );
                            })}
                        </tr>
                    </thead>
                    <tbody>
                        {rows.map((row, rowIndex) => {
                            return (
                                <tr>
                                    {columns.map((columnType, columnIndex) => {
                                        return (
                                            <td>
                                                <Cell value={row[columnIndex]} rowIndex={rowIndex} columnIndex={columnIndex} />
                                            </td>
                                        );
                                    })}
                                </tr>
                            );

                        })}

                    </tbody>

                </table>}

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
