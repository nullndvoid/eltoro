//! Low-level amd64-specific functions.

/// Stops the CPU completely. Loops forever and ignores NMIs.
pub inline fn hang() noreturn {
    asm volatile ("cli");
    // Loops just in case NMIs are recieved.
    while (true) {
        asm volatile ("hlt");
    }
}

/// Used by the IDT and GDT registers.
pub const SystemTableDescriptor = packed struct {
    /// The size of the table in bytes, subtracted by 1.
    size: u16,
    /// The linear address of the GDT. Not the physical address as paging applies.
    base: u64,
};

/// Loads a new Global Descriptor table.
pub inline fn lgdt(
    /// A pointer to a GDT descriptor structure.
    gdtr: SystemTableDescriptor,
) void {
    asm volatile ("lgdt (%[gdtr])"
        :
        : [gdtr] "r" (&gdtr),
    );
}
