{

const binaryen = require('binaryen');

class MemorySegment {
	constructor(address) {
		this.address = address;
		this.data = [];

		// used for float conversions
		this.buffer = new ArrayBuffer(4);
		this.i32Array = new Uint32Array(this.buffer);
		this.f32Array = new Float32Array(this.buffer);
	}

	addByte(byte) {
		this.data.push(byte | 0);
	}

	addWord(word) {
		this.addByte(word & 0xFF);
		this.addByte((word >> 8) & 0xFF);
	}

	addDoubleWord(dword) {
		this.addWord(dword & 0xFFFF);
		this.addWord((dword >> 16) & 0xFFFF);
	}

	addFloat(float) {
		this.f32Array[0] = float;
		this.addDoubleWord(this.i32Array[0]);
	}
}

class Variable {
	constructor(type, name) {
		this.type = type;
		this.name = name;
	}
}

class Program {
	constructor() {
		this.defines = {};
		this.module = new binaryen.Module();
		this.functionTypes = {};
		this.nextId = 1;
		this.memoryPages = 0;
		this.memorySegments = [];
		this.startFunction = undefined;
		this.functions = {};
	}

	init() {
		let interruptFuncType = this.getFunctionSignature(binaryen.none, [ binaryen.i32 ]);
		this.module.addFunctionImport('interrupt', 'system', 'interrupt', interruptFuncType);

		this.module.addMemoryExport("0", "0");

		for (let i = 0; i < 32; ++i) {
			this.module.addGlobal('r'+i, binaryen.i32, 1, this.module.i32.const(0));
			this.module.addGlobal('s'+i, binaryen.f32, 1, this.module.f32.const(0));
		}

		this.org(0);
	}

	getTypeSymbol(type) {
		switch (type) {
			case binaryen.none: return 'v';
			case binaryen.i32:  return 'i';
			case binaryen.f32:  return 'f';
		}
	}

	getFunctionSignature(rettype, locals) {
		let signature = this.module.getFunctionTypeBySignature(rettype, locals);

		if (signature == 0) {
			let signatureName = 'f_' + this.getTypeSymbol(rettype) + '_';

			for (const localtype of locals) {
				signatureName += this.getTypeSymbol(localtype);
			}

			signature = this.module.addFunctionType(signatureName, rettype, locals);
		}

		return signature;
	}

	addFunction(name, rettype, locals, expr) {
		let block = this.module.block(null, expr);
		let ftype = this.getFunctionSignature(rettype, locals);
		let func = this.module.addFunction(name, ftype, [], block);
		this.functions[name] = func;
	}

	org(addr) {
		this.memorySegments.push(new MemorySegment(addr));
	}

	getMemorySegment() {
		return this.memorySegments[this.memorySegments.length - 1];
	}

	uid() {
		return `id${this.nextId++}`;
	}

	finalize() {
		let segments = [];

		for (let segment of this.memorySegments) {
			segments.push({ 
				offset: this.module.i32.const(segment.address),
				data: new Uint8Array(segment.data)
			});
		}

		this.module.setMemory(this.memoryPages, this.memoryPages, null, segments);

		if (this.startFunction !== undefined) {
			let func = this.functions[this.startFunction];

			if (func !== undefined) {
				this.module.setStart(func);
			}
		}
	}
}

let program = new Program();
program.init();

function loc() { return peg$computePosDetails(peg$currPos); }

}

Start
	= Program { program.finalize(); return program.module; }

Program
	= __ GlobalSection __ ((CodeSection / DataSection) __)*

/******** SECTIONS ********/

GlobalSection
	= GlobalStatement*

CodeSection
	= ".code" __ (CodeStatement __)*

DataSection
	= ".data" __ (DataStatement __)*

/******** STATEMENTS ********/

GlobalStatement
	= ".export" _ func:Identifier __ { program.module.addFunctionExport(func, func); }
	/ ".mempages" _ pages:NumericExpression __ { program.memoryPages = pages; }
	/ ".start" _ name:Identifier __ { program.startFunction = name; }
	/ ".define" _ name:Identifier __ "=" __ value:NumericExpression __ { program.defines[name] = value; }

CodeStatement
	= FunctionStatement

DataStatement
	= ".org" _ addr:Numeric __ { program.org(addr); }
	/ name:Identifier ":" __ {
		let segment = program.getMemorySegment();
		program.defines[name] = segment.address + segment.data.length;
	}
	/ ".db" _ values:NumericList __ { 
		let segment = program.getMemorySegment();
		values.forEach(segment.addByte.bind(segment));
	}
	/ ".dw" _ values:NumericList __ {
		let segment = program.getMemorySegment();
		values.forEach(segment.addWord.bind(segment));
	}
	/ ".dd" _ values:NumericList __ {
		let segment = program.getMemorySegment();
		values.forEach(segment.addDoubleWord.bind(segment));
	}
	/ ".df" _ values:NumericList __ {
		let segment = program.getMemorySegment();
		values.forEach(segment.addFloat.bind(segment));
	}

