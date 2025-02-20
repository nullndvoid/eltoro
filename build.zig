const std = @import("std");

pub fn build(b: *std.Build) void {
    const output_iso = b.option(
        []const u8,
        "iso",
        "The output path to generate an ISO for. Default prefix is the zig install prefix, this may be changed using -Diso_prefix.",
    );

    const output_iso_prefix = b.option(
        []const u8,
        "iso_prefix",
        "The prefix to install the generated ISO at. Defaults to the install prefix.",
    ) orelse b.install_prefix;

    var target_query: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    const Feature = std.Target.x86.Feature;

    // Disables hardware FPUs and forces software float emulation.
    var removeSet = &target_query.cpu_features_sub;
    removeSet.addFeature(@intFromEnum(Feature.x87));
    removeSet.addFeature(@intFromEnum(Feature.mmx));
    removeSet.addFeature(@intFromEnum(Feature.sse));
    removeSet.addFeature(@intFromEnum(Feature.sse2));
    removeSet.addFeature(@intFromEnum(Feature.avx));
    removeSet.addFeature(@intFromEnum(Feature.avx2));

    var addSet = &target_query.cpu_features_add;
    addSet.addFeature(@intFromEnum(Feature.soft_float));

    const target = b.resolveTargetQuery(target_query);
    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "eltoro",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel, // Zig will compile with the memory model of a kernel in mind.
        .linkage = .static,
        .pic = false, // We don't want position independent code.
        .omit_frame_pointer = false, // Used for stack traces if I wanted to implement them.
    });

    // Disable nuisance/unsupported features for the kernel.
    kernel.root_module.red_zone = false;
    kernel.root_module.stack_check = false;
    kernel.root_module.stack_protector = false;
    kernel.want_lto = false;

    // Links functions, data etc in their own sections so Zig can remove unused code safely at link time.
    kernel.link_function_sections = true;
    kernel.link_data_sections = true;
    kernel.link_gc_sections = true;

    // Forces the page size to 4KiB to avoid adding a lot of padding for alignment purposes etc.
    kernel.link_z_max_page_size = 0x1000;

    kernel.entry = .{ .symbol_name = "kmain" };

    // Add the Limine library as a dependency.
    const limine = b.dependency("limine", .{});
    kernel.root_module.addImport("limine", limine.module("limine"));

    // Used to add SSFN support.
    kernel.addIncludePath(.{ .cwd_relative = "dist/vendor" });
    kernel.setLinkerScript(b.path("linker.ld"));

    b.installArtifact(kernel);

    if (output_iso) |iso_path|
        makeISO(output_iso_prefix, iso_path) catch unreachable;

    const run_step = b.step("run", "Runs the kernel in qemu.");

    run_step.* = std.Build.Step.init(.{
        .name = "run",
        .id = std.Build.Step.Id.run,
        .owner = kernel.step.owner,
        .makeFn = runInQemu,
    });

    run_step.dependOn(b.getInstallStep());

    // TODO: Add unit testing capabilities.
    // const exe_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_exe_unit_tests.step);
}

/// Runs the kernel in qemu.
fn runInQemu(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
    const b = step.owner;
    const install_prefix = b.install_prefix;

    try makeISO(install_prefix, ".runner");
    const alloc = b.allocator;

    const iso_path = try std.fs.path.join(
        alloc,
        &[_][]const u8{ install_prefix, ".runner.iso" },
    );

    // // TODO: Make image size configurable, possibly make this a different subcommand
    // //       or something.
    // try runProgram(
    //     alloc,
    //     &[_][]const u8{ "qemu-img", "create", iso_path, "256M" },
    //     false,
    // );

    const driveArg = try std.fmt.allocPrint(
        alloc,
        "file={s},media=cdrom",
        .{iso_path},
    );

    try runProgram(alloc, &[_][]const u8{
        // zig fmt: off
        "qemu-system-x86_64", 
        "-drive",              driveArg,
        "-display",            "sdl",
        "-cpu",                "host",
        "-machine",            "pc,accel=kvm",
        // TODO: Make this tunable.
        "-m",                  "1G",
        "-enable-kvm",
        "-boot",               "d",
        // zig fmt: on
    }, false);
}

