
import React from "react";
import PureComponent from "./PureComponent";
import R from "ramda";
import Icon from "./Icon";

const STATUS_ICONS = {
    ok: {icon: "ok", className: "success"},
    error: {icon: "attention", className: "error"},
    waiting: {icon: "info"},
    working: {icon: "cog", className: "spin"},
};

export default class StatusIcon extends PureComponent {

    isError() {
        return STATUS_ICONS[this.props.status].className === "error";
    }

    render() {
        const statusProps = STATUS_ICONS[this.props.status];
        return (
            <Icon
                title={this.props.status}
                {...statusProps}
                {...R.omit(["status"], this.props)}
            />
        );
    }
}


StatusIcon.propTypes = {
    status: React.PropTypes.oneOf(R.keys(STATUS_ICONS)).isRequired,
};
