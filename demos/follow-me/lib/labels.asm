#importonce

//
// All of the constants referenced in the rest of the library
//


// We enable by setting bit 8
.const ENABLE   = $80
.const DISABLE  = $00

// Bit 8
.const BIT8 = ENABLE

// Bit 7
.const BIT7 = $40

// Lower 7 bits
.const LOWER7 = $7f

.const NMI_VECTOR   = $fffa
.const RESET_VECTOR = $fffc
.const IRQ_VECTOR   = $fffe

// Game Modes
.label GAME_MODE_ATTRACT    = $00
.label GAME_MODE_COMPUTER   = $01
.label GAME_MODE_HUMAN      = $02
.label GAME_MODE_FAIL       = $03
.label GAME_MODE_GAME_OVER  = $04
.label GAME_MODE_WIN        = $05

// Timer constants
.label TIMER_SINGLE         = $00
.label TIMER_CONTINUOUS     = $01
.label TIMER_HALF_SECOND    = $1e
.label TIMER_ONE_SECOND     = $3c
.label TIMER_TWO_SECONDS    = $78
.label TIMER_THREE_SECONDS  = $b4
.label TIMER_FOUR_SECONDS   = $f0
.label TIMER_STRUCT_BYTES   = $40

// The bank the VIC-II chip will be in
.label BANK = $00

// The start of physical RAM the VIC-II will see
.label VIC_START = (BANK * $4000)

.label SCREEN_START = VIC_START + $0400
.label SPRITE_POINTERS = SCREEN_START + $03f8

// Offsets for start of VIC memory for each sprite attribute
.label SPR_VISIBLE  = vic.SPENA   - vic.SP0X
.label SPR_X_EXPAND = vic.XXPAND  - vic.SP0X
.label SPR_Y_EXPAND = vic.YXPAND  - vic.SP0X
.label SPR_HMC      = vic.SPMC    - vic.SP0X
.label SPR_PRIORITY = vic.SPBGPR  - vic.SP0X

// Flags for various sprite settings
.label SPR_HIDE       = DISABLE
.label SPR_SHOW       = ENABLE
.label SPR_NORMAL     = DISABLE
.label SPR_EXPAND     = ENABLE
.label SPR_FG         = DISABLE
.label SPR_BG         = ENABLE
.label SPR_HIRES      = DISABLE
.label SPR_MULTICOLOR = ENABLE

// Joystick constants
.label JOY_BUTTON = %00010000
.label JOY_UP     = %00000001
.label JOY_DOWN   = %00000010
.label JOY_LEFT   = %00000100
.label JOY_RIGHT  = %00001000

.const RED_ADDRESS      = $0541
.const YELLOW_ADDRESS   = $054b
.const GREEN_ADDRESS    = $0555
.const BLUE_ADDRESS     = $055f
