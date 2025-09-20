# Link Time Optimization when combining Rust and C++
Rust’s rustc uses LLVM under the hood, and cross-language LTO only reliably works when the C/C++ toolchain (clang/llvm + lld/LLVM gold plugin) is compatible with the LLVM version used to build rustc.

# Step-by-step (WSL / Ubuntu)

1.  run `rustc --version --verbose` to get the LLVM version
output:

```
rustc 1.90.0 (1159e78c4 2025-09-14)
binary: rustc
commit-hash: 1159e78c4747b02ef996e55082b704c09b970588
commit-date: 2025-09-14
host: x86_64-unknown-linux-gnu
release: 1.90.0
LLVM version: 20.1.8
```
```
LLVM_FULL=$(rustc --version --verbose | awk -F': ' '/llvm version/{print $2}')
LLVM_MAJOR=$(printf "%s" "$LLVM_FULL" | cut -d. -f1)
echo "rustc LLVM version: $LLVM_FULL (major: $LLVM_MAJOR)"
```

2. set variables to describe the llvm version prior to installation

```
LLVM_FULL=20.1.8
LLVM_MAJOR=20
```

3. Install matching clang / lld / llvm tools

```
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh 20 # only major version are accepted
```
- even though we supplied the major version only, it happened to install 20.1.8

```
clang-20 --version
Ubuntu clang version 20.1.8 (++20250708082409+6fb913d3e2ec-1~exp1~20250708202428.132)
Target: x86_64-pc-linux-gnu
Thread model: posix
InstalledDir: /usr/lib/llvm-20/bin
```