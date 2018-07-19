const wasm = require('..');
const fs = require("fs");
const path = require("path");

let files = [];
let options = { optimize: false, debug: false, validate: false };

if (process.argv.length > 2) {
	for (let i = 2; i < process.argv.length; ++i) {
		let arg = process.argv[i];

		if (arg[0] == '-') {
			switch (arg) {
				case '-O':
					options.optimize = true;
					break;

				case '-g':
					options.debug = true;
					break;

				case '-W':
					options.validate = true;
					break;

				default:
					console.error(`error: unrecognized command line option '${arg}'`);
					break;
			}
		}
		else {
			try {
				let file = fs.readFileSync(arg, "utf8");
				files.push({name: arg, data:file});
			}
			catch (e) {
				console.error(`error: ${arg}: No such file or directory`);
			}
		}
	}
}

if (files.length == 0) {
	console.error("fatal error: no input files");
	process.exit(-1);
}

for (let file of files) {
	options.filename = file.name;
	let parsedModule = wasm.parse(file.data, options);

	if (options.validate) {
		console.assert(parsedModule.validate());
	}

	if (options.optimize) {
		parsedModule.optimize();
	}

	let binary = parsedModule.emitBinary();
	let ext = path.extname(path.basename(file.name));
	let outfile = file.name.slice(0, file.name.length - ext.length) + '.wasm';

	try {
		fs.writeFileSync(outfile, binary);
	}
	catch (e) {
		console.error(`error: failed to write ${outfile}`);
	}
}

