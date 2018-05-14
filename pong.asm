; Pong Example
; February 9th 2017
; Mike D'Aguillo

INCLUDE "gbhw.inc" ; standard hardware definitions from devrs.com
INCLUDE "pongassets.inc" ; specific defs
INCLUDE "PongSprites.z80"
INCLUDE "memory.asm"

; create variables
	SpriteAttr	LeftPaddle 
	SpriteAttr	RightPaddle
	SpriteAttr	Ball
	OneByteVar	BallXVelocity
	OneByteVar	BallYVelocity
	OneByteVar	TimerEvent
	OneByteVar	XCollisionCounter ; Amount of times there's been a horizontal collision
	OneByteVar	LeftScore
	OneByteVar	RightScore
	OneByteVar	RNGSeed
	TwoByteVar	OneSecondTimer
	
; IRQs
SECTION	"Vblank",HOME[$0040]
	jp	HIGHRAMLOC ; *hs* update sprites every time the Vblank interrupt is called (~60Hz)
SECTION	"LCDC",HOME[$0048]
	reti
SECTION	"Timer_Overflow",HOME[$0050]
	jp	TimerInterrupt		; flag the timer interrupt
SECTION	"Serial",HOME[$0058]
	reti
SECTION	"p1thru4",HOME[$0060]
	reti

; ****************************************************************************************
; boot loader jumps to here.
; ****************************************************************************************
SECTION	"start",HOME[$0100]
nop
jp	begin

; ****************************************************************************************
; ROM HEADER and ASCII character set
; ****************************************************************************************
; ROM header
	ROM_HEADER	ROM_NOMBC, ROM_SIZE_32KBYTE, RAM_SIZE_0KBYTE

; ****************************************************************************************
; Main code Initialization:
; set the stack pointer, enable interrupts, set the palette, set the screen relative to the window
; copy the ASCII character table, clear the screen
; ****************************************************************************************
begin:
	nop
	di
	ld	sp, $ffff		; set the stack pointer to highest mem location + 1

; NEXT FOUR LINES FOR SETTING UP SPRITES *hs*
	call	initdma			; move routine to HRAM
	ld	a, IEF_VBLANK|IEF_TIMER
	ld	[rIE],a			; ENABLE VBLANK AND TIMER INTERRUPT
	ei				; LET THE INTS FLY

init:
	ld	a, %11100100 		; Window palette colors, from darkest to lightest
	ld	[rBGP], a		; set background and window pallette
	ldh	[rOBP0],a		; set sprite pallette 0 (choose palette 0 or 1 when describing the sprite)
	ldh	[rOBP1],a		; set sprite pallette 1

	ld	a,0			; SET SCREEN TO TO UPPER RIGHT HAND CORNER
	ld	[rSCX], a
	ld	[rSCY], a		
	call	StopLCD			; YOU CAN NOT LOAD $8000 WITH LCD ON
	ld	hl, Sprites
	ld	de, _VRAM		; $8000
	ld	bc, 16 * 32
	call	mem_Copy	; load tile data
	
; *hs* erase sprite table
	ld	a,0
	ld	hl,OAMDATALOC
	ld	bc,OAMDATALENGTH
	call	mem_Set
	
	; Set the LCDC register
	ld	a, LCDCF_ON|LCDCF_BG8000|LCDCF_BG9800|LCDCF_BGON|LCDCF_OBJ8|LCDCF_OBJON ; *hs* see gbspec.txt lines 1525-1565 and gbhw.inc lines 70-86
	ld	[rLCDC], a
	
; ****************************************************************************************
; Title Screen:
; Draw the sprites, wait for user input
; ****************************************************************************************	
titleSetup:
	; Draw the title screen sprites
	ld	a, $17		; First make the whole screen black
	ld	hl, _SCRN0
	ld	bc, SCRN_VX_B * SCRN_VY_B
	call	mem_SetVRAM	
	
	; Now draw the letters of the title screen
	ld a,$18					; P
	ld hl,TitleTextLocation
	call Draw8by16Sprite
	
	ld a,$1A					; O
	ld hl,TitleTextLocation+2
	call Draw8by16Sprite
	
	ld a,$1C					; N
	ld hl,TitleTextLocation+4
	call Draw8by16Sprite
	
	ld a, $1E					; G
	ld hl,TitleTextLocation+6
	call Draw8by16Sprite
	
