
import React from "react";
import PureComponent from "react-pure-render/component";
import R from "ramda";
import classNames from "classnames";

export default class Fa extends PureComponent {
    render() {
        var otherProps = R.omit(["className", "icon"], this.props);
        var className = classNames("Fa", "fa", "fa-" + this.props.icon, this.props.className);
        return <i className={className} {...otherProps}></i>;
    }
}

Fa.propTypes = {
    icon: React.PropTypes.string.isRequired,
    className: React.PropTypes.string,
};
