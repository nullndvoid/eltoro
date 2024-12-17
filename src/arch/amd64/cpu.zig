//! Low-level amd64-specific functions.

/// Stops the CPU completely. Loops forever and ignores NMIs.
pub inline fn hang() noreturn {
    asm volatile ("cli");
    // Loops just in case NMIs are recieved.
    while (true) {
        asm volatile ("hlt");
    }
}