TitleLoop:
	call	GameLoopTimeDelay
	call	GetKeys
	and		PADF_START
	jp		nz,StartNewGame
	jr		TitleLoop
	
; ****************************************************************************************
; Game code:
; This is the main game engine code. 
; ****************************************************************************************
StartNewGame:
	; Start the timer so we can seed the RNG
	ld	a,GameTimerClockDiv		; load number of counts of timer
	ld	[rTMA],a		
	ld	a,TimerHertz		; load timer speed
	ld	[rTAC],a

	ld	a, $33						; Clear the screen
	ld	hl, _SCRN0
	ld	bc, SCRN_VX_B * SCRN_VY_B
	call	mem_SetVRAM	

	; Set LeftPaddle location to 0,72
	PutSpriteXAddr	LeftPaddle,LeftPaddleStartingPosX
	PutSpriteYAddr	LeftPaddle,LeftPaddleStartingPosY	
 	ld	a,20
 	ld 	[LeftPaddleTileNum],a      ; Left Paddle's tile address
 	ld	a,%00000000         	   ; set flags (see gbhw.inc lines 33-42)
 	ld	[LeftPaddleFlags],a        ; save flags
	
	; Set RightPaddle location to 152,72
	PutSpriteXAddr	RightPaddle,RightPaddleStartingPosX
	PutSpriteYAddr	RightPaddle,RightPaddleStartingPosY
 	ld	a,21
 	ld 	[RightPaddleTileNum],a      ; Left Paddle's tile address
 	ld	a,%00000000         		; set flags (see gbhw.inc lines 33-42)
 	ld	[RightPaddleFlags],a        ; save flags
	
	; Set Ball location to 80,72
	PutSpriteXAddr	Ball,BallStartingPosX
	PutSpriteYAddr	Ball,BallStartingPosY
 	ld	a,22
 	ld 	[BallTileNum],a      ; Ball's tile address
 	ld	a,%00000000        	 ; set flags (see gbhw.inc lines 33-42)
 	ld	[BallFlags],a        ; save 
	
	; Set up the collision counter which keeps track of when to speed up velocity
	ld	a,1
	ld	[XCollisionCounter],a	
	
	; Set the starting score
	ld	a,0
	ld	[LeftScore],a
	ld	[RightScore],a
	ld	h,a
	ld	l,a
	call	DrawScore
	
	ld	a,[rTIMA]			; Seed the RNG with whatever is in the Divider Register (this is incremented ~16k times a second)
	ld	[RNGSeed],a	
	call	SetRandomBallVelocity
	
GameLoop:
	call	GameLoopTimeDelay
	call	UpdateBall
	call	GetKeys
	push	af
	and		PADF_UP
	call	nz,MoveLeftPaddleUp
	pop		af
	push	af
	and		PADF_DOWN
	call	nz,MoveLeftPaddleDown
	pop		af
	push	af
	and		PADF_A
	call	nz,MoveRightPaddleUp
	pop		af
	push	af
	and		PADF_B
	call	nz,MoveRightPaddleDown
	pop		af
	jr		GameLoop

; ****************************************************************************************
; Functions
; ****************************************************************************************
; Moves the left paddle up
MoveLeftPaddleUp:		
	GetSpriteYAddr	LeftPaddle,a
	cp		0				; already at top of screen?
	ret		z
	SUB		a,3				; Move 3 pixels up
	cp		SCRN_Y-8		; Check to see if we've gone too far up now	
	jp		c,.end			; Check if we haven't wrapped past 0 (to 255). If the carry flag is set, the screen is still larger
.loop
	INC		a				; If we got here we need to keep adding until we wrap back to 0 
	cp		SCRN_Y-8
	jr		nc,.loop
.end:
	PutSpriteYAddr	LeftPaddle,a
	ret
	
; Moves the left paddle down
MoveLeftPaddleDown:		
	GetSpriteYAddr	LeftPaddle,a
	cp		SCRN_Y-8	; already at bottom of screen?
	ret		z
	ADD		a,3			; move 3 pixels down
	cp		SCRN_Y-8	; Now are we at the bottom of the screen?
	jp		z,.end		; If it's now zero we're at the bottom of the screen, set the value
	jp		c,.end 		; If we get here and the carry flag is set we're not past the screen
.loop
	DEC		a			; If we're here, we need to decrement until were at 0
	cp		SCRN_Y-8
	jr		nz,.loop
