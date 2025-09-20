WSL debugging notes

This workspace includes recommended VS Code settings to make Rust debugging work in WSL.

What I added:
- `.vscode/settings.json` sets `rust-analyzer.debug.engine` to use the CodeLLDB extension id: `vadimcn.vscode-lldb`.
- `.vscode/extensions.json` recommends `vadimcn.vscode-lldb` and `ms-vscode.cpptools`.
- `.vscode/launch.json` contains a minimal `type: "lldb"` configuration named "Debug executable (lldb)".

Why this is needed
- In WSL, the debug adapter must be available inside the Linux environment. On Windows, the Rust extension can use the Windows-side debuggers automatically which is why debugging worked there without extra config.

Quick steps to enable debugging inside WSL
1. Open VS Code connected to the WSL remote (use Remote - WSL extension).
2. Install the recommended extension inside the WSL remote: `vadimcn.vscode-lldb` (CodeLLDB). You can do this from the Extensions view while connected to WSL.
3. Ensure lldb DAP is available. On this machine it's provided as `lldb-dap-20` at `/usr/bin/lldb-dap-20`.
   - If the CodeLLDB extension doesn't automatically find it, create a symlink:
     sudo ln -s /usr/bin/lldb-dap-20 /usr/bin/lldb-dap
4. Build your project in debug mode:
   cargo build
5. Use the run/debug gutter icons or Run and Debug view to start the `Debug executable (lldb)` configuration.

Alternative: Use cpptools
- If you prefer GDB, install `gdb` in WSL and set `rust-analyzer.debug.engine` to `ms-vscode.cpptools`. The workspace recommends `ms-vscode.cpptools` in `extensions.json` for that path.

If you want, I can try to create the symlink automatically in this workspace (will use sudo). Let me know if you want me to do that from the terminal.