FunctionStatement
	= rettype:ReturnType _ name:Identifier "(" locals:FunctionArgumentList ")" __ "{" __ body:FunctionBodyStatement+ __ "}" { program.addFunction(name, rettype, locals, body); }

FunctionArgumentList
	= argtype:ArgumentType _ argname:Identifier __ "," __ list:FunctionArgumentList { return [new Variable(argtype, argname)].concat(list); }
	/ argtype:ArgumentType _ argname:Identifier __ { return [new Variable(argtype, argname)]; }
	/ __ { return []; }

FunctionBodyStatement
	= IntegerCodeStatement
	/ FloatCodeStatement
	/ label:Identifier "(" ")" __ { return program.module.call(label, [], binaryen.none); }
	/ "int" _ int:IntegerRightValue __ { return program.module.call_import('interrupt', [ int ], binaryen.none); }
	/ "nop" __ { return program.module.nop(); }
	/ "ret" __ { return program.module.return(); }
	/ "brk" __ { return program.module.unreachable(); }
	/ "if" __ cond:ComparisonExpression __ "then" __ trueBody:FunctionBodyStatement+ ("else" __ falseBody:FunctionBodyStatement+)? "end" __ { 
		return program.module.if(program.module.block(null, [cond], binaryen.auto), program.module.block(null, trueBody)); 
	}
	/ "do" __ body:FunctionBodyStatement+ __ "while" __ cond:ComparisonExpression "end" __ { 
		const id = program.uid();
		body.push(program.module.break(id, [cond]));
		return program.module.loop(id, program.module.block(null, body)); 
	}

ComparisonExpression
	= inst:IntegerComparisonInstruction _ left:IntegerRightValue _ right:IntegerRightValue __ { return program.module.i32[inst](left, right); }
	/ inst:FloatComparisonInstruction _ left:FloatRightValue _ right:FloatRightValue __ { return program.module.f32[inst](left, right); }

IntegerCodeStatement
	= inst:IntegerUnaryInstruction _ arg:IntegerRightValue __ { return program.module.i32[inst](arg); }
	/ inst:IntegerBinaryInstruction _ left:IntegerLeftValue _ right:IntegerRightValue __ { return program.module.setGlobal(left, program.module.i32[inst](program.module.getGlobal(left, binaryen.i32), right)); }
	/ inst:IntegerLoadInstruction _ left:IntegerLeftValue _ right:IntegerRightValue __ { return program.module.setGlobal(left, program.module.i32[inst](0, 0, right)); }
	/ inst:IntegerStoreInstruction _ left:IntegerRightValue _ right:IntegerRightValue __ { return program.module.i32[inst](0, 0, left, right); }
	/ "mov" _ left:IntegerLeftValue _ right:IntegerRightValue __ { return program.module.setGlobal(left, right); }
	/ "eqz" _ value:IntegerRightValue __ { return program.module.i32.eqz(value); }
	/ "inc" _ left:IntegerLeftValue __ { return program.module.setGlobal(left, program.module.i32.add(program.module.getGlobal(left, binaryen.i32), program.module.i32.const(1))); }
	/ "dec" _ left:IntegerLeftValue __ { return program.module.setGlobal(left, program.module.i32.sub(program.module.getGlobal(left, binaryen.i32), program.module.i32.const(1))); }

FloatCodeStatement
	= inst:FloatUnaryInstruction _ arg:FloatRightValue __ { return program.module.f32[inst](arg); }
	/ inst:FloatBinaryInstruction _ left:FloatLeftValue _ right:FloatRightValue __ { return program.module.setGlobal(left, program.module.f32[inst](program.module.getGlobal(left, binaryen.f32), right)); }
	/ inst:FloatLoadInstruction _ left:FloatLeftValue _ right:IntegerRightValue __ { return program.module.setGlobal(left, program.module.f32[inst](0, 0, right)); }
	/ inst:FloatStoreInstruction _ left:IntegerRightValue _ right:FloatRightValue __ { return program.module.f32[inst](0, 0, left, right); }
	/ "fmov" _ left:FloatLeftValue _ right:FloatRightValue __ { return program.module.setGlobal(left, right); }
	/ "finc" _ left:FloatLeftValue __ { return program.module.setGlobal(left, program.module.f32.add(program.module.getGlobal(left, binaryen.f32), program.module.f32.const(1))); }
	/ "fdec" _ left:FloatLeftValue __ { return program.module.setGlobal(left, program.module.f32.sub(program.module.getGlobal(left, binaryen.f32), program.module.f32.const(1))); }

/******** LVALUES & RVALUES ********/

IntegerLeftValue
	= IntegerRegister

IntegerRightValue
	= IntegerRegisterExpression
	/ IntegerExpression

FloatLeftValue
	= FloatRegister