.end:
	PutSpriteYAddr	LeftPaddle,a ; store the final position again
	ret

; Moves the left paddle up
MoveRightPaddleUp:		
	GetSpriteYAddr	RightPaddle,a
	cp		0				; already at top of screen?
	ret		z
	SUB		a,3				; Move 3 pixels up
	cp		SCRN_Y-8		; Check to see if we've gone too far up now	
	jp		c,.end			; Check if we haven't wrapped past 0 (to 255). If the carry flag is set, the screen is still larger
.loop
	INC		a				; If we got here we needto keep adding until we wrap back to 0 
	cp		SCRN_Y-8
	jr		nc,.loop
.end:
	PutSpriteYAddr	RightPaddle,a
	ret

; Moves the left paddle down
MoveRightPaddleDown:		
	GetSpriteYAddr	RightPaddle,a
	cp		SCRN_Y-8	; already at bottom of screen?
	ret		z
	ADD		a,3			; move 3 pixels down
	cp		SCRN_Y-8	; Now are we at the bottom of the screen?
	jp		z,.end		; If it's now zero we're at the bottom of the screen, set the value
	jp		c,.end 		; If we get here and the carry flag is set we're not past the screen
.loop
	DEC		a			; If we're here, we need to decrement until were at 0
	cp		SCRN_Y-8
	jr		nz,.loop
.end:
	PutSpriteYAddr	RightPaddle,a ; store the final position again
	ret
	
; Function which updates the ball's position based on its current velocity
; First checks if the ball has collided with a paddle or wall
; Then attempt to move the ball based on its velocity and stop if it collides with something relevant
; Register use:
; b = Temp storage for collision operations
; d = Temp storage for velocity operations
; h = stores final ball X position
; c = stores final ball Y position
UpdateBall:
	; Store the ball's X and Y position to start
	GetSpriteXAddr	Ball,a
	ld				h,a
	GetSpriteYAddr	Ball,a
	ld				c,a
	
	; Check if the ball collided with the left paddle
	call			LeftPaddleCheck 
	ld				a,1				
	cp				b				; If they're the same, we have a collision
	jp				z,.Xcollision
	
	; Check if the ball collided with the right paddle
	call			RightPaddleCheck 
	ld				a,1
	cp				b
	jp				z,.Xcollision
	
	; Check if the ball collided with Left Wall
	ld				l,0
	call			WallCollisionCheck 
	cp				1
	jp				z,.RightScore
	
	ld				l,1
	call			WallCollisionCheck
	cp				1
	jp				z,.LeftScore

	; If we get here no x collisions, jump to check y collisions
	jp				.toporbottomcheck

.LeftScore
	ld				a,[LeftScore]
	inc				a
	ld				[LeftScore],a
	jp				.PointScored
.RightScore	
	ld				a,[RightScore]
	inc				a
	ld				[RightScore],a
	jp				.PointScored
	
.PointScored
	cp		10				; Game Over?
	jp		z,titleSetup
	call	PointScored
	jp		GameLoop		; Else keep going
	
.Xcollision
	; At this point we've determined we have a collision, negate the velocity (and possibly increase it)
	ld		a,[XCollisionCounter]
	INC		a
	ld		[XCollisionCounter],a
	call	InvertXVelocity	
	
.toporbottomcheck
	; Check if the ball is touching one of the top or bottom edges of the screen
	ld				a,c			; Get the balls Y address
	cp				-2
	call			z,InvertYVelocity
	cp				SCRN_Y-6
	call			z,InvertYVelocity		

.setYPosition
	; Now set the Y position
	ld				a,[BallYVelocity] ; load the velocity into the accumulator
	add				a,c ; add the two
	PutSpriteYAddr	Ball,a
	
	; Finally increase the X position one pixel at a time (so we can check for collisions)
	; until we've moved the ball as many times as needed
	ld				a,[BallXVelocity]
	
	; Check the sign of the X velocity
	AND				%10000000
	cp				%10000000
	
	ld				a,[BallXVelocity]
	ld				l,a						; Load the velocity into the l register	
	ld				a,h						; Load the position into the accumulator
	jp				z,.negativeloop			; Our comparison flags are still set
	
