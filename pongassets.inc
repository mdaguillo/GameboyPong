; pongassets.inc
; definitions used in pong.asm

printt	"Beginning assembling pongassets.inc\n"

TimerHertz	EQU	TACF_START|TACF_4KHZ
GameTimerClockDiv	EQU	256-100			; Interrupt occurs ~40.96 times a second
OneSecTimerClockDiv EQU 256-1			; Interrupt occurrs 4096 times a second	

TimerOFlowSet	EQU	1
TimerOFlowReset	EQU	0

HIGHRAMLOC	EQU	$ff80
OAMDATALOC	EQU	_RAM				; must be multiple of $100
OAMDATALOCBANK	EQU	OAMDATALOC/$100 
OAMDATALENGTH	EQU	$A0

LoRamBase       SET     OAMDATALOC + OAMDATALENGTH	; low area of RAM for storing variables

BallStartingPosX 			EQU	80
BallStartingPosY			EQU	72
LeftPaddleStartingPosX		EQU	0
LeftPaddleStartingPosY		EQU	72
RightPaddleStartingPosX		EQU	152
RightPaddleStartingPosY		EQU	72

; Background locations				 x offset    y offset
LeftScoreTopSpriteLocation EQU (_SCRN0)+(7)+(SCRN_VY_B*1)
RightScoreTopSpriteLocation EQU (_SCRN0)+(12)+(SCRN_VY_B*1)
TitleTextLocation EQU (_SCRN0)+(6)+(SCRN_VY_B * 7)

OneByteVar:	MACRO
\1		EQU	LoRamBase
LoRamBase	SET	LoRamBase+1
		ENDM

TwoByteVar: MACRO
\1		EQU LoRamBase
LoRamBase	SET LoRamBase+2
		ENDM

		RSSET	OAMDATALOC
SpriteAttr:	MACRO
\1YAddr		RB	1
\1XAddr		RB	1
\1TileNum	RB	1
\1Flags		RB	1
		ENDM

;set XAddr of sprite.
;format:
;	PutSpriteXAddr	SpriteName,r8
;	PutSpriteXAddr	SpriteName,n8
PutSpriteXAddr:	MACRO
		push	af
		ld	a,\2
		add	8	
		ld	[\1XAddr],a
		pop	af
		ENDM

;set YAddr of sprite.
;format:
;	PutSpriteYAddr	SpriteName,r8
;	PutSpriteYAddr	SpriteName,n8
PutSpriteYAddr:	MACRO
		push	af
		ld	a,\2
		add	16	
		ld	[\1YAddr],a
		pop	af
		ENDM

GetSpriteXAddr:	MACRO
		ld	a,[\1XAddr]
		sub	8
		ENDM

GetSpriteYAddr:	MACRO
		ld	a,[\1YAddr]
		sub	16
		ENDM
		
		printt	"Finished Assembling pongassets.inc\n"