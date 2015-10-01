
import PureComponent from "./PureComponent";
import React from "react";

import {preventDefault} from "../utils";

import Modal from "./Modal";
import Icon from "./Icon";

export default class ErrorModalButton extends PureComponent {


    constructor(props) {
        super(props);
        this.state = {show: false};
    }

    render() {
        return (
            <span>
                <span>
                    <a title={this.props.tooltip} href="#" onClick={preventDefault(_ => this.setState({show: true}))}>
                        <Icon icon="exclamation-triangle" className="error" />
                    </a>
                    {" "}
                </span>

                {this.state.show &&
                <Modal show onHide={e => this.setState({show: false})}>
                    <div>
                        <h1>Error</h1>
                        {this.props.children}
                    </div>
                </Modal>}
            </span>
        );
    }

}

ErrorModalButton.propTypes = {
    tooltip: React.PropTypes.node.isRequired,
    children: React.PropTypes.node,
};