.positiveloop
	INC				a		; Add one to the current position
	ld				h,a		; Store the new position
	ld				a,l		; Load the velocity reference into a
	DEC				a		; Decrease the velocity reference (bring it closer to zero)
	ld				l,a		; Load the velocity reference back into l

	; Now do some position checks. We first need to check if we collided with the right paddle OR the right wall
	; If that's the case then we're done with the loop and can store the position back into sprite memory
	; If we haven't collided, then we need to check if the velocity is zero. If it is we're done.
	
	ld				a,h						; Reload the position into a
	cp				SCRN_X-6				; Check if we collided with the right wall
	jp				z,.setXPosition
	ld				h,a						; Set up the arguments for the function call
	GetSpriteYAddr	Ball,a
	ld				c,a
	call			RightPaddleCheck
	ld				a,1
	cp				b						; Check if we've collided with the right paddle
	jp				z,.setXPosition
	
	; We haven't collided with either the right wall or the right paddle, check if velocity is non zero
	ld				a,0
	cp				l
	ld				a,h						; Don't forget to reload the current position into a
	jr				nz,.positiveloop		; If the velocity was non zero, go and loop back
	
	; Otherwise we're done and can set the position
	jp				.setXPosition
	
.negativeloop
	DEC				a		; Subtract one from the current position
	ld				h,a		; Store the new position
	ld				a,l		; Load the velocity reference into a
	INC				a		; Increase the velocity reference (bring it closer to zero)
	ld				l,a		; Reload the velocity reference back into l
	
	; Now do some position checks. We first need to check if we collided with the left paddle OR the left wall
	; If that's the case then we're done with the loop and can store the position back into sprite memory
	; If we haven't collided, then we need to check if the velocity is still non zero. If it isn't we're done.
	
	ld				a,h						; Reload the position into a
	cp				-2						; Check if we collided with the left wall
	jp				z,.setXPosition
	ld				h,a						; Set up the arguments for the function call
	GetSpriteYAddr	Ball,a
	ld				c,a
	call			LeftPaddleCheck
	ld				a,1
	cp				b						; Check if we've collided with the left paddle
	jp				z,.setXPosition
	
	; We haven't collided with either the left wall or the left paddle, check if velocity is non zero
	ld				a,0
	cp				l
	ld				a,h						; Don't forget to reload the current position into a
	jr				nz,.negativeloop		; If the velocity was non zero, go and loop back
	
	; Otherwise we're done and can set the position

.setXPosition
	ld				a,h
	PutSpriteXAddr	Ball,a
	ret
	
; Inverts the Y velocity of the ball
InvertYVelocity:
	push af ; Save the current a value
	ld	a,[BallYVelocity]
	ld	d,a ; Load velcoity into d
	ld	a,0
	SUB	d
	ld	[BallYVelocity],a	; Store the new negated value
	pop af ; Restore the previous a value
	ret
	
; Inverts the X velocity of the ball and increases its magnitude by 1
InvertXVelocity:
	push af ; Save the current a value
	
	; Check if theres been enough collisions to increase the counter
	ld	a,[XCollisionCounter]
	SRA	a						; Shift right. If carry flag is set, not divisible by 2
	jp	c,.dontincreasevelocity
	
	ld	a,[BallXVelocity]
	AND	%10000000
	cp	%10000000
	jp	z,.negativevelocity
.positivevelocity
	ld	a,[BallXVelocity]
	ADD	1
	jp	.negate
.negativevelocity
	ld	a,[BallXVelocity]
	SUB 1
	jp	.negate
.dontincreasevelocity
	ld	a,[BallXVelocity]
.negate
	ld	d,a ; Load velocity into d
	ld	a,0
	SUB	d
	ld	[BallXVelocity],a	; Store the new negated value
	pop af ; Restore the previous a value
	ret
	
; Function to wait a short amount of time
GameLoopTimeDelay:
	ld	a,TimerOFlowReset	; reset timer interrupt flag
	ld	[TimerEvent],a
	ld	a,GameTimerClockDiv		; load number of counts of timer
	ld	[rTMA],a		
	ld	a,TimerHertz		; load timer speed
	ld	[rTAC],a
.wait:	halt				; wait for an interrupt
	nop				; always follow HALT with NOP (gbspec.txt lines 514-578)
	ld	a,[TimerEvent]		; load timer flag
	cp	TimerOFlowSet		; was the interrupt caused by the timer?
	jr	nz,.wait		; nope. Keep waiting
	ret
	
