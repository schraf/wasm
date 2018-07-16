# simple assembly file with a kitchen sink of 
# code covering most use cases

.export main # expose function to web assembly
.define x = 0x1234 # memory address to store data in

main:
	store x 1
	mov r0 0
	do 
		add r0 1
	while lt_s r0 100 end
	store x r0
	call foo
	int r8 # interrupt instruction calls into an imported function
	mov r0 r8
	int r0
	nop
	do
		add r0 10
		int r0
	while lt_s r0 200 end
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

