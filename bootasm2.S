# When the PC starts, the processor is essentially emulating an 8086 processor, i.e. 
# a 16-bit processor.  So our initial boot loader code is 16-bit code that will 
# eventually switch the processor into 32-bit mode.

# This code is linked to assume a starting address of 0x7C00 which is where the BIOS
# will load a boot segment.

.code16                         # Assemble for 16-bit mode
.globl start
start:
    jmp     real_start

# Write to the console using BIOS.
# 
# Input: SI contains the address of the null-terminated string to be displayed

cons_write:
    movb    $0x0e, %ah           # 0x0e is the INT 10h BIOS call to output the value contained in AL to screen

cons_write_rpt:
    movb    (%si), %al          # Load the byte at the location contained in the SI register into AL   
    inc     %si                 # Add 1 to the value in SI
    cmp     $0, %al             # Compare the value in AL with 0
    jz      cons_write_done     # If it is zero, then we are done
    int     $0x10               # Output the character in AL to the screen
    jmp     cons_write_rpt      # and continue

cons_write_done:                # Something that is called will never return 
    ret                         # until a 'ret' instruction is encountered.  Labels do 
                                # not give a program any structure.  They just give a 
                                # memory location a name that we can use in our code. 

cons_write_crlf:
    movb    $0x0e, %ah          # Output CR
    movb    $0x0d, %al
    int     $0x10
    movb    $0x0a, %al          # Output LF
    int     $0x10
    ret

cons_writeline:
    call    cons_write
    call    cons_write_crlf
    ret    

convert_sector_int:
    xorw    %ax, %ax            # %ax stores result

convert_sector_int_loop:
    movb    (%si), %bl          # (%si) is character in sector_user_input
    testb   %bl, %bl            # Is Null-terminator?
    jz      convert_sector_int_done

    subb    $48, %bl            # 48 ASCII is '0'
    imul    $10, %ax            # Multiply by 10 to convert to Integer
    addw    %bx, %ax            # Add to result
    inc     %si
    jmp     convert_sector_int_loop

convert_sector_int_done:
    ret

cons_pause:
    movb    $0x00, %ah
    int     $0x16               # Get any input
    ret

# Output the 16-bit value in BX to the screen has a 4 digit hex value	
#
# Input:  BX = Value to output	

HexChars:	.ascii "0123456789ABCDEF"

hex_padding:
    .word   0

cons_write_hex:         
    pushw   %ax                 # Save registers
    pushw   %cx
    pushw   %si                 

	movw	(hex_padding), %cx  # Determines if 2 or 4 hex chars should be outputted
    movb    $0x0e, %ah
    subw    $4, %cx             # Subtract max 4 chars
    cmp     $0, %cx             # Equal means we are using 4 chars
    je      start_hexloop
    rol     $8, %dx             # Remove first two bits as hex_padding should be 2 here
    movw    (hex_padding), %cx
    jmp     hexloop

start_hexloop:
    movw    $4, %cx
	
hexloop:
    rol     $4, %dx
    movw    %dx, %si
    and     $0x000f, %si
    movb    HexChars(%si), %al
	int		$0x10
	loop	hexloop

    popw    %si
    popw    %cx
    popw    %ax
	ret

# Output the value passed on the stack to the screen using the specified base
#

#define     number      6
#define     base        4

#define     endofstring -2

cons_write_number:
    pushw   %bp                 # Save existing frame pointer
    movw    %sp, %bp            # Setup our frame pointer
    subw    $18, %sp            # Reserve space for our string buffer
    pushw   %ax                 # Save the registers we will trash
    pushw   %bx
    pushw   %cx
    pushw   %dx
    pushw   %si
    pushw   %di

    movw    %bp, %si
    subw    $3, %si
    movb    $0, endofstring(%bp) # Insert end of string indicator (0)    
    movw    number(%bp), %ax
	