; TimerInterrupt is the routine called when a timer interrupt occurs.
TimerInterrupt:	
	push	af			; save a
	push	hl
	ld	a,TimerOFlowSet		; load value representing that an interrupt occured.
	ld	[TimerEvent],a		; save value in a variable
	
	; Increment the 16bit variable so we can keep track of time on a seconds interval
	ld	a,[OneSecondTimer]
	ld	l,a
	ld	a,[OneSecondTimer+1]
	ld	h,a
	inc	hl
	ld	a,l
	ld	[OneSecondTimer],a
	ld	a,h
	ld	[OneSecondTimer+1],a
	pop hl
	pop	af			; restore a. Everything has been preserved.
	reti

; GetKeys: adapted from APOCNOW.ASM and gbspec.txt
GetKeys:                 ;gets keypress
	ld 	a,P1F_5			; set bit 5
	ld 	[rP1],a			; select P14 by setting it low. See gbspec.txt lines 1019-1095
	ld 	a,[rP1]
 	ld 	a,[rP1]			; wait a few cycles
	cpl				; complement A. "You are a very very nice Accumulator..."
	and 	$0f			; look at only the first 4 bits
	swap 	a			; move bits 3-0 into 7-4
	ld 	b,a			; and store in b

 	ld	a,P1F_4			; select P15
 	ld 	[rP1],a
	ld	a,[rP1]
	ld	a,[rP1]
	ld	a,[rP1]
	ld	a,[rP1]
	ld	a,[rP1]
	ld	a,[rP1]			; wait for the bouncing to stop
	cpl				; as before, complement...
 	and $0f				; and look only for the last 4 bits
 	or b				; combine with the previous result
 	ret				; do we need to reset joypad? (gbspec line 1082)

; This function returns 1 in the b register if there is a collision between the ball and the left paddle and 0 if there isn't.
; It uses the b register
; Arguments:
;	h = X position of the ball
;	c = Y position of the ball
LeftPaddleCheck:
	push			af				; Store the af registers
	
	; Check if the leftmost part of the ball is in the same plane as the rightmost part of the left paddle
	ld				a,h
	ADD				a,2				; Adjust for the white space of the ball
	ld				b,a				; Store the ball's adjusted x coordinate in b
	GetSpriteXAddr	LeftPaddle,a
	ADD				a,8				; Add 8 pixels so we have the position of the right most part of the paddle
	cp				b				; Now compare their positions
	jp				nz,.false		; If they are not the same, return false
	
	; Check if the top of the ball is below the left paddle
	ld				a,c				; Get the balls Y address
	ADD				a,2				; The ball has 2 pixels of white space we don't count
	ld				b,a				; Store the top of the balls address
	GetSpriteYAddr	LeftPaddle,a	
	ADD				a,8				; We want the bottom of the paddle
	cp				b				; Compare the bottom of the paddle to the top of the ball
	jp				z,.true			; If they're the same we have a collision
	jp				c,.false		; If carry is set, the ball is greater and past the paddle
	
	; Check if the bottom of the ball is above the left paddle
	ld				a,c				; Get the ball's y address
	ADD				a,6				; Adjust to bottom pixel of ball
	ld				b,a				; Store the value for later
	GetSpriteYAddr	LeftPaddle,a
	cp				b				; Compare the bottom of the ball to the top of the paddle
	jp				z,.true			; They're the same we have a collision
	jp				nc,.false		; NC = The paddles position is greater (below), so the ball is past
	
	; If we get here we have a collision
	jp				.true
	
.false
	ld				b,0
	jp				.end
.true
	ld				b,1	
.end
	pop				af				; Restore the stack
	ret

; This function returns 1 in the b register if there is a collision between the ball and the right paddle and 0 if there isn't.
; It uses the b register
; Arguments:
;	h = X position of the ball
;	c = Y position of the ball
RightPaddleCheck:
	push			af						; Store the af registers
	
	; Check if the right most part of the ball is in the same plane as the leftmost part of the right paddle
	ld				a,h
	ADD				a,6						; Adjust to the rightmost part of the ball
	ld				b,a
	GetSpriteXAddr	RightPaddle,a			; We don't need any extra adjustments
	cp				b
	jp				nz,.false 				; Not in same plane, return false
	
	; Check if the top most part of the ball is below the bottom most part of the right paddle
	ld				a,c
	ADD				a,2				; The ball has 2 pixels of white space
	ld				b,a
	GetSpriteYAddr 	RightPaddle,a	
	ADD				a,8				; We want the bottom of the paddle
	cp				b
	jp				z,.true
	jp				c,.false
	
	; Check if the bottom most part of the ball is above the top most part of the right paddle
	ld				a,c				; Load the balls position
	ADD				a,6				; Adjust to the bottom part of the ball
	ld				b,a				; Store temporarily in b
	GetSpriteYAddr	RightPaddle,a	; Get the position of the paddle
	cp				b				; Check if the paddle's top position is > than the balls bottom
	jp				z,.true
	jp				nc,.false
	
	; If we get here there's a collision
	jp				.true

