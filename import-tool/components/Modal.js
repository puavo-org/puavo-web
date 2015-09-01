

import R from "ramda";
import React from "react";
import Modal from "react-overlays/lib/Modal";
import PureComponent from "react-pure-render/component";

const modalStyle = {
    position: "fixed",
    zIndex: 1040,
    top: 0, bottom: 0, left: 0, right: 0,
};

const backdropStyle = {
    ...modalStyle,
    zIndex: "auto",
    backgroundColor: "#000",
    opacity: 0.5,
};

const dialogStyle = function() {
    // we use some psuedo random coords so modals
    // don't sit right on top of each other.
    let top = 50;
    let left = 50;
    return {
        position: "absolute",
        overflow: "auto",
        maxWidth: "90%",
        maxHeight: "90%",
        top: top + "%", left: left + "%",
        transform: `translate(-${top}%, -${left}%)`,
        border: "1px solid #e5e5e5",
        backgroundColor: "white",
        boxShadow: "0 5px 15px rgba(0,0,0,.5)",
        padding: 20,
    };
};


export default class MyModal extends PureComponent {
    render() {
        return (
            <Modal style={modalStyle} backdropStyle={backdropStyle} {...R.omit(["children"], this.props)} >
                <div style={dialogStyle()}>
                    {this.props.children}
                </div>
            </Modal>
        );
    }
}

MyModal.propTypes = {
    children: React.PropTypes.node,
};
