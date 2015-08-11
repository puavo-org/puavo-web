
import R from "ramda";
import React from "react";
import {combineReducers, createStore} from "redux";
import {Provider} from "react-redux";
import * as reducers from "./reducers";
import {connect} from "react-redux";
import {setImportData} from "./actions";

import {Sortable,  Column} from "./Sortable";


var store = createStore(combineReducers(reducers));

const defaultSortFirst = R.ifElse(R.equals(0), R.always({defaultSort: true}), R.always({}));

class Hello extends React.Component {


    onParseCSV(e) {
        var el = React.findDOMNode(this.refs.textarea);
        this.props.dispatch(setImportData(el.value));
    }

    render() {
        console.log("props", this.props);

        var columnCount = R.path(["importData", 0, "length"], this.props) || 0;

        return (
            <div>
                <textarea ref="textarea">
                </textarea>

                <button onClick={this.onParseCSV.bind(this)}>lue</button>

                {columnCount > 0 &&
                <Sortable rows={this.props.importData}>
                    {this.props.columnTypes.map((columnType, i) => {
                        return (
                            <Column {...defaultSortFirst(i)} render={row => row[i]}>
                                {columnType.attribute}
                            </Column>
                        );
                    })}
                </Sortable>}
            </div>
        );
    }
}

Hello.propTypes = {
    dispatch: React.PropTypes.func.isRequired,
    importData: React.PropTypes.array.isRequired,
    columnTypes: React.PropTypes.array.isRequired,
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
