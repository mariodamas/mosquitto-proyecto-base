The following packages can be used to add features to mosquitto. All of them
are optional.

* openssl
* c-ares (for DNS-SRV support, disabled by default)
* tcp-wrappers (optional, package name libwrap0-dev)
* libwebsockets (optional, disabled by default, version 2.4 and above)
* cJSON (optional but recommended, for dynamic-security plugin support, and
  JSON output from mosquitto_sub/mosquitto_rr)
* libsystemd-dev (optional, if building with systemd support on Linux)
* On Windows, a pthreads library is required if threading support is to be
  included.
* xsltproc (only if building from git)
* docbook-xsl (only if building from git)

To compile, run "make", but also see the file config.mk for more details on the
various options that can be compiled in.

Where possible use the Makefiles to compile. This is particularly relevant for
the client libraries as symbol information will be included.  Use cmake to
compile on Windows or Mac.

If you have any questions, problems or suggestions (particularly related to
installing on a more unusual device) then please get in touch using the details
in README.md.

## Developer Setup (VS Code + clangd)

### Why This Matters

**clangd** is a language server that provides real-time static analysis in VS Code. It catches common bugs, security issues, and code quality problems *before you commit*.

For this to work, clangd needs:
1. **`compile_commands.json`** — tells clangd how to compile each `.c` file
2. **`.clang-tidy`** — configuration for which checks to run
3. **VS Code + clangd extension** — your IDE

### Quick Start

```bash
./scripts/setup-dev-env.sh
```

This script will:
- Run CMake to generate `compile_commands.json`
- Copy it to the project root (where clangd expects it)
- Create/verify `.clang-tidy` configuration
- Check that VS Code and clangd extension are installed
- Show installation instructions if anything is missing

**Expected output:**
```
Setting up Mosquitto dev environment for VS Code + clangd...
✓ compile_commands.json copied to project root
✓ .clang-tidy already exists
✓ VS Code found
⚠ Please ensure clangd extension is installed in VS Code:
  1. Open VS Code
  2. Extensions (Ctrl+Shift+X / Cmd+Shift+X)
  3. Search 'clangd' and install

Setup complete!
Open any .c file in VS Code to see analysis warnings.
```

### Manual Setup (Alternative)

If you prefer to set up manually:

1. **Generate compilation database:**
   ```bash
   mkdir -p build && cd build
   cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=1
   cp compile_commands.json ../
   cd ..
   ```

2. **Verify `.clang-tidy` exists in project root** (should be present; if not, see the script above)

3. **Install clangd extension in VS Code:**
   - Open VS Code
   - Press `Ctrl+Shift+X` (or `Cmd+Shift+X` on macOS)
   - Search for `clangd` (by LLVM Extensions)
   - Click Install

### How to Use

Once setup is complete:
1. Open any `.c` or `.h` file in VS Code
2. clangd will analyze it automatically
3. Warnings appear as underlines in the editor
4. Hover over warnings to see details
5. Fix issues before committing

### Troubleshooting

**Q: I'm getting "compile_commands.json not found" or no warnings appear**

A: Run `./scripts/setup-dev-env.sh` again, or verify that `compile_commands.json` exists in the project root:
```bash
ls -la compile_commands.json
```
If it doesn't exist, check that CMake ran successfully:
```bash
cat build/compile_commands.json | head -5
```

**Q: Warnings aren't showing even though clangd is installed**

A: Try reloading VS Code:
- Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on macOS)
- Type `reload window` and press Enter
- Or close and reopen VS Code

**Q: I changed the build configuration; now clangd shows outdated warnings**

A: Regenerate the compilation database:
```bash
./scripts/setup-dev-env.sh
```
Then reload VS Code.

**Q: The script fails with cmake errors**

A: Ensure you have CMake installed:
```bash
cmake --version
```
If not installed, install it (available in most package managers or from https://cmake.org/download/).

### Configuration

The `.clang-tidy` file in the project root controls which checks clangd runs. Default configuration includes:
- **clang-diagnostic-\***: Compiler warnings
- **clang-analyzer-\***: Static analysis checks
- **cert-\***: CERT secure coding rules
- **bugprone-\***: Common bug patterns

To customize, edit `.clang-tidy` and reload VS Code. See [clang-tidy documentation](https://clang.llvm.org/extra/clang-tidy/checks/list.html) for available checks.
