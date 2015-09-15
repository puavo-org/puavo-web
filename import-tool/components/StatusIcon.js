
import React from "react";
import PureComponent from "react-pure-render/component";
import R from "ramda";
import Fa from "./Fa";

const STATUS_ICONS = {
    ok: {icon: "thumbs-up", className: "success"},
    error: {icon: "exclamation-triangle", className: "error"},
    waiting: {icon: "pause"},
    working: {icon: "cog", className: "spin"},
};

export default class StatusIcon extends PureComponent {

    isError() {
        return STATUS_ICONS[this.props.status].className === "error";
    }

    render() {
        const statusProps = STATUS_ICONS[this.props.status];
        return (
            <Fa
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
