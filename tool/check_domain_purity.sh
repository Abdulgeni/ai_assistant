#!/usr/bin/env bash
# tool/check_domain_purity.sh
#
# Clean Architecture guard: code under lib/domain may only import
#   - pure Dart core libraries (async, collection, convert, core, math, typed_data)
#   - other files under package:ai_assistant/domain/
# No Flutter, no packages, no data/presentation, no relative imports.
#
# Usage:
#   tool/check_domain_purity.sh [dir]      # default: lib/domain
#   tool/check_domain_purity.sh --self-test
#
# Exit codes: 0 clean | 1 violations | 2 usage error or self-test failure

set -uo pipefail

PKG="ai_assistant"

violations() {
  grep -rnE "^[[:space:]]*(import|export|part)[[:space:]]+['\"]" \
      --include='*.dart' "$1" 2>/dev/null \
    | grep -vE "['\"](dart:(async|collection|convert|core|math|typed_data)|package:${PKG}/domain/[^'\"]+)['\"]"
}

self_test() {
  local tmp out n rc=0
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT
  mkdir -p "$tmp/good" "$tmp/bad"
  cat > "$tmp/good/ok.dart" <<'EOF'
import 'dart:async';
import "dart:collection";
import 'package:ai_assistant/domain/entities/value_object.dart';
// import 'package:flutter/material.dart';
part of 'x.dart';
EOF
  cat > "$tmp/bad/no.dart" <<'EOF'
import 'package:flutter/foundation.dart';
import 'package:ai_assistant/data/models/foo.dart';
import 'dart:ui';
import '../relative.dart';
export 'package:dio/dio.dart';
import 'dart:io';
EOF
  out=$(violations "$tmp/good")
  if [ -n "$out" ]; then echo "SELF-TEST FAIL: clean fixture flagged:"; echo "$out"; rc=2; fi
  n=$(violations "$tmp/bad" | wc -l | tr -d ' ')
  if [ "$n" -ne 6 ]; then echo "SELF-TEST FAIL: expected 6 violations, got $n"; rc=2; fi
  if [ "$rc" -eq 0 ]; then echo "self-test passed"; fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  -h|--help)   sed -n '2,15p' "$0"; exit 0 ;;
esac

DIR="${1:-lib/domain}"
if [ ! -d "$DIR" ]; then
  echo "error: directory '$DIR' not found" >&2
  exit 2
fi

out=$(violations "$DIR")
if [ -n "$out" ]; then
  echo "✗ Domain layer imports something other than pure Dart / domain files:"
  printf '%s\n' "$out" | sed 's/^/    /'
  echo
  echo "Domain purity guard FAILED. Move the dependency behind an interface in lib/domain."
  exit 1
fi
echo "Domain purity guard passed: $DIR is pure."
