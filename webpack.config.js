/*eslint comma-dangle:0*/
var webpack = require("webpack");

var sourceMap = "cheap-module-eval-source-map";

if (process.env.NODE_ENV === "production") {
    sourceMap = "source-map";
}

module.exports = {
    entry: "./import-tool/index.js",
    output: {
        path: __dirname + "/public",
        filename: "import_tool.js"
    },
    devtool: sourceMap,
    module: {
        loaders: [
            {test: /\.jsx?$/, exclude: /node_modules/, loader: "babel-loader"}
        ]
    },
    plugins: [
        new webpack.ExtendedAPIPlugin(),
        new webpack.DefinePlugin({
            "process.env.NODE_ENV": JSON.stringify(process.env.NODE_ENV)
        })
    ]
};
