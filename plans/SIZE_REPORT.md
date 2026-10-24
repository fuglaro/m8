# Small Build Size Report

For the arm64 macOS build produced by:

```sh
zig build -Dsmall=true
```

`small` selects `ReleaseSmall`, explicitly omits debug symbols, and on macOS
removes local linker symbols after installation. Every m8 build is
single-threaded. The resulting Mach-O executable is **550,576 bytes / 537.7
KiB**.

## On-disk breakdown

| Area | Bytes | KiB | Share |
|---|---:|---:|---:|
| Machine code (`__text`) | 331,988 | 324.2 | 60.3% |
| C strings | 55,674 | 54.4 | 10.1% |
| Read-only constants | 25,968 | 25.4 | 4.7% |
| Unwind information | 42,776 | 41.8 | 7.8% |
| Stubs | 2,256 | 2.2 | 0.4% |
| File-backed data | 38,704 | 37.8 | 7.0% |
| Mach-O segment alignment | 41,552 | 40.6 | 7.5% |
| Link/edit metadata | 9,904 | 9.7 | 1.8% |
| Miscellaneous headers | 1,754 | 1.7 | 0.3% |

The main target is therefore ordinary generated code: about **324 KiB**.

The 54 KiB string section contains help, diagnostics, command names, provider configuration, and embedded resources. The sandbox profile alone is about 8 KiB of source text.

### A misleading detail from `size`

Mach-O reports the `__DATA` segment as approximately 294 KiB, but **262,168 bytes of that are zero-fill storage**. They consume virtual/runtime memory, not bytes in the 538 KiB file. Only about 38 KiB of `__DATA` is present on disk.

## Architectural breakdown from the split build

The split binaries provide a useful approximation of which command stacks carry weight. These are complete executables, so the differences are not additive, but they show the relative shape:

| Split command | Size | Above smallest leaf |
|---|---:|---:|
| `m8-shield-ask` | 149.9 KiB | baseline |
| `m8-render` | 149.9 KiB | baseline |
| `m8-call` | 149.9 KiB | baseline |
| `m8-riff` | 166.3 KiB | +16.3 KiB |
| `m8-providers` | 198.5 KiB | +48.6 KiB |
| `m8-munge` | 214.4 KiB | +64.5 KiB |
| `m8-providers-toy` | 246.8 KiB | +96.9 KiB |
| `m8-parse` | 262.9 KiB | +112.9 KiB |
| `m8-encode` | 279.0 KiB | +129.1 KiB |

The broad conclusions are:

1. **Codec support is the largest feature stack.**  
   `encode` and `parse` are the heaviest leaves.

2. **The toy provider is substantial.**  
   That includes the local models and Z-machine path.

3. **Munge is the next significant independent stack.**

4. **The default URL transport is nearly free.**  
   `m8-providers-url` is about 150 KiB—essentially a minimal leaf—because curl carries HTTP/TLS rather than the binary.

5. **The single binary shares a lot.**  
   The 538 KiB result is much smaller than summing the split programs because parsing, ledger handling, process plumbing, allocation, and codecs are shared and LTO can fold/internalize them.

## Link metadata and stripping

`ReleaseSmall` already passes Zig's `-fstrip`, which omits debug symbols. On
Mach-O, LLVM's machine outliner nevertheless leaves local linker symbols named
`_OUTLINED_FUNCTION_*`. Before the post-install strip, the single-threaded
artifact was 604,080 bytes and carried:

- 1,558 Mach-O symbols;
- 1,459 local symbols, overwhelmingly outlined functions;
- 34 KiB of symbol-name strings;
- 63,408 bytes of link/edit metadata.

The `small` build runs the Darwin toolchain's `strip -x` after installation.
That preserves the global and undefined symbols needed by the executable while
removing the local linker symbols:

```text
before local-symbol strip  604,080 bytes  589.9 KiB
after local-symbol strip   550,576 bytes  537.7 KiB
```

The installed executable retains 98 symbols and 9,904 bytes of link/edit
metadata, and runs normally. The additional saving is **53,504 bytes / 8.9%**.

After stripping, the remaining meaningful targets are generated
code—particularly codecs, toy/Z-Machine, and munge. The 40.6 KiB of Mach-O
alignment and roughly 42 KiB of unwind data are structural/toolchain costs
rather than obvious application bloat.
