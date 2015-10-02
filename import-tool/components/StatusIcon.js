
import React from "react";
import PureComponent from "./PureComponent";
import Icon from "./Icon";

const STATUS_ICONS = {
    ok: {icon: "ok", className: "success"},
    error: {icon: "attention", className: "error"},
    waiting: {icon: "info"},
    working: {icon: "cog", className: "spin"},
};

export default class StatusIcon extends PureComponent {
    render() {
        const {status, ...otherProps} = this.props;
        const statusProps = STATUS_ICONS[status];
        return <Icon title={status} {...statusProps} {...otherProps} />;
    }
}


StatusIcon.propTypes = {
    status: React.PropTypes.oneOf(Object.keys(STATUS_ICONS)).isRequired,
};
