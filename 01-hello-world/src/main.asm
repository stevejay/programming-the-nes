; set the correct CPU instruction set for the NES.
.setcpu "6502"

; constants
PPU_CTRL         = $2000
PPU_MASK         = $2001
PPU_STATUS       = $2002
PPU_OAM_ADDR     = $2003
    ; "Write the address of OAM you want to access here.
    ; Most games just write $00 here and then use OAMDMA."
PPU_SCROLL       = $2005
PPU_ADDR         = $2006
PPU_DATA         = $2007

APU_MODCTRL      = $4010
APU_PAD2         = $4017

BG_ENABLED          = %00001000
NO_BKGRND_LEFT_CLIP = %00000010

.segment "HEADER"
; header bytes format: https://wiki.nesdev.com/w/index.php/INES

.byte "NES", $1A ; Magic cookie
.byte $01 ; Size of PRG-ROM in 16 KB units
.byte $01 ; Size of CHR-ROM in 8 KB units (0 means the program uses CHR RAM)
; Mirroring, save RAM, trainer, mapper low nybble
.byte $00                                   ; mapper 0 (NROM), save RAM
; Vs., PlayChoice-10, NES 2.0, mapper high nybble
.byte $00
; Size of PRG RAM in 8 KB units
.byte $00
; NTSC/PAL
.byte $00

; 4E 45 53 1A 01010000 00000000 00000000

.segment "CODE"

reset_handler:
    sei ; disable interrupts during reset
    cld ; disable decimal mode to support generic 6502 debuggers

    ; We need to make sure that about 29658 cycles have passed
    ; before doing non-initialisation work.
    ; This is because the PPU will ignore some writes before then.
    ; (https://wiki.nesdev.com/w/index.php/PPU_power_up_state)
    ; "BIT will load bit 7 of the addressed value directly into the N flag."
    bit PPU_STATUS  ; clear the VBL flag if it was set at reset time
                    ; and persisted across the reset.
                    ; 'bit' works by sampling the values of bits 6 and 7
                    ; of the PPU status byte and setting them as the values
                    ; of the overflow (V) and negative (N) flags respectively
                    ; of the processor status flag register.
                    ; Reading PPU_STATUS has the side-effect of clearing the VBL flag.
                    ; https://retrocomputing.stackexchange.com/questions/11108/why-does-the-6502-have-the-bit-instruction

vblank_wait_1:
    bit PPU_STATUS 
    bpl vblank_wait_1 ; loop if bit 7 (negative flag) set to 0, meaning not currently in vblank; a value of 1 for bit 7 means vblank started.
                      ; https://wiki.nesdev.com/w/index.php/NMI

    ldx #$40
    stx APU_PAD2    ; disable APU frame IRQ - why???

    ldx #$00
    ; I think delaying these PPU writes to after the vblank waits
    ; is the correct thing to do, as writes to this PPU_CTRL register
    ; are ignored for about 30,000 cycles.
    ; https://wiki.nesdev.com/w/index.php/PPU_registers#Status_.28.242002.29_.3C_read
    stx PPU_CTRL ; disable the NMI at the start of each vblank.
    stx PPU_MASK ; set normal rendering ($00) of sprites and backgrounds
                 ; and disable sprite and background rendering.
    stx PPU_OAM_ADDR ; "Most games just write $00 here and then use OAMDMA."
                     ; https://wiki.nesdev.com/w/index.php/PPU_registers#Status_.28.242002.29_.3C_read
    stx APU_MODCTRL ; disable DPCM IRQ

    ; load all ram with 0's.
    ; ld a with 0, then store
    ; a into the location + x.
    ldx #$00
    lda #$00

clear_memory:
    sta $0000, x ; zero page
    sta $0100, x ; stack page
    sta $0200, x
    sta $0300, x
    sta $0400, x
    sta $0500, x
    sta $0600, x
    sta $0700, x
    ; This is an alternative way to clear $02XX if you will be
    ; using it as shadow OAM memory.
    ; lda #$FE
    ; sta $0200, x ; move all sprites off screen
    inx
    bne clear_memory ; loop until value of x wraps around to zero.

vblank_wait_2:
    bit PPU_STATUS 
    bpl vblank_wait_2

    ldx #$FF
    txs ; set up stack by copying value of x ($FF) into the stack pointer register.
        ; FF is used as the initial value of the stack pointer as 
        ; the 6502 has a descending stack (i.e., it grows downwards),
        ; so we point to the end byte of the stack page.

    ; write the palette to $3F00 (one background palette)
    bit PPU_STATUS ; reset the PPU scroll/address latch to high.
                   ; When writing data to PPUADDR, we need to first reset the high/low latch (to high).
                   ; An alternative is LDA PPUSTATUS, but that overwrites the current content of A.
    lda #$3F
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    ldx #$00 ; counter

:   lda palette,x
    sta PPU_DATA ; write to ppu
    inx
    cpx #$4; is it $4?
    bne :-  ; if not, go to -

print_message:
    bit PPU_STATUS ; reset the PPU scroll/address latch.
                   ; https://retrocomputing.stackexchange.com/questions/2238/trying-to-understand-what-an-address-latch-is-while-emulating-the-nes-ppu
    ; write to the first nametable (which starts at $2000).
    lda #$21
    sta PPU_ADDR
    lda #$80
    sta PPU_ADDR

    ldx #$00 ; index into message
:   lda message, x
    cmp #$00
    beq load_attr
    sta PPU_DATA
    inx
    jmp :-

load_attr:
    bit PPU_STATUS ; reset the PPU scroll/address latch.
    ; write to the attribute area ($23C0 onwards) of the first nametable.
    lda #$23
    sta PPU_ADDR
    lda #$C0
    sta PPU_ADDR

    ldx #$00 ; counter

:   lda #$00
    sta PPU_DATA
    inx
    cpx #$40; is it $40?
    bne :-  ; if not, go to -

    ; reset scroll
    ; "Before turning rendering back on, we have to tell the PPU which pixel
    ; of the nametable should be at the top-left corner of the screen.
    ; This is done by writing first the horizontal offset followed by
    ; the vertical offset to the PPU_SCROLL register. We want to start
    ; from the beginning of the nametable, so we’ll set both to zero."
    ; https://timcheeseman.com/nesdev/2016/01/18/hello-world-part-one.html
    bit PPU_STATUS ; reset the PPU scroll/address latch.
    lda #$00
    sta PPU_SCROLL
    lda #$00
    sta PPU_SCROLL

    ; should I wait for vblank here before enabling the bg?

    lda #BG_ENABLED | NO_BKGRND_LEFT_CLIP ; enable background rendering.
    sta PPU_MASK

@loop_forever:
  jmp @loop_forever

palette:
.byte $02,$30,$20,$20

message:
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$05,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$02,$20,$20,$20,$20,$20,$20,$20,$20  ; row 13
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$01,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$01,$20,$20,$20,$20,$20,$20,$20,$20  ; row 14
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$01,$20,"Hello, world",$20,$01,$20,$20,$20,$20,$20,$20,$20,$20  ; row 15
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$01,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$01,$20,$20,$20,$20,$20,$20,$20,$20  ; row 16
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$04,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$03,$20,$20,$20,$20,$20,$20,$20,$20  ; row 17
  .byte $00

.proc nmi_handler
  ; do nothing
  rti
.endproc

; noop handler
.proc irq_handler
  ; do nothing
  rti
.endproc

.segment "VECTORS"
.addr nmi_handler, reset_handler, irq_handler

.segment "CHRROM"
.incbin "./font.tbl" ; include the content of the font file here
