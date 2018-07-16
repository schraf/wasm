const fs = require("fs");
const path = require("path");

let filename = path.join(__dirname, 'main.wasm');
let data = fs.readFileSync(filename);
let importObject = {
	system: {
		interrupt: function (value) {
			console.log('INT', value);
		}
	}
};

WebAssembly.instantiate(data, importObject).then(result => {
	result.instance.exports.main();
});
