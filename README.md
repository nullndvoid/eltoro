# eltoro

Hobby 'kernel' project in Zig. Uses the Limine bootloader because I like it.

## Build-Time Dependencies

* xorriso (typically provided by libisoburn)
* git
* make

## Compilation

```sh
zig build
zig build -Diso=output -Diso_prefix=/path/to/prefix
```

The outputted ISO file is bootable and uses Limine to boot the kernel ELF file. Note that by default the `iso_prefix` is equal to Zig's, which is typically `zig-out/bin`.

## Running In Qemu

**Requires qemu to be installed on your system!**

```sh
zig build run
```

or manually, like so (specifying other required arguments):

```sh
zig build -Diso=isofile -Diso_prefix=path/to
qemu-system-x86_64 -cdrom path/to/isofile.iso
```

## License

See [LICENSE](./LICENSE)
