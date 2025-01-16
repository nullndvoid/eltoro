const limine = @import("limine");
const std = @import("std");
const amd64 = @import("arch/amd64/cpu.zig");
const gdt = @import("arch/amd64/gdt.zig");
const term = @import("term/terminal.zig");

const assert = std.debug.assert;

pub export var base_revision: limine.BaseRevision linksection(".limine_requests") = .{
    .revision = 2, // TODO: Support revision 3, this is just nabbed from AndreaOrru/zen.
};

export fn kmain() callconv(.C) noreturn {
    if (!base_revision.is_supported()) {
        amd64.hang();
    }

    // TODO: Support scalable screen font and use with Iosevka because it is lush.
    _ = term.Terminal.initialise();
    term.clear(0x000000);

    gdt.initialise();
    amd64.hang();
}
