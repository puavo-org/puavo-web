
import React from "react";
import PureComponent from "react-pure-render/component";

import {preventDefault} from "../utils";

export default class ConfirmationButton extends PureComponent {
    constructor(props) {
        super(props);
        this.state = {clickedOnce: false};
    }

    render() {

        if (this.state.clickedOnce) {
            return <button {...this.props} onClick={this.props.onClick}>Really?</button>;
        }

        return (
            <button
                {...this.props}
                onClick={preventDefault(_ => this.setState({clickedOnce: true}))}
            >{this.props.children}</button>
        );
    }
}

ConfirmationButton.propTypes = {
    children: React.PropTypes.node,
    onClick: React.PropTypes.func.isRequired,
};
