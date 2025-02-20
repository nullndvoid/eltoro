const limine = @import("limine");
const std = @import("std");
const amd64 = @import("arch/amd64/cpu.zig");
const gdt = @import("arch/amd64/gdt.zig");
const term = @import("term/terminal.zig");

const assert = std.debug.assert;

pub export var base_revision: limine.BaseRevision linksection(".limine_requests") = .{
    .revision = 3,
};

// physical address = logical_address - offset
// TODO: Comprehend what on earth Limine is doing, get a pen and paper out.
pub export var hhdm_request: limine.HhdmRequest linksection(".limine_requests") = .{};
pub export var memmap_request: limine.MemoryMapRequest linksection(".limine_requests") = .{};

export fn kmain() callconv(.C) noreturn {
    if (!base_revision.is_supported() or
        memmap_request.response == null or
        hhdm_request.response == null)
    {
        amd64.hang();
    }

    // TODO: Support scalable screen font and use with Iosevka because it is lush.
    _ = term.Terminal.initialise();
    term.clear(0x082222);
    term.print("Reading memory map from Limine...\n", .{});

    readMemMap();
    gdt.initialise();
    amd64.hang();
}

fn readMemMap() void {
    var memmap = memmap_request.response.?;
    var usable_memory: usize = 0;
    for (memmap.entries()) |entry| {
        term.print("{any}\n", .{entry});
        if (entry.kind == .usable) usable_memory += entry.length;
    }

    term.print("Got {d} bytes usable memory!\n", .{usable_memory});
    term.print("{any}\n", .{hhdm_request.response.?});
}
