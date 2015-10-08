/*eslint comma-dangle:0*/

// Polyfill Promise global for style loaders
global.Promise = require("bluebird");
var webpack = require("webpack");


var config = {
    entry: "./import-tool/index.js",
    output: {
        path: __dirname + "/public",
        filename: "import_tool.js",
        publicPath: "/"
    },
    devtool: "cheap-module-eval-source-map",
    module: {
        loaders: [
            {test: /\.css$/, loaders: ["style", "css?sourceMap"]},
            {
                test: /\.jsx?$/,
                exclude: /node_modules/,
                loader: "babel",
            }
        ]
    },
    plugins: [
        new webpack.ExtendedAPIPlugin(),
        new webpack.DefinePlugin({
            "process.env.NODE_ENV": JSON.stringify(process.env.NODE_ENV)
        })
    ]
};

if (process.env.NODE_ENV === "production") {
    config.devtool = "source-map";
    delete config.output.publicPath;
}

module.exports = config;
