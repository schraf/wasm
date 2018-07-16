.export main
.define x = 0x1234

main:
	store x 1
	mov r0 0
	do 
		add r0 1
	while lt_s r0 100 end
	store x r0
	call foo
	int r8
	mov r0 r8
	int r0
	nop
	nop
	ret

foo:
	load r8 x
	if eqz r8 then
		int 5
		add r8 10
	end
	add r8 1
	store x r8
	ret
