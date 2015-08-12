
import R from "ramda";
import React from "react";
import {combineReducers, createStore, applyMiddleware} from "redux";
import thunk from "redux-thunk";
import {Provider} from "react-redux";
import * as reducers from "./reducers";
import {connect} from "react-redux";
import {setImportData, startImport, changeColumnType} from "./actions";

import {Sortable,  Column} from "./Sortable";
import ColumnTypeSelector from "./ColumnTypeSelector";


const createStoreWithMiddleware = applyMiddleware(thunk)(createStore);
const store = createStoreWithMiddleware(combineReducers(reducers));

const defaultSortFirst = R.ifElse(R.equals(0), R.always({defaultSort: true}), R.always({}));

const demoData = `
foo,bar, foo
lol, omg, lol
`;

class Cell extends React.Component {

    setCustomValue(e) {
        if (e.key === "Enter" && e.target.value.trim()) {
            this.props.dispatch(setCustomValue(this.props.rowIndex, this.props.columnIndex, e.target.value));
        }
    }

    render() {
        console.log("cell dis", this.props.dispatch);
        return (
            <pre>
                {JSON.stringify(this.props.value)}
                <input type="text" onKeyUp={this.setCustomValue.bind(this)} />
            </pre>
        );
    }
}

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

        var columnCount = R.path(["importData", 0, "length"], this.props) || 0;
        var {rowStatus} = this.props;

        return (
            <div>
                <textarea ref="textarea" value={demoData} />

                <button onClick={this.onParseCSV.bind(this)}>lue2</button>

                {columnCount > 0 &&
                <Sortable rows={this.props.importData}>
                    {this.props.columnTypes.map((columnType, columnIndex) => {
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

                    <Column render={(row, rowId) => R.path([rowId, "status"], rowStatus) || "waiting"}>
                        Status
                    </Column>

                </Sortable>}

                <button onClick={this.startImport.bind(this)}>import</button>
            </div>
        );
    }
}

Hello.propTypes = {
    dispatch: React.PropTypes.func.isRequired,
    importData: React.PropTypes.array.isRequired,
    columnTypes: React.PropTypes.array.isRequired,
    rowStatus: React.PropTypes.object.isRequired,
};

function select(state) {
    return state;
}

var App = connect(select)(Hello);

var container = document.getElementById("import-tool");
container.innerHTML = "";
React.render (
    <Provider store={store}>
        {() => <App />}
    </Provider>, container);
