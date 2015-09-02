
import React from "react";
import PureComponent from "react-pure-render/component";
import {connect} from "react-redux";
import R from "ramda";

import ToolTip from "./ToolTip";
import {Overlay} from "react-overlays";
import COLUMN_TYPES from "../column_types";
import {addColumn} from "../actions";

class AddColumn extends PureComponent {

    constructor(props) {
        super(props);
        this.state = {
            showMenu: false,
        };
    }

    addColumn(e) {
        if (e && e.target.value !== "nil") {
            this.props.addColumn(e.target.value);
            this.hideMenu();
        }
    }

    showMenu() {
        this.setState({showMenu: true});
    }

    hideMenu() {
        this.setState({showMenu: false});
    }

    render() {
        return (
            <div className="AddColumn">

                <button ref="target" onClick={this.showMenu.bind(this)}>+</button>

                <Overlay
                    show={this.state.showMenu}
                    onHide={this.hideMenu.bind(this)}
                    rootClose
                    placement="bottom"
                    target={() => {
                        var el = React.findDOMNode(this.refs.target);
                        // var el = document.getElementById("boo");
                        return el;
                    }}
                >
                    <ToolTip>
                        <select onChange={this.addColumn.bind(this)}>
                            <option key="nil" value="nil" >Select...</option>
                            {R.toPairs(COLUMN_TYPES).map(([columnType, column]) => {
                                return <option key={columnType} value={columnType}>{column.name}</option>;
                            })}
                        </select>
                    </ToolTip>
                </Overlay>
            </div>
        );
    }

}

AddColumn.propTypes = {
    addColumn: React.PropTypes.func.isRequired,
};

export default connect(null, {addColumn})(AddColumn);