.false
	ld				b,0
	jp				.end
.true
	ld				b,1
.end	
	pop				af
	ret

; This function checks if there is a collision between the ball and either wall.
; It uses the b register
; Arguments:
;	h = X position of the ball
;	l (Bool) = When 0 check left wall, when 1 check right wall
; Returns 1 in the 'a' register if there is a collision, 0 if there is not 
WallCollisionCheck:
	push			hl
	ld				a,l		
	cp				1
	ld				a,h					; Load ball's x pos in accum
	jp				z,.RightWallCheck	; If 1 check RightWall
	jp				.LeftWallCheck		; Else check LeftWall

.RightWallCheck
	cp				SCRN_X-6			; The ball has 2 pixels of empty space
	jp				.result
.LeftWallCheck
	cp				-2
.result
	jp				z,.true
	jp				.false
.false
	ld				a,0
	jp				.end
.true
	ld				a,1
.end
	pop				hl
	ret
	
; Arguments:
;	a = Top sprite tile number
;	hl = Top Sprite screen location
Draw8by16Sprite:
	push bc 			; Save the values in these registers
	push hl
	push af 			; Save the vram tile location
	ld	 bc,1
	call mem_SetVRAM
	pop	 af
	inc	 a
	pop	 hl
	ld	 de,SCRN_VY_B	; Move the screen sprite location down one 
	add	 hl,de			
	ld	 bc,1			; Just in case
	call mem_SetVRAM
	pop  bc
	ret
	
; This function checks the current score and draws the correct tiles to the score locations in the background
; Arguments:
;	h = LeftScore
;	l = RightScore
DrawScore:
	; Let's draw the left score.
	; The location of the sprite in VRAM is simply an offset of the current score * 2
	push hl 			; save the score info before performing a multiply to get the offset
	ld	e,h 			; Load the left score into the low order byte for the multiply function
	ld	a,2				; Multiplying by 2 (the offset of the score to sprite location)
	call	Mult8Bit
	ld	a,l				; Load the lower order byte result
	
	ld	hl,LeftScoreTopSpriteLocation
	call Draw8by16Sprite
	
	; Now do the same for the right score
	pop hl								; Get the scores back
	ld	e,l								; load the right score into low order byte
	ld	a,2
	call	Mult8Bit
	ld	a,l
	
	ld	hl,RightScoreTopSpriteLocation
	call Draw8by16Sprite
	ret
	
; This function redraws the score, waits a second, resets the balls position towards the center of the screen, waits a second, and finally gives it a random velocity.
PointScored:
	; Update the score
	ld		a,[LeftScore]
	ld		h,a
	ld		a,[RightScore]
	ld		l,a
	call DrawScore
	
	; Wait a second
	call WaitOneSecond
	
	; Reset the ball and paddle positions
	PutSpriteXAddr	Ball,BallStartingPosX
	PutSpriteYAddr	Ball,BallStartingPosY
	PutSpriteXAddr	LeftPaddle,LeftPaddleStartingPosX
	PutSpriteYAddr	LeftPaddle,LeftPaddleStartingPosY
	PutSpriteXAddr	RightPaddle,RightPaddleStartingPosX
	PutSpriteYAddr	RightPaddle,RightPaddleStartingPosY
	
	; Reset the collision counter
	ld	a,1
	ld	[XCollisionCounter],a	
	
	; Reset the ball's velocity
	call SetRandomBallVelocity
	
	; Wait a second
	call WaitOneSecond
	
	ret
	
; High Ram functions that copies the place in memory where we store the sprite positions to the actual 
; Place in memory the gameboy reads the sprite data from
initdma:
	ld	de, HIGHRAMLOC
	ld	hl, dmacode
	ld	bc, dmaend-dmacode
	call	mem_CopyVRAM			; copy when VRAM is available
	ret
