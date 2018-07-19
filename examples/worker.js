
const WIDTH = 256;
const HEIGHT = 256;

class VirtualMachine {
	constructor() {
		this.backBuffer = new ArrayBuffer(WIDTH * HEIGHT * 4);
		this.memory = null;
		this.instance = null;
	}

	interrupt(value) {
		switch (value) {
			case 0x03:
				close();
				break;
		}
	}

	async load() {
		let importObject = { system: { interrupt: this.interrupt.bind(this) } };
		let fetchResponse = await fetch('main.wasm');
		let bytes = await fetchResponse.arrayBuffer();
		let mod = await WebAssembly.compile(bytes);
		this.instance = await WebAssembly.instantiate(mod, importObject);
		this.memory = this.instance.exports[0];
		this.instance.exports.init();
		this.vsync();
	}

	vsync() {
		this.instance.exports.vsync();

		let src = new Uint8ClampedArray(this.memory.buffer, 0x0C00, WIDTH*HEIGHT);
		let dst = new Uint32Array(this.backBuffer);

		for (let y = 0; y < HEIGHT; ++y) {
			for (let x = 0; x < WIDTH; ++x) {
				let idx = y*WIDTH+x;
				let pixel = src[idx];
				dst[idx] =(255 << 24) |
					((((pixel >> 5) & 7) * 32) << 16) |
					((((pixel >> 2) & 7) * 32) << 8) |
					((pixel & 3) * 64);
			}
		}

		postMessage(this.backBuffer);
		setTimeout(this.vsync.bind(this), 16);
	}
}

let vm = new VirtualMachine();
vm.load();

