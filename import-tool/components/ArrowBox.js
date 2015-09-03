
import React from "react";

// Styles Mostly from Bootstrap
const BoxStyle = {
    position: "absolute",
    padding: "0 5px",
};

const BoxInnerStyle = {
    padding: "20px",
    color: "#fff",
    textAlign: "center",
    borderRadius: 3,
    border: "5px solid black",
    backgroundColor: "white",
};

const ArrowStyle = {
    position: "absolute",
    width: 0, height: 0,
    borderRightColor: "transparent",
    borderLeftColor: "transparent",
    borderTopColor: "transparent",
    borderBottomColor: "transparent",
    borderStyle: "solid",
};

const PlacementStyles = {
    left: {
        box: {marginLeft: -3, padding: "0 5px"},
        arrow: {
            right: 0, marginTop: -5, borderWidth: "5px 0 5px 5px", borderLeftColor: "#000",
        },
    },
    right: {
        box: {marginRight: 3, padding: "0 5px"},
        arrow: {left: 0, marginTop: -5, borderWidth: "5px 5px 5px 0", borderRightColor: "#000"},
    },
    top: {
        box: {marginTop: -3, padding: "5px 0"},
        arrow: {bottom: 0, marginLeft: -5, borderWidth: "5px 5px 0", borderTopColor: "#000"},
    },
    bottom: {
        box: {marginBottom: 3, padding: "5px 0"},
        arrow: {top: 0, marginLeft: -5, borderWidth: "0 5px 5px", borderBottomColor: "#000"},
    },
};

export default class ArrowBox {
    render(){
        let placementStyle = PlacementStyles[this.props.placement];

        let {style,
            arrowOffsetLeft: left = placementStyle.arrow.left,
            arrowOffsetTop: top = placementStyle.arrow.top,
            ...props} = this.props;

        return (
            <div style={{...BoxStyle, ...placementStyle.box, ...style}}>
                <div style={{...ArrowStyle, ...placementStyle.arrow, left, top}}/>
                <div style={BoxInnerStyle}>
                    {props.children}
                </div>
            </div>
        );
    }
}


ArrowBox.propTypes = {
    placement: React.PropTypes.string,
    style: React.PropTypes.object,
    arrowOffsetLeft: React.PropTypes.string,
    arrowOffsetTop: React.PropTypes.string,
};
