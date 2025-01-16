//! Handles setting up a small GDT for AMD64.
const amd64 = @import("cpu.zig");

/// Flags for use with segment descriptors.
const SegmentDescriptorFlags = packed struct(u4) {
    /// Available for use by system software.
    _reserved: bool,
    /// The descriptor defines a 64-bit code segment. DB MUST BE CLEAR IF SET.
    long_code_segment: bool,
    /// Set this to 0 if `long_code_segment` is set. 0 = 16-bit, 1 = 32-bit.
    db_flag: bool,
    /// Sets the size the limit value should be scaled by. 0 = 1-byte blocks, 1 = 4KiB blocks (page granularity).
    granularity_flag: bool,

    pub fn init(flags: u4) SegmentDescriptorFlags {
        return flags;
    }
};

/// The segment descriptor as laid out in memory. The SegmentDescriptor struct
/// can be used to create this raw version.
const RawSegmentDescriptor = packed struct(u64) {
    /// Ignored in 64-bit mode. Maximum addressable unit (bytes or 4KiB pages).
    limit_low: u16,
    /// Ignored in 64-bit mode. The linear address where the segment should begin.
    base_low: u24,
    /// Contains some metadata, we don't care about most of this right now.
    access_byte: SegmentDescriptorAccess,
    /// Upper 4 bits of the limit. Ignored in 64-bit mode.
    limit_high: u4,
    /// Boolean flags to set on the segment descriptor.
    flags: SegmentDescriptorFlags,
    /// Ignored in 64-bit mode. Uppermost byte of the base address.
    base_high: u8,

    /// Returns a typical or default descriptor for my use case.
    pub fn init(
        /// The size of the segment, ignored in long mode.
        limit: u20,
        /// The location of byte 0 of the segment in the 4GB linear address space.
        base: u32,
        /// Metadata which says how the segment can be accessed, as well as its privilege level.
        access_byte: SegmentDescriptorAccess,
        /// A bit field of flags.
        flags: SegmentDescriptorFlags,
    ) RawSegmentDescriptor {
        comptime {
            const base_high8: u8 = @truncate((base & (0xff << 24)) >> 24);
            const base_low24: u24 = base & ((1 << 24) - 1);

            const limit_low16: u16 = limit & ((1 << 16) - 1);
            const limit_high4: u4 = @truncate((limit & 0xf0000) >> 16);

            return RawSegmentDescriptor{
                // Set the limit, getting the lower 16 bits and upper nibble.
                .limit_low = limit_low16,
                .limit_high = limit_high4,

                // Set the base, separating the lower 3 bytes and the upper byte.
                .base_low = base_low24,
                .base_high = base_high8,

                .access_byte = access_byte,
                .flags = flags,
            };
        }
    }
};

/// Extended system segment descriptor for usage with TSS, LDT etc.
/// Available types are 0x2, 0x9 and 0xB because we are in long mode.
///
/// # Notes
///
/// The available types of system segments in long mode are as follows:
///
/// * 0x2: LDT
/// * 0x9: 64-bit TSS (available)
/// * 0xB: 64-bit TSS (busy)
///
/// This will be enforced in `init`.
const SystemSegmentDescriptor = packed struct(u128) {
    /// Ignored in 64-bit mode. Maximum addressable unit (bytes or 4KiB pages).
    limit_low: u16,
    /// The linear address where the segment should begin. Bytes from index 16:39. Forms part of a 64-bit linear address.
    base_low: u24,
    /// Contains some metadata, we don't care about most of this right now.
    access_byte: SystemSegmentDescriptorAccess,
    /// Upper 4 bits of the limit. Ignored in 64-bit mode.
    limit_upper: u4,
    /// Boolean flags to set on the segment descriptor.
    flags: SegmentDescriptorFlags,
    /// Byte from index 56:63. Forms part of a 64-bit linear address.
    base_middle: u8,
    /// The 32 most significant bits of base address. Used for addressing the TSS etc with a 64-bit linear address.
    base_high: u32,
    /// A reserved section.
    _reserved: u32,

    pub fn init(
        /// The size of the segment, ignored in long mode.
        limit: u20,
        /// The location of byte 0 of the segment in the **64-bit** linear address space.
        base: u64,
        /// Metadata which says how the segment can be accessed, as well as its privilege level.
        access_byte: SystemSegmentDescriptorAccess,
        /// A bit field of flags.
        flags: SegmentDescriptorFlags,
    ) SystemSegmentDescriptor {
        comptime {
            const base_top32: u32 = @truncate((base & (0xffffffff << 32)) >> 32);
            const base_mid8: u8 = @truncate((base & (0xff << 24)) >> 24);
            const base_low24: u24 = base & ((1 << 24) - 1);

            const limit_low16: u16 = limit & ((1 << 16) - 1);
            const limit_high4: u4 = @truncate((limit & 0xf0000) >> 16);

            return SystemSegmentDescriptor{
                .limit_low = limit_low16,
                .limit_upper = limit_high4,

                .base_low = base_low24,
                .base_middle = base_mid8,
                .base_high = base_top32,

                .access_byte = access_byte,
                .flags = flags,
            };
        }
    }
};

