module.exports = {
    entry: "./import-tool/index.js",
    output: {
        path: __dirname + "/public",
        filename: "import_tool.js"
    },
    devtool: 'source-map',
    module: {
        loaders: [
            {test: /\.jsx?$/, exclude: /node_modules/, loader: 'babel-loader'}
        ]
    }
};