dmacode:
	push	af
	ld	a, OAMDATALOCBANK		; bank where OAM DATA is stored
	ldh	[rDMA], a			; Start DMA
	ld	a, $28				; 160ns
dma_wait:
	dec	a
	jr	nz, dma_wait
	pop	af
	reti
dmaend:

; Turn off LCD if it is on and wait until the LCD is off
StopLCD:
        ld      a,[rLCDC]
        rlca                    ; Put the high bit of LCDC into the Carry flag
        ret     nc              ; Screen is off already. Exit.
.wait:							; Loop until we're in vblank
        ld      a,[rLY]
        cp      145             ; Is display on scan line 145 yet?
        jr      nz,.wait        ; no, keep waiting
        ld      a,[rLCDC]		; Turn off the LCD
        res     7,a             ; Reset bit 7 of LCDC
        ld      [rLCDC],a
        ret

; A simple multiply function that allows you to multiply a 16 bit number by an 8 bit one
; Works for products < 65536
; Taken from here: http://sgate.emt.bme.hu/patai/publications/z80guide/part4.html
; Arguments
;	A =	8 bit factor
;	DE = 16 bit factor
;	HL = 16 bit result
;	B = operand counter
;	C = temp storage
Mult8Bit:
	ld hl,0                        ; HL is used to accumulate the result
	ld b,8                         ; the multiplier (A) is 8 bits wide
.Mul8Loop
    rrca                           ; putting the next bit into the carry
	jp nc,.Mul8Skip                 ; if zero, we skip the addition (jp is used for speed)
	add hl,de                      ; adding to the product if necessary
.Mul8Skip
	sla e                          ; calculating the next auxiliary product by shifting
	rl d                           ; DE one bit leftwards (refer to the shift instructions!)
	dec b
	ld c,a							; Store the 8 bit factor
	ld a,b
	cp 0
	ld a,c							; Reload the 8 bit factor
	jr nz,.Mul8Loop
	ret
	
; An 8-bit pseudo-random number generator function,
; using a similar method to the Spectrum ROM,
; - without the overhead of the Spectrum ROM.
;
; Returns a random number in the Accumulator
RandomNum:
	ld a, [RNGSeed]
	ld b, a 

	rrca ; multiply by 32
	rrca
	rrca
	xor	 a,%00011111

	add a, b
	sbc a, 255 ; carry

	ld [RNGSeed], a
	ret

; Uses a Pseudo random num generator to set a randomly either "1" or "-1" as the ball's x and y velocity
SetRandomBallVelocity:
	call 	RandomNum		; Gen some random number
	cp		$7F				; Determine if the number is negative or not
	
	jp		nc,.negativeNumberX
	
.positiveNumberX
	ld		a,1
	ld		[BallXVelocity],a
	jp		.GenYVel
.negativeNumberX
	ld		a,-1
	ld		[BallXVelocity],a

.GenYVel	
	call 	RandomNum		; Gen some random number
	cp		$7F				; Determine if the number is negative or not
	jp		nc,.negativeNumberY	

.positiveNumberY
	ld		a,1
	ld		[BallYVelocity],a
	jp		.end
.negativeNumberY
	ld		a,-1
	ld		[BallYVelocity],a
.end
	ret

WaitOneSecond:
	ld	a,OneSecTimerClockDiv		; load number of counts of timer
	ld	[rTMA],a	
	ld	a,TimerHertz		; load timer speed
	ld	[rTAC],a
	
	ld	a,0
	ld	[OneSecondTimer],a	; Reset the counter
	ld	[OneSecondTimer+1],a
	
.loop:
	ld	a,TimerOFlowReset	; reset timer interrupt flag
	ld	[TimerEvent],a
.wait:
	halt
	nop
	ld	a,[TimerEvent]
	cp	TimerOFlowSet
	jr	nz,.wait
	
	; Check if the OneSecondTimer is equal to 4096
	ld	a,[OneSecondTimer+1]
	
; A second passes when the OneSecondTimer address space = $1000. Since we reset the high order byte to 0 earlier, we don't have to worry about checking the low order byte ever. Just need to make sure that the counter is greater than $1000 (and thus the high order byte just needs to be $10 or greater).
.highorderbytecompare:
	cp	$10
	jr	c,.loop		; Smaller than $10? Keep waiting	
	ret