
import React from "react";
import PureComponent from "./PureComponent";
import classNames from "classnames";

// See app/assets/stylesheets/font/fontello-puavo/css/puavo-icons-codes.css
const ICONS = [
    "plus",
    "minus",
    "home",
    "check",
    "cog",
    "attention",
    "cog-alt",
    "pencil",
    "ok",
    "cancel",
    "eye",
    "tag",
    "tags",
    "location",
    "trash",
    "login",
    "logout",
    "inbox",
    "link-ext",
    "hdd",
    "docs",
    "exchange",
    "info",
    "lock-open-alt",
    "collapse",
    "picture",
    "videocam",
    "user",
    "users",
    "doc",
    "phone",
    "download",
    "camera",
    "search",
    "key",
    "lock",
];

export default class Icon extends PureComponent {
    render() {
        let {className, icon, ...otherProps} = this.props;
        className = classNames("Icon", "icon-" + icon, className);
        return <i className={className} {...otherProps}></i>;
    }
}

Icon.propTypes = {
    icon: React.PropTypes.oneOf(ICONS).isRequired,
    className: React.PropTypes.string,
};
