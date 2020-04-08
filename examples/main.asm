# simple assembly file with a kitchen sink of 
# code covering most use cases

.export init
.export vsync
.start init
.mempages 10

# interrupt values
.define VSYNC = 0x13 # video sync interrupt

.define VIDMEM = 0x0C00 # start of video memory map
.define WIDTH = 256
.define HEIGHT = 256

.data

sprite:
.db 0xFF, 0x0F, 0xF0, 0x3
.dw 12345
.dd 1232423
.df 34.2, 15.6

.code

void clear()
{
	mov r0 VIDMEM
	mov r1 WIDTH
	mul r1 HEIGHT
	add r1 r0
	do
		store r0 0
		add r0 1
	while 
		lt_u r0 r1 
	end
	ret
}

void draw()
{
	mov r1 sprite
	mov r3 VIDMEM
	add r3 r10
	do
		load8_u r0 r1
		if ne r0 0 then
			store8 r3 r0
			inc r3
		end
		inc r1
	while
		lt_u r1 sprite+4
	end
	ret
}

void vsync()
{
	clear()
	draw()
	inc r10
	and r10 0xFF
	ret
}

void init()
{
	mov r10 0
	draw()
	clear()
	ret
}