getdigit:
	xor		%dx, %dx            # Divide number by base
	movw	base(%bp), %cx
	div		%cx
    movw    %dx, %di            # Convert remainder to hex character
    movb    HexChars(%di), %dl  # and store in buffer
	movb	%dl, (%si)
	dec		%si
	cmpw	$0, %ax             # Have we extracted all digits?
	jne		getdigit
	inc		%si
	call	cons_write          # Output the string

    popw    %di                 # Restore the registers
    popw    %si
    popw    %dx
    popw    %cx
    popw    %bx
    popw    %ax
    movw    %bp, %sp            # Delete the local variables
    popw    %bp
    ret     $4                  # Return, removing paramters from stack

cons_write_space:
    movb    $0x0e, %ah
    movb    $0x20, %al          # Output Space
    int     $0x10
    ret

real_start:
    movb    %dl, (boot_device)  # Boot device number is passed in DL from BIOS. Save it here since DL might get trashed

    movw    $boot_message, %si  # Display our boot message
    call    cons_writeline

    movw    $booted_from_msg, %si
    call    cons_write

    movb    (boot_device), %dl
    cmp     $0x80, %dl
    jge     harddrive

    movw    $fd, %si
    jmp     finish

harddrive:
    movw    $hd, %si

finish:
    call    cons_writeline
    movw    (sector_input_message), %si
    # If value from address isn't pointed to before pointing to the direct value,
    # the first character's ASCII value is warped by some random offset

sector_user_input:
    .space  5                   # 4-digit sector number (5 for Null-terminated string)
sector_num_input:
    .space  5

sector_input_prompt:
    movw    $sector_input_message, %si
    call    cons_write
    mov     $sector_user_input, %di
    call    sector_input_start
    call    cons_write_crlf

    movw    $sector_num_message, %si
    call    cons_write
    mov     $sector_num_input, %di
    call    sector_input_start
    call    cons_write_crlf

    jmp     display_sector
    
sector_input_start:
    xorw    %cx, %cx            # Set %cx to 0 for length counting

sector_input_loop:
    cmp     $4, %cx             # Input exceeds 4 characters
    jae     sector_input_done

    movb    $0x00, %ah          # Get character
    int     $0x16

    cmp     $0x08, %al          # Check if Backspace
    je      sector_input_backspace
    cmp     $0x0d, %al          # Check if CR (Enter)
    je      sector_input_done
    cmp     $0x30, %al          # ASCII 0-9 for exclusively numbers
    jl      sector_input_loop
    cmp     $0x39, %al
    jg      sector_input_loop

    movb    $0x0e, %ah          # Output user input to screen
    int     $0x10
    stosb                       # Store character in sector_user_input pointed to by %di
    inc     %cx
    jmp     sector_input_loop

sector_input_backspace:
    cmp     $0, %cx             # Are we at the start of the input?
    je      sector_input_loop

    movb    $0x0e, %ah          # Move back 1 character
    int     $0x10
    movb    $0x20, %al          # Space to clear old character
    int     $0x10
    movb    $0x08, %al          # Move back 1 character
    int     $0x10

    dec     %cx                 # Decrement counters
    dec     %di
    jmp     sector_input_loop

sector_input_done:
    movb    $0, %al             # Null-termitate string
    stosb  
    ret

sector_start_num:
    .word   0
num_sectors:                    # Number of Sectors (n)
    .word   0
sector_count:                   # Sector count  (0-num_sectors, step 1)
    .word   0
sector_offset:                  # Sector offset (0-512, step 16)
    .word   0
data_offset:                    # Sector's data offset (0-512, step 1)
    .word   0
line_count:                     # Line count (0-16, step 1)
    .byte   0

display_sector:
    movw    $sector_user_input, %si
    call    convert_sector_int  # Convert sector_user_input to number and store in %ax
    movw    %ax, (sector_start_num)
    movw    %ax, %bx
    pushw   %bx                 # Ensure value does not get altered

    movw    $sector_num_input, %si
    call    convert_sector_int  # Number of sectors to read now stored in %ax
    cmp     $0, %ax
    jne     display_sector_cont

set_appropriate_num:
    movw    $1, %ax

display_sector_cont:
    movw    %ax, (num_sectors)  # Store for later
    popw    %bx                 # Retrieve saved value

    movw    $disk_address_packet, %si
    movw    %ax, 2(%si)                 # Blocks to read
    movw    $0xd000, 4(%si)             # Read into
    movw    %bx, 8(%si)                 # First block to read
    movb    $0x42, %ah                  # LBA reading
	movb	(boot_device), %dl          # Drive
    int     $0x13                       # Read the disk
    jc      sector_read_error	        # The carry flag will be set if an error occured

    movw    $0xd000, (data_offset) # Offset to the read data
    movw    $0, (sector_count)
    
