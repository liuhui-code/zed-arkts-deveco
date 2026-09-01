#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-0.3.5}"
dist_dir="$repo_root/dist"
stage_dir="$dist_dir/arkts-deveco"
archive="$dist_dir/arkts-grammar.tar.gz"
expected_sha="7fdf1154fa0a55e84d455be5fd60ca721d63c0d5f449ae1b3b106fc4b46bf1f6"

rm -rf "$dist_dir"
mkdir -p "$stage_dir/grammars"

rustup target add wasm32-wasip2
cargo build --manifest-path "$repo_root/Cargo.toml" --release --target wasm32-wasip2

cp "$repo_root/extension.toml" "$stage_dir/extension.toml"
printf '\n[lib]\nkind = "Rust"\nversion = "0.7.0"\n' >> "$stage_dir/extension.toml"
cp -R "$repo_root/languages" "$stage_dir/languages"
cp "$repo_root/LICENSE" "$stage_dir/LICENSE"
cp "$repo_root/THIRD_PARTY_NOTICES.md" "$stage_dir/THIRD_PARTY_NOTICES.md"
cp "$repo_root/target/wasm32-wasip2/release/zed_arkts_deveco.wasm" "$stage_dir/extension.wasm"

curl --fail --location --output "$archive" https://api.zed.dev/extensions/arkts/0.3.0/download
actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "Unexpected grammar archive SHA-256: $actual_sha" >&2
  exit 1
fi

tar -xOzf "$archive" ./grammars/arkts.wasm > "$stage_dir/grammars/arkts.wasm"
tar -czf "$dist_dir/zed-arkts-deveco-$version.tar.gz" -C "$stage_dir" .
echo "$dist_dir/zed-arkts-deveco-$version.tar.gz"
