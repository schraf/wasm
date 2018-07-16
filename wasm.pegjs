{

const PAGESIZE = 65536;
const MEGABYTE = 1024 * 1024;
const MEMSIZE  = 8 * MEGABYTE;
const PAGES    = (MEMSIZE / PAGESIZE) | 0;

const binaryen = require('binaryen');

let defines = {};
let module = new binaryen.Module();
let ftype = module.addFunctionType('void', binaryen.none, []);
let itype = module.addFunctionType('itype', binaryen.none, [ binaryen.i32 ]);
let nextId = 0;

module.addFunctionImport('interrupt', 'system', 'interrupt', itype);
module.setMemory(PAGES, PAGES);
module.addMemoryExport("0", "0");

for (let i = 0; i < 32; ++i) {
	module.addGlobal('r'+i, binaryen.i32, 1, module.i32.const(0));
}

function uid() { return `id${nextId++}`; }

}

Start
	= __ ((Block / Directive) __)* { return module; }

Directive
	= ".export" _ func:Identifier __ { module.addFunctionExport(func, func); }
	/ ".define" _ name:Identifier _ "=" _ value:NumericLiteral __ { defines[name] = value; }

Block
	= label:Identifier ":" __ body:Instruction+ { 
		let block = module.block(null, body);
		module.addFunction(label, ftype, [], block);
	}

Instruction
	= op:Operation _ dst:lvalue _ src:rvalue __ { return module.setGlobal(dst, module.i32[op](module.getGlobal(dst, binaryen.i32), src)); }
	/ op:LoadOperation _ dst:lvalue _ src:rvalue __ { return module.setGlobal(dst, module.i32[op](0, 0, src)); }
	/ op:StoreOperation _ dst:rvalue _ src:rvalue __ { return module.i32[op](0, 0, dst, src); }
	/ op:Comparison _ left:rvalue _ right:rvalue __ { return module.i32[op](left, right); }
	/ "mov" _ dst:lvalue _ src:rvalue __ { return module.setGlobal(dst, src); }
	/ "call" _ label:Identifier __ { return module.call(label, [], binaryen.none); }
	/ "int" _ int:rvalue __ { return module.call_import('interrupt', [ int ], binaryen.none); }
	/ "eqz" _ src:rvalue __ { return module.i32.eqz(src); }
	/ "nop" __ { return module.nop(); }
	/ "ret" __ { return module.return(); }
	/ "brk" __ { return module.unreachable(); }
	/ "if" __ cond:Instruction+ __ "then" __ body:Instruction+ ("else" __ body2:Instruction+)? "end" __ { return module.if(module.block(null, cond, binaryen.i32), module.block(null, body)); }
	/ "do" __ body:Instruction+ __ "while" __ cond:Instruction+ "end" __ { 
		const id = uid();
		body.push(module.break(id, cond));
		return module.loop(id, module.block(null, body)); 
	}

Operation
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

Comparison
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

LoadOperation
	= "load"
	/ "load8_s"
	/ "load8_u"
	/ "load16_s"
	/ "load16_u"

StoreOperation
	= "store"
	/ "store8_s"
	/ "store8_u"
	/ "store16_s"
	/ "store16_u"

lvalue
	= Register

rvalue
	= RegisterExpression
	/ NumericExpression
	/ DefineExpression

RegisterExpression
	= reg:Register { return module.getGlobal(reg, binaryen.i32); }

NumericExpression
	= value:NumericLiteral { return module.i32.const(value); }

DefineExpression
	= name:Identifier { 
		let value = defines[name];
		if (value === undefined) {
			error(`unknown define ${name}`); 
		}
		return module.i32.const(value);
	}

WhiteSpace "whitespace"
	= [ \t]

LineTerminator
	= "\n"
	/ "\r"
	/ "\r\n"

Identifier
	= name:[_a-zA-Z]+ { return name.join(''); }

Register
	= "r"i ("3"[0-1] / [1-2][0-9] / [0-9]) { return text(); }

NumericLiteral "number"
	= HexLiteral
	/ BinaryLiteral
	/ OctalLiteral
	/ DecimalLiteral

DecimalLiteral
	= "0" { return 0; }
	/ [+-]? [1-9] [0-9]* { return parseInt(text()); }

HexLiteral
	= "0x"i digits:$(([0-9a-f]i)+) { return parseInt(digits, 16); }

BinaryLiteral
	= "0b"i digits:$([01]+) { return parseInt(digits, 2); }

OctalLiteral
	= "0" digits:$([0-7]+) { return parseInt(digits, 8); }

__
	= (WhiteSpace / LineTerminator)* { }

_
	= (WhiteSpace)+ { }