/// Creates an ISO bootable image for the kernel. This requires git and xorriso (usually found in libisoburn).
fn makeISO(install_prefix: []const u8, iso_prefix: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const alloc = arena.allocator();

    try runProgram(
        alloc,
        &[_][]const u8{
            "git",
            "clone",
            "https://github.com/limine-bootloader/limine.git",
            "--branch=v8.x-binary",
            "--depth=1",
            "build/limine",
        },
        true,
    );

    try runProgram(
        alloc,
        &[_][]const u8{ "make", "-C", "build/limine", "-j8" },
        false,
    );

    // Setup the iso_root directory.
    try setupIsoRootDir();

    // Create the ISO file using 'xorriso'.
    const iso_filename = try std.mem.join(alloc, ".", &[_][]const u8{ iso_prefix, "iso" });
    const iso_output_path = try std.fs.path.join(alloc, &[_][]const u8{ install_prefix, iso_filename });

    try runProgram(
        alloc,
        &[_][]const u8{
            // zig fmt: off
            "xorriso", "-as", "mkisofs", "-R", "-r", "-J", "-b", "boot/limine/limine-bios-cd.bin", "-no-emul-boot", 
            "-boot-load-size", "4", "-boot-info-table", "-hfsplus", "-apm-block-size", "2048", "--efi-boot", 
            "boot/limine/limine-uefi-cd.bin", "-efi-boot-part", "--efi-boot-image", "--protective-msdos-label",
            "build/iso_root", "-o", iso_output_path
            // zig fmt: on
        },
        false,
    );
}

/// Sets up the iso_root directory under ./build. This copies a variety of files into the required structure.
fn setupIsoRootDir() !void {
    var cwd = std.fs.cwd();

    // Setup the ISO root directory, copy the relevant files in.
    var boot_dir = try cwd.makeOpenPath("build/iso_root/boot", .{});
    defer boot_dir.close();

    var output_dir = try cwd.openDir("zig-out/bin", .{});
    defer output_dir.close();

    try output_dir.copyFile("eltoro", boot_dir, "eltoro", .{});

    var boot_limine_subdir = try boot_dir.makeOpenPath("limine", .{});
    defer boot_limine_subdir.close();

    var limine_dir = try cwd.makeOpenPath("build/limine", .{});
    defer limine_dir.close();

    // A list of files to copy into build/iso_root/boot/limine.
    const required_limine: [3][]const u8 = [_][]const u8{ "limine-bios.sys", "limine-bios-cd.bin", "limine-uefi-cd.bin" };

    for (required_limine) |filename| {
        try limine_dir.copyFile(filename, boot_limine_subdir, filename, .{});
    }

    // Copy the provided config file over.
    var dist_dir = try cwd.openDir("dist", .{});
    defer dist_dir.close();

    try dist_dir.copyFile("limine.conf", boot_limine_subdir, "limine.conf", .{});

    var efi_boot_dir = try cwd.makeOpenPath("build/iso_root/EFI/BOOT", .{});
    defer efi_boot_dir.close();

    try limine_dir.copyFile("BOOTX64.EFI", efi_boot_dir, "BOOTX64.EFI", .{});
    try limine_dir.copyFile("BOOTIA32.EFI", efi_boot_dir, "BOOTIA32.EFI", .{});
}

/// Attempts to run a child process. Gives an informative error if the program does not exist.
fn runProgram(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    /// Should program errors be ignored or printed to console?
    ignore_program_errors: bool,
) !void {
    const command = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        // Stops crashes when programs output a lot of content.
        .max_output_bytes = std.math.maxInt(usize),
    }) catch |err| switch (err) {
        std.process.Child.RunError.FileNotFound => {
            std.log.err("Could not run command {s}! Please check it exists on the system path :(\n", .{argv[0]});
            return err;
        },
        else => {
            return err;
        },
    };

    switch (command.term) {
        .Exited => |exit_code| {
            if (exit_code != 0 and !ignore_program_errors) {
                std.debug.print("Process {s} exited with status code {d}\n", .{ argv[0], exit_code });
                std.debug.print("stderr:\n\n{s}\n", .{command.stderr});

                return error.CommandFailed;
            }
        },
        else => {},
    }
}