display_sector_start:
    call    cons_write_crlf
    movw    $sector_contents_message, %si
    call    cons_write

    movw    (sector_count), %ax
    movw    (sector_start_num), %bx
    addw    %ax, %bx
    pushw   %bx
    pushw   $10
    call    cons_write_number
    call    cons_write_crlf
    call    cons_write_crlf

    movw    $0, (sector_offset) # Sector offset set to 0
    movb    $0, (line_count)    # Line count set to 0
    
display_sector_loop:
    xorw    %bx, %bx
    movb    (line_count), %al   # Get current line_count
    cmpb    $16, %al            # 16 lines been displayed?
    je      display_sector_wait # Wait for user input

    inc     %al                 # Add 1 to it
    movb    %al, (line_count)   # Store the value

    movw    (sector_offset), %dx
    movw    $4, (hex_padding)
    call    cons_write_hex
    call    cons_write_space

    movw    $16, %cx

display_line_loop:
    movw    (data_offset), %si
    xorw    %ax, %ax            # Clear %ax
    lodsb                       # Load into %al
    movw    %ax, %dx
    movb    $2, (hex_padding)
    call    cons_write_hex
    call    cons_write_space

    addw    $1, (data_offset)   # Increment current address by 1
    subw    $1, %cx             # Decrement number of bytes left in line
    cmpw    $0, %cx
    jg      display_line_loop

    subw    $16, (data_offset)  # Go back 16 bytes
    movw    (data_offset), %si
    movw    $16, %cx            # 16 bytes per line

display_line_loop_ascii:
    lodsb                       # Load into %al
    cmp     $32, %al            # ASCII check for special actions
    jl      replace_ascii
    jmp     display_ascii_byte

replace_ascii:
    movb    $0x5f, %al          # ASCII for '_'

display_ascii_byte:
    movb    $0x0e, %ah
    int     $0x10               # Output ASCII
    loop    display_line_loop_ascii 

display_sector_done:
    addw    $16, (data_offset)  # Go forward 16 bytes
    addw    $16, (sector_offset) # Move offset to next line 
    call    cons_write_crlf    

    cmpw    $512, (sector_offset) # Have we displayed entire Section?
    jb      display_sector_loop

    call    display_sector_pause
    movw    (sector_count), %ax # Increment sector_count
    inc     %ax
    movw    %ax, (sector_count)

    cmpw    (num_sectors), %ax  # Compare sector_count to num_sectors
    je      repeat_display_sector_program      
    jmp     display_sector_start

repeat_display_sector_program:
    call    cons_write_crlf     # New line
    jmp     sector_input_prompt # Restart sector read loop

display_sector_wait:
    call    display_sector_pause
    jmp     reset_line_count

display_sector_pause:
    movw    $sector_display_wait_message, %si
    call    cons_write
    call    cons_pause
    call    cons_write_crlf
    ret

reset_line_count:
    movb    $0, (line_count)   # Reset line_count to 0
    jmp     display_sector_loop

sector_read_error:
    call    cons_write_crlf
    movw    $sector_read_error_message, %si
    call    cons_writeline
    jmp     sector_input_prompt

endless_loop:                   # Loop forever more
    jmp     endless_loop   

# Program data

boot_device:
    .byte   0

disk_address_packet:
    .byte   0x10
    .byte   0
    .word   0
    .long   0
    .long   0
    .long   0

boot_message:
    .string "Boot Loader Stage 2 loaded"             
booted_from_msg:
    .string "Booting from "
fd: .string "floppy disk"
hd: .string "hard drive"

sector_input_message:
    .string "Enter the starting sector number to read: "
sector_num_message:
    .string "Enter the number of sectors to read: "
sector_contents_message:
    .string "Contents of sector "
sector_display_wait_message:
    .string "Press a key to continue..."
sector_read_error_message:
    .string "Error: Sector/Range cannot be read."
