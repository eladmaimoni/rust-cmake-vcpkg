# integrate to exisitng workspace

[integate to existing cargo workspace](https://cjycode.com/flutter_rust_bridge/guides/how-to/cargo-workspaces)

from the flutter project root dir:

```
flutter_rust_bridge_codegen create by2_ui --rust-crate-dir ../../rust/src/by2_api
```

don't forget to follow other instructions like:

- deleting the Cargo.lock file in by2_api
- adding the crate to the workspace Cargo.toml

# regenerate after rust code changes

run from the flutter project root

```
flutter_rust_bridge_codegen generate

# OR

flutter_rust_bridge_codegen generate --watch
```