FloatRightValue
	= FloatRegisterExpression
	/ FloatExpression

/******** INSTRUCTIONS ********/

IntegerBinaryInstruction
	= "add"
	/ "sub"
	/ "mul"
	/ "div_s"
	/ "div_u"
	/ "rem_s"
	/ "rem_u"
	/ "and"
	/ "or"
	/ "xor"
	/ "shl"
	/ "shl_u"
	/ "shl_s"
	/ "rotl"
	/ "rotr"

IntegerUnaryInstruction
	= "clz"
	/ "clz"

IntegerComparisonInstruction
	= "eq"
	/ "ne"
	/ "lt_s"
	/ "lt_u"
	/ "le_s"
	/ "le_u"
	/ "gt_s"
	/ "gt_u"
	/ "ge_s"
	/ "ge_u"

FloatUnaryInstruction
	= "neg"
	/ "abs"
	/ "ceil"
	/ "floor"
	/ "trunc"
	/ "nearest"
	/ "sqrt"

FloatBinaryInstruction
	= "fadd"
	/ "fsub"
	/ "fmul"
	/ "fdiv"
	/ "fmin"
	/ "fmax"

FloatComparisonInstruction
	= "feq"
	/ "fne"
	/ "flt"
	/ "fle"
	/ "fgt"
	/ "fge"

FloatLoadInstruction
	= "fload"

FloatStoreInstruction
	= "fstore"

IntegerLoadInstruction
	= "load8_s"
	/ "load8_u"
	/ "load16_s"
	/ "load16_u"
	/ "load"

IntegerStoreInstruction
	= "store8"
	/ "store8"
	/ "store16"
	/ "store16"
	/ "store"

/******** REGISTERS ********/

IntegerRegisterExpression
	= reg:IntegerRegister { return program.module.getGlobal(reg, binaryen.i32); }

FloatRegisterExpression
	= reg:FloatRegister { return program.module.getGlobal(reg, binaryen.f32); }

IntegerRegister
	= "r"i ("3"[0-1] / [1-2][0-9] / [0-9]) { return text(); }

FloatRegister
	= "s"i ("3"[0-1] / [1-2][0-9] / [0-9]) { return text(); }

/******** EXPRESSIONS ********/

IntegerExpression
	= value:NumericExpression { return program.module.i32.const(value | 0); }

FloatExpression
	= value:NumericExpression { return program.module.f32.const(value); }

NumericList
	= value:NumericExpression __ "," __ list:NumericList { return [value].concat(list); }
	/ value:NumericExpression { return [value]; }

NumericExpression
	= left:NumericSubExpression __ "+" __ right:NumericExpression { return left+right; }
	/ left:NumericSubExpression __ "-" __ right:NumericExpression { return left-right; }
	/ NumericSubExpression

NumericSubExpression
	= left:NumericPrimary __ "*" __ right:NumericSubExpression { return left*right; }
	/ left:NumericPrimary __ "/" __ right:NumericSubExpression { return left/right; }
	/ NumericPrimary

NumericPrimary
	= Numeric
	/ "(" value:NumericExpression ")" { return value; }

/******** NUMBERS ********/

Numeric "numeric"
	= HexLiteral
	/ BinaryLiteral
	/ OctalLiteral
	/ FloatLiteral
	/ IntegerLiteral
	/ DefineLiteral

DefineLiteral
	= name:Identifier {
		let value = program.defines[name];
		if (value === undefined) {
			error(`unknown define ${name}`);
		}
		return value;
	}

FloatLiteral
	= [+-]? [1-9] [0-9]* "." [0-9]+ { return parseFloat(text()); }
	/ [+-]? "0." [0-9]+ { return parseFloat(text()); }

IntegerLiteral
	= "0" { return 0; }
	/ [+-]? [1-9] [0-9]* { return parseInt(text()); }

HexLiteral
	= "0x"i digits:$(([0-9a-f]i)+) { return parseInt(digits, 16); }

BinaryLiteral
	= "0b"i digits:$([01]+) { return parseInt(digits, 2); }

OctalLiteral
	= "0" digits:$([0-7]+) { return parseInt(digits, 8); }

/******** TYPES ********/

ArgumentType
	= IntegerType
	/ FloatType

ReturnType
	= VoidType
	/ IntegerType
	/ FloatType

VoidType
	= "void" { return binaryen.void; }

IntegerType
	= "i32" { return binaryen.i32; }

FloatType
	= "f32" { return binaryen.f32; }

/******** IDENTIFIERS ********/

Identifier
	= name:[_a-zA-Z]+ { return name.join(''); }

/******** WHITE SPACE AND COMMENTS ********/

WhiteSpace "whitespace"
	= [ \t]

LineTerminator
	= "\n"
	/ "\r"
	/ "\r\n"

Comment
	= "#" [^\n\r]*

__
	= (WhiteSpace / LineTerminator / Comment)* { }

_
	= (WhiteSpace)+ { }