/// Some access information associated with the segment, this is mostly unused in our case.
const SegmentDescriptorAccess = packed struct(u8) {
    /// Was the segment accessed?
    accessed: bool,
    /// Set if readable for a code segment and if writable for a data segment. Typically set to 1.
    read_write: bool,
    /// Code segments: Conforming bit (DPL respected or is execution allowed to far jmp to lower priv levels).
    /// Data segments: 1: grows down, 0: grows up.
    conforming_expand_down: bool,
    /// Is the segment a code segment or data segment?
    is_code: bool,
    /// Flag indicating whether the descriptor is for a system segment or a code/data segment.
    system_segment: bool,
    /// Controls access to the segment. 0 is highest privileged.
    privilege_level: u2,
    /// Must be set to 1 for any valid segment. Unset if the segment is not present in memory.
    /// If unset, arbitrary bits may be stored in 0:31 of first doubleword and 0:7, 16:31 of
    /// second doubleword.
    ///
    /// Generates a segment not present exception if loaded whilst this is false.
    present_bit: bool,

    pub fn init(byte: u8) SegmentDescriptorAccess {
        return byte;
    }
};

/// Used in system segment descriptors. Defines the type of the system segment.
const SystemSegmentDescriptorType = enum(u4) { LDT = 0x2, LONG_TSS_AVAIL = 0x9, LONG_TSS_BUSY = 0xB };

/// The access byte for the system segments are slightly different as the first 4 bits define the type.
const SystemSegmentDescriptorAccess = packed struct(u8) {
    system_segment_type: SystemSegmentDescriptorType,
    /// Whether the segment is a system segment or code/data. This should be set to
    /// false in this case, how obvious!
    system_segment: bool,
    /// Controls access to the segment.
    privilege_level: u2,
    /// Must be set to 1 for any valid segment. Unset if the segment is not present in memory.
    /// If unset, arbitrary bits may be stored in 0:31 of first doubleword and 0:7, 16:31 of
    /// second doubleword.
    ///
    /// Generates a segment not present exception if loaded whilst this is false.
    present_bit: bool,
};

/// Segment limits are in terms of 4KiB (page granularity). Reserved bits are ignored.
/// To see the meanings of the below fields, write them out as binary and see which bits are set.
var gdt = [_]u64{
    RawSegmentDescriptor.init(
        0,
        0,
        SegmentDescriptorAccess.init(0),
        SegmentDescriptorFlags.init(0),
    ),
    RawSegmentDescriptor.init(
        0xFFFFF,
        0,
        SegmentDescriptorAccess.init(0x9A),
        SegmentDescriptorFlags.init(0xA),
    ),
    RawSegmentDescriptor.init(
        0xFFFFF,
        0,
        SegmentDescriptorAccess.init(0x92),
        SegmentDescriptorFlags.init(0xC),
    ),
    RawSegmentDescriptor.init(
        0xFFFFF,
        0,
        SegmentDescriptorAccess.init(0xFA),
        SegmentDescriptorFlags.init(0xA),
    ),
    RawSegmentDescriptor.init(
        0xFFFFF,
        0,
        SegmentDescriptorAccess.init(0xF2),
        SegmentDescriptorFlags.init(0xC),
    ),

    // TODO: Add TSS entries for allowing entering into user mode at runtime.
    // These 2 entries will be required because the system segment is larger,
    // this is OK because we can bitcast as required.
    RawSegmentDescriptor.init(
        0,
        0,
        SegmentDescriptorAccess.init(0),
        SegmentDescriptorFlags.init(0),
    ),
    RawSegmentDescriptor.init(
        0,
        0,
        SegmentDescriptorAccess.init(0),
        SegmentDescriptorFlags.init(0),
    ),
};

/// These are the GDT offsets for our table entries.
pub const SegmentSelector = enum(u16) {
    null_desc = 0x00,
    ks_code = 0x08,
    ks_data = 0x10,
    us_code = 0x18,
    us_data = 0x20,
    /// TODO: Add the TSS so we can switch to user mode.
    tss = 0x28,
};

/// Initalises the GDT as well as TSS later (TODO: Setup the TSS).
pub fn initialise() void {
    loadGdt();
}

// Load the GDT and reloads code and data segment registers.
fn loadGdt() void {
    amd64.lgdt(.{
        .size = @sizeOf(@TypeOf(gdt)) - 1,
        .base = @intFromPtr(gdt[0]),
    });

    // Perform a far jump to reload the code segment.
    // Data segment registers are set to the null descriptor as they are not used in 64-bit mode.
    asm volatile (
        \\ push %[kernel_code]
        \\ lea 1f(%rip), %rax
        \\ push %rax
        \\ lretq
        \\
        \\ 1:
        \\     mov %[null_desc], %ax
        \\     mov %ax, %ds
        \\     mov %ax, %es
        \\     mov %ax, %fs
        \\     mov %ax, %gs
        \\     mov %ax, %ss
        :
        : [kernel_code] "i" (SegmentSelector.kernel_code),
          [null_desc] "i" (SegmentSelector.null_desc),
        : "rax", "memory"
    );
}
