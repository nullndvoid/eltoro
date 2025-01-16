//! Handles setting up a small TSS for AMD64. This is used to allow returning to
//! ring 0 code from ring 3. This should be done per CPU, and placed into the GDT.

pub const TSS = packed struct {};
