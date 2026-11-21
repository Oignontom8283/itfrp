# itfrp

Install Rust correctly on Windows.

One PowerShell script that sets up everything a Rust developer needs, the way it is meant to be set up:

- **rustup**, with `rustc`, `cargo`, `rustfmt` and `clippy`, and the `stable` toolchain as the default
- the **Microsoft C++ build tools** that Rust needs to link programs
- `rust-src` and `rust-analyzer`, so that editors understand the standard library
- the extra **targets** you ask for (`wasm32-unknown-unknown`, `aarch64-pc-windows-msvc`, ...)

It needs Windows 10 or 11 with `winget` and `curl`, which Windows has by default.

## Use

```powershell
irm https://raw.githubusercontent.com/Oignontom8283/itfrp/main/install.ps1 | iex
```

It asks you to accept the terms of what it installs (Microsoft's for the build tools, Rust's licences) before it does anything.

To answer yes to every question, or to give options, call it like this:

```powershell
iex "& { $(irm https://raw.githubusercontent.com/Oignontom8283/itfrp/main/install.ps1) } --yes --target wasm32-unknown-unknown"
```

## When Rust is already installed

The script looks for a Rust that is already there, however it was installed (rustup, the stand-alone installer) and even if it is half-installed or broken, and asks what to do:

1. **Keep it and update it** (only when it is healthy)
2. **Install it again from scratch**, overwriting the current settings
3. **Uninstall Rust**
4. **Cancel**

Your projects, the tools you installed with `cargo install`, your cargo configuration and your crates.io login are never touched. When uninstalling, `--wipe` also removes them (the whole cargo folder).

A Rust installed by something else (scoop, chocolatey...) is reported but left alone.

## Options

| Option | |
| --- | --- |
| `--yes`, `-y` | Answers yes to every question. With a Rust already there: a healthy one is kept and updated, a broken one is installed again. |
| `--keep` | A Rust is already there: keep it and update it. |
| `--reinstall` | A Rust is already there: remove it and install it again. |
| `--uninstall` | Remove Rust and install nothing. |
| `--wipe` | With `--uninstall`: also remove the whole cargo folder. |
| `--target <list>` | Targets to add, separated by commas. |
| `--toolchain <name>` | Toolchain to install and make the default (default: `stable`). |
| `--profile <name>` | `minimal`, `default` or `complete` (default: `default`). |
| `--skip-msvc` | Does not install the C++ build tools. |
| `--dry-run` | Shows what would be done and changes nothing. |

With PowerShell parameters instead of the `--` style: `-Yes`, `-Keep`, `-Reinstall`, `-Uninstall`, `-Wipe`, `-Target`, `-Toolchain`, `-RustProfile`, `-SkipMsvc`, `-DryRun`.

The environment variables `ITFRP_YES=1`, `ITFRP_TARGET`, `ITFRP_TOOLCHAIN` and `ITFRP_PROFILE` do the same, for when the script is piped and options are awkward to pass.

## How it stays safe

- Nothing is changed before every question has been answered.
- `rustup-init.exe` is checked against the checksum that Rust publishes next to it before it runs. The build tools come from `winget`, which checks them itself.
- At the end a small program is compiled and run, to prove that the linker works.
- Piped into `iex`, it leaves no function or variable in your PowerShell session, and never closes your terminal.

## Licence

MIT.
