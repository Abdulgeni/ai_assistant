#!/usr/bin/env bash
# tool/check_no_physical_directions.sh
#
# RTL guard: fails if Dart code under the target directory uses physical
# (left/right) layout APIs. Use the *Directional / start-end equivalents.
#
# Usage:
#   tool/check_no_physical_directions.sh [dir]     # default: lib
#   tool/check_no_physical_directions.sh --self-test
#
# Suppress a single line (rare, e.g. a third-party API that is physical):
#   foo(left: 8); // rtl-ignore: <reason>
#
# Exit codes: 0 clean | 1 violations found | 2 usage error or self-test failure

set -uo pipefail

NW='(^|[^A-Za-z0-9_])'
NK="(^|[^A-Za-z0-9_.\"'])"
SH='(^|[[:space:](:,=?!])'
EN='([^A-Za-z0-9_]|$)'

LABELS=()
REGEXES=()
HINTS=()
HITS=()
TOTAL=0

add_rule() { LABELS+=("$1"); REGEXES+=("$2"); HINTS+=("$3"); }

add_rule "EdgeInsets.only / fromLTRB" \
  "${NW}EdgeInsets\.(only|fromLTRB)\(" \
  "use EdgeInsetsDirectional.only(start:, end:) or EdgeInsets.symmetric/all"
add_rule "Alignment.<physical>" \
  "${NW}Alignment\.(topLeft|topRight|centerLeft|centerRight|bottomLeft|bottomRight)${EN}" \
  "use AlignmentDirectional.topStart / centerStart / bottomEnd ..."
add_rule "Alignment(x, y) constructor" \
  "${NW}Alignment\(" \
  "use AlignmentDirectional(start, y)"
add_rule "Positioned(...)" \
  "${NW}Positioned\(" \
  "use PositionedDirectional(start:, end:); Positioned.fill is allowed"
add_rule "Border(...)" \
  "${NW}Border\(" \
  "use BorderDirectional(start:, end:); Border.all / Border.symmetric are allowed"
add_rule "BorderRadius.only / horizontal" \
  "${NW}BorderRadius\.(only|horizontal)\(" \
  "use BorderRadiusDirectional.only(topStart:, ...) / .horizontal(start:, end:)"
add_rule "TextAlign.left / right" \
  "${NW}TextAlign\.(left|right)${EN}" \
  "use TextAlign.start / TextAlign.end"
add_rule "named argument left: / right:" \
  "${NK}(left|right)[[:space:]]*:" \
  "use start: / end: (or a *Directional API)"
add_rule "named argument topLeft: / bottomRight: ..." \
  "${NW}(topLeft|topRight|bottomLeft|bottomRight)[[:space:]]*:" \
  "use topStart: / topEnd: / bottomStart: / bottomEnd:"
add_rule "dot-shorthand .left / .topRight ..." \
  "${SH}\.(topLeft|topRight|centerLeft|centerRight|bottomLeft|bottomRight|left|right)${EN}" \
  "use the explicit start/end value (shorthand hides physical directions)"
add_rule "dot-shorthand .only( / .fromLTRB(" \
  "${SH}\.(only|fromLTRB)\(" \
  "write the explicit class name (EdgeInsetsDirectional.only ...) so it can be audited"

scan() {
  local root="$1" i hits count
  TOTAL=0
  for i in "${!LABELS[@]}"; do
    HITS[$i]=0
    hits=$(grep -rnE --include='*.dart' --exclude='*.g.dart' --exclude='*.freezed.dart' \
        --exclude-dir=generated -e "${REGEXES[$i]}" "$root" 2>/dev/null \
      | grep -vE ':[0-9]+:[[:space:]]*//' \
      | grep -vE 'rtl-ignore|ignore: rtl_physical_direction')
    if [ -n "$hits" ]; then
      count=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
      HITS[$i]=$count
      TOTAL=$((TOTAL + count))
      echo "✗ ${LABELS[$i]}  ->  ${HINTS[$i]}"
      printf '%s\n' "$hits" | sed 's/^/    /'
    fi
  done
}

self_test() {
  local tmp rc=0 i
  tmp=$(mktemp -d)
  trap "rm -rf '$tmp'" EXIT
  mkdir -p "$tmp/bad" "$tmp/good"

  cat > "$tmp/bad/bad.dart" <<'EOF'
final a = EdgeInsets.only(top: 1);
final a2 = const EdgeInsets.fromLTRB(1, 2, 3, 4);
const b = Alignment.centerLeft;
const b2 = Alignment(-1, 0);
Widget w = Positioned(top: 0, child: x);
final bd = Border(top: BorderSide.none);
final br = BorderRadius.horizontal(left: Radius.zero);
const t = TextAlign.right;
final n = foo(left: 8);
final n2 = foo(topLeft: r);
final s1 = x(alignment: .bottomRight);
final s2 = x(textAlign: .left);
final s3 = x(padding: .only(top: 1));
final s4 = x(padding: .fromLTRB(1, 2, 3, 4));
EOF

  cat > "$tmp/good/good.dart" <<'EOF'
const a = EdgeInsetsDirectional.only(start: 8);
const b = AlignmentDirectional.centerStart;
Widget w = PositionedDirectional(start: 0, top: 0, child: x);
Widget f = Positioned.fill(child: x);
final bd = BorderDirectional(start: BorderSide.none);
final br = BorderRadiusDirectional.only(topStart: Radius.circular(8));
const t = TextAlign.start;
const sym = EdgeInsets.symmetric(horizontal: 8);
const all = EdgeInsets.all(4);
final r = rect.left + box.rect.right;
final m = {'left': 1, "right": 2};
// EdgeInsets.only(left: 1) mentioned in a comment
/// Positioned(left: 1) mentioned in a doc comment
final legacy = EdgeInsets.only(left: 1); // rtl-ignore: third-party API
EOF

  scan "$tmp/good" > /dev/null
  if [ "$TOTAL" -ne 0 ]; then
    echo "SELF-TEST FAIL: clean fixture was flagged ($TOTAL hits)"; rc=2
  fi
  scan "$tmp/bad" > /dev/null
  for i in "${!LABELS[@]}"; do
    if [ "${HITS[$i]}" -eq 0 ]; then
      echo "SELF-TEST FAIL: rule never triggered: ${LABELS[$i]}"; rc=2
    fi
  done
  if [ "$rc" -eq 0 ]; then
    echo "self-test passed (${#LABELS[@]} rules)"
  fi
  return "$rc"
}

case "${1:-}" in
  --self-test) self_test; exit $? ;;
  -h|--help)   sed -n '2,15p' "$0"; exit 0 ;;
esac

ROOT="${1:-lib}"
if [ ! -d "$ROOT" ]; then
  echo "error: directory '$ROOT' not found" >&2
  exit 2
fi

scan "$ROOT"
if [ "$TOTAL" -gt 0 ]; then
  echo
  echo "RTL guard FAILED: $TOTAL physical-direction usage(s) in $ROOT."
  echo "Fix them, or append '// rtl-ignore: <reason>' for third-party APIs only."
  exit 1
fi
echo "RTL guard passed: no physical-direction APIs in $ROOT"
