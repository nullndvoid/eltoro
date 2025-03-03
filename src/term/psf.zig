//! PC Screen Font Support (version 2 only).

/// The magic bytes for a version 2 PSF.
pub const psf2_font_magic = 0x864ab572;

/// The file header for a version 2 PSF.
pub const Psf2FontHeader = struct {
    /// Magic bytes to identify the font as PSF.
    magic: u32,
    /// Should be set to 0 for a version 2.
    version: u32,
    /// The offset of the bitmaps in the file.
    header_size: u32,
    /// Set to 0 if there is no unicode table.
    flags: u32,
    /// The number of glyphs defined.
    num_glyphs: u32,
    /// How big each glyph is.
    bytes_per_glyph: u32,
    /// The height of a glyph in pixels.
    height: u32,
    /// The width of a glyph in pixels.
    width: u32,
};

