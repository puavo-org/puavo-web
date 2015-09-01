/*eslint comma-dangle:0*/
var webpack = require("webpack");

module.exports = {
    entry: "./import-tool/index.js",
    output: {
        path: __dirname + "/public",
        filename: "import_tool.js"
    },
    devtool: "source-map",
    module: {
        loaders: [
            {test: /\.jsx?$/, exclude: /node_modules/, loader: "transform?envify"},
            {test: /\.jsx?$/, exclude: /node_modules/, loader: "babel-loader"}
        ]
    },
    plugins: [
        new webpack.ExtendedAPIPlugin()
    ]
};
