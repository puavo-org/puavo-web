
import R from "ramda";
import React from "react";
import {combineReducers, createStore, applyMiddleware} from "redux";
import thunk from "redux-thunk";
import {Provider} from "react-redux";
import * as reducers from "./reducers";
import {connect} from "react-redux";
import {setImportData, startImport, changeColumnType, setCustomValue} from "./actions";

import {Sortable,  Column} from "./Sortable";
import ColumnTypeSelector from "./ColumnTypeSelector";


const createStoreWithMiddleware = applyMiddleware(thunk)(createStore);
const combinedReducers = combineReducers(reducers);

const store = createStoreWithMiddleware((state, action) => {
    state = combinedReducers(state, action);
    console.log("action", action);
    return state;
});

const defaultSortFirst = R.ifElse(R.equals(0), R.always({defaultSort: true}), R.always({}));

const demoData = `
Bob, Brown, bob@examle.com
Alice, Smith, alice@example.com
Charlie, Chaplin, charlie@exampl.com
`;

class Cell extends React.Component {

    constructor(props) {
        super(props);
        this.state = {
            customValue: props.value.originalValue,
            editing: false,
        };
    }

    dispatchCustomValue(e) {
        if (e.key !== "Enter") return;
        if (this.state.customValue !== this.props.value.originalValue) {
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
React.render (
    <Provider store={store}>
        {() => <App />}
    </Provider>, container);
