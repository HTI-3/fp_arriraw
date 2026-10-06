/* og95 -- record CinemaDNG from sensor mode 95 (MONIT1_24_HD, 5712x3216,
 * 23.976, 14-bit readout) in place of stock UHD 23.98 12-bit.
 *
 * The same four-part method fp_sup's open gate documents (projects/open-gate.md),
 * applied to one stock slot:
 *
 *   picker     12-bit table slot 3 (UHD23_98, profile 172): mode 101 -> 95
 *   producer   record RWZM for canvas record 119 (p172): 1600 -> 1024 (unity)
 *   canvas     this hook: the gathered geometry record, raster and crop
 *   timing     none -- mode 95 is natively 911 x 3296 at 72 MHz = 23.976
 *
 * The first three are placed by build_og95_card.py as loader sections, so
 * stage2 journals every firmware word and writes it back at power-off.
 *
 * Hook site 0xC043A19C inside FUN_c043a158(obj=r4, profile=r5, ...): stock
 * `mov r0, r4`, directly after FUN_c0439d18 gathers the profile's 67 fields
 * into the canvas record at obj+0x5C and before anything derives from it.
 * Reached by BL, so lr is the return; clobbers only r0-r3 and ip, which the
 * very next instruction (a BL) does not preserve either.
 *
 * Applies only when profile == 172 AND the record still holds the stock
 * UHD23_98 geometry. Anything else passes through untouched.
 *
 *   +00/+04  RAW raster        3856x2170 -> 5712x3216
 *   +DC/+E4  RAW override      3856x2170 -> 5712x3216   (size getters read it)
 *   +24/+2C  active crop       3840x2160 -> 5696x3206   (+16/+10 convention)
 *   +F4/+F8  sensor output     6064x3412 -> 5712x3216   (INPUT_FIELDS=1 only)
 *
 * Preview fields (+0C/+10, +20/+28, +D8/+E0, +60/+D0) and the 12-bit plane
 * format (+80/+84 = 7/7) are left stock -- unless REC14:
 *
 *   +84      record plane format  7 -> 8                   (REC14=1 only)
 *
 * The record buffer's bit-depth enum is FUN_c0436360(record[+0x84]) (read by
 * FUN_c0436218 for the builder FUN_c04381e8 -> FUN_c04385c8); 8 maps to enum 1,
 * 14-bit, as it does in every stills profile. +80 is the preview side and stays
 * 7: OG3K found a movie preview that is not 12-bit goes green and flickers.
 *
 * Telemetry at TEL: {hits applied, calls seen for p172, last guard miss mask}.
 */
    .syntax unified
    .arm

.macro ldr_addr reg, value
    movw    \reg, #:lower16:\value
    movt    \reg, #:upper16:\value
.endm

.equ PROFILE,    172
.equ TEL,        0xC072FA00
.equ INPUT_FIELDS, 0
.equ REC14,      1

    .global og95_canvas
og95_canvas:
    cmp     r5, #PROFILE
    bne     pass
    ldr_addr ip, TEL
    ldr     r1, [ip, #4]
    add     r1, r1, #1
    str     r1, [ip, #4]            @ calls seen for p172

    add     r0, r4, #0x5C           @ canvas record
    mov     r2, #0                  @ guard miss mask
    adr     r3, guard
1:  ldr     r1, [r3], #4            @ offset, or 0xFFFFFFFF = end
    cmn     r1, #1
    beq     2f
    ldr     r1, [r0, r1]
    ldr     ip, [r3], #4            @ expected stock value
    cmp     r1, ip
    orrne   r2, r2, #1
    lsl     r2, r2, #1
    b       1b
2:  cmp     r2, #0
    ldr_addr ip, TEL
    strne   r2, [ip, #8]
    bne     pass

    adr     r3, apply
3:  ldr     r1, [r3], #4
    cmn     r1, #1
    beq     4f
    ldr     r2, [r3], #4
    str     r2, [r0, r1]
    b       3b
4:
.if INPUT_FIELDS
    adr     r3, apply_input
5:  ldr     r1, [r3], #4
    cmn     r1, #1
    beq     6f
    ldr     r2, [r3], #4
    str     r2, [r0, r1]
    b       5b
6:
.endif
.if REC14
    ldr     r1, [r0, #0x84]         @ only from stock 12-bit record
    cmp     r1, #7
    ldreq   r1, [r0, #0x80]
    cmpeq   r1, #7
    moveq   r1, #8
    streq   r1, [r0, #0x84]
.endif
    ldr_addr ip, TEL
    ldr     r1, [ip]
    add     r1, r1, #1
    str     r1, [ip]                @ applied
pass:
    mov     r0, r4                  @ the instruction this replaced
    bx      lr

    .align  2
/* stock UHD23_98 (canvas record 119), read out of the 5.02 image */
guard:
    .word   0x00, 3856
    .word   0x04, 2170
    .word   0x24, 3840
    .word   0x2C, 2160
    .word   0xDC, 3856
    .word   0xE4, 2170
    .word   0xF4, 6064
    .word   0xF8, 3412
    .word   0xFFFFFFFF
apply:
    .word   0x00, 5712
    .word   0x04, 3216
    .word   0xDC, 5712
    .word   0xE4, 3216
    .word   0x24, 5696
    .word   0x2C, 3206
    .word   0xFFFFFFFF
apply_input:
    .word   0xF4, 5712
    .word   0xF8, 3216
    .word   0xFFFFFFFF
