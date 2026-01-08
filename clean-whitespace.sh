#!/usr/bin/env bash
set -u

REPO_ROOT="${SRCROOT:-$(pwd)}"
cd "$REPO_ROOT"

echo "🔹 Cleaning whitespace in Swift files..."

cleaned_any=false

find . \
  -type f \
  -name "*.swift" \
  ! -path "./.git/*" \
  ! -path "./DerivedData/*" \
  ! -path "./Pods/*" \
  ! -path "./Carthage/*" \
  ! -path "./.build/*" \
  -print0 2>/dev/null | while IFS= read -r -d '' file; do

    cleaned="$(sed -E 's/[[:space:]]+$//' "$file")"

    tmp_file="$(mktemp)"
    printf "%s" "$cleaned" > "$tmp_file"

    if ! cmp -s "$file" "$tmp_file"; then
        mv "$tmp_file" "$file"
        echo "  ✨ Cleaned: $file"
        cleaned_any=true
    else
        rm "$tmp_file"
    fi
done

if [ "$cleaned_any" = true ]; then
    echo "✅ Whitespace cleaning complete."
else
    echo "✅ No whitespace changes needed."
fi

exit 0
