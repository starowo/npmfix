#!/usr/bin/env bash
set -euo pipefail

declare -A VULN_VERSIONS=(
  [debug]="4.4.2"
  [color-name]="2.0.1"
  [strip-ansi]="7.1.1"
  [color]="5.0.1"
  [color-convert]="3.1.1"
  [color-string]="2.1.1"
  [has-ansi]="6.0.1"
  [ansi-styles]="6.2.2"
  [ansi-regex]="6.2.1"
  [supports-color]="10.2.1"
  [chalk]="5.6.1"
  [backslash]="0.2.1"
  [wrap-ansi]="9.0.1"
  [is-arrayish]="0.3.3"
  [error-ex]="1.3.3"
  [slice-ansi]="7.1.1"
  [simple-swizzle]="0.2.3"
  [chalk-template]="1.1.1"
  [supports-hyperlinks]="4.1.1"
)

DRY_RUN="${DRY_RUN:-0}"                # 置 1 仅打印将要执行的动作
WRITE_OVERRIDES="${WRITE_OVERRIDES:-1}"# 置 0 不写 package.json 的 "overrides"
BACKUP_PKG_JSON="${BACKUP_PKG_JSON:-1}"# 置 0 不备份 package.json

npm_root_global() { npm root -g 2>/dev/null | tr -d '\r'; }

parse_version_json() {
  PKG="$1"
  node -e '
    const fs = require("fs");
    const pkg = process.env.PKG;
    let d=""; process.stdin.on("data",c=>d+=c);
    process.stdin.on("end",()=>{
      try{
        const j=JSON.parse(d||"{}");
        const v=j?.dependencies?.[pkg]?.version || "";
        process.stdout.write(v);
      }catch{ process.stdout.write(""); }
    });
  '
}

check_local_version() {
  PKG="$1"
  export PKG
  npm ls "$PKG" --depth=0 --json 2>/dev/null | parse_version_json "$PKG"
}

check_global_version() {
  PKG="$1"
  export PKG
  npm -g ls "$PKG" --depth=0 --json 2>/dev/null | parse_version_json "$PKG"
}

fix_local() {
  PKG="$1"
  if [[ "$DRY_RUN" = "1" ]]; then
    echo "[DRY] npm remove $PKG && npm install $PKG@latest"
  else
    npm remove "$PKG" || true
    npm install "$PKG@latest"
  fi
}

fix_global() {
  PKG="$1"
  if [[ "$DRY_RUN" = "1" ]]; then
    echo "[DRY] npm -g remove $PKG && npm -g install $PKG@latest"
  else
    npm -g remove "$PKG" || true
    npm -g install "$PKG@latest"
  fi
}

add_override_if_needed() {
  PKG="$1"
  SAFE_RANGE="${2:-"*" }"

  [[ "$WRITE_OVERRIDES" = "1" ]] || return 0
  [[ -f package.json ]] || return 0

  if [[ "$BACKUP_PKG_JSON" = "1" && ! -f package.json.bak_semfix ]]; then
    cp package.json package.json.bak_semfix
  fi

  node -e '
    const fs=require("fs");
    const path="package.json";
    const pkg=JSON.parse(fs.readFileSync(path,"utf8"));
    pkg.overrides = Object.assign({}, pkg.overrides);
    const name=process.argv[1], range=process.argv[2];
    // 只有在没写过 override 或想提升版本时才写入
    if (!pkg.overrides[name] || pkg.overrides[name] !== range) {
      pkg.overrides[name]=range;
      fs.writeFileSync(path, JSON.stringify(pkg,null,2));
      console.log(`[overrides] set ${name} -> ${range}`);
    }
  ' "$PKG" "^0.0.0-0 || >=0.0.0" >/dev/null 2>&1

  if [[ "$DRY_RUN" = "1" ]]; then
    echo "[DRY] npm install  # to apply overrides"
  else
    npm install
  fi
}

echo "=== 扫描并修复当前项目（$(pwd)）与 npm 全局 ==="

HIT_LOCAL=0
HIT_GLOBAL=0

for PKG in "${!VULN_VERSIONS[@]}"; do
  BAD="${VULN_VERSIONS[$PKG]}"

  # --- 本地 ---
  LV="$(check_local_version "$PKG" || true)"
  if [[ -n "$LV" && "$LV" == "$BAD" ]]; then
    ((HIT_LOCAL++))
    echo "[LOCAL] 命中 $PKG@$LV  → 修复为最新版本"
    fix_local "$PKG"
    add_override_if_needed "$PKG"
  fi

  # --- 全局 ---
  GV="$(check_global_version "$PKG" || true)"
  if [[ -n "$GV" && "$GV" == "$BAD" ]]; then
    ((HIT_GLOBAL++))
    echo "[GLOBAL] 命中 $PKG@$GV  → 修复为最新版本"
    fix_global "$PKG"
  fi
done

if [[ $HIT_LOCAL -eq 0 && $HIT_GLOBAL -eq 0 ]]; then
  echo "未发现受害清单中的精确版本。"
else
  echo "完成。项目命中 $HIT_LOCAL 个，全局命中 $HIT_GLOBAL 个。"
  echo "建议：执行一次全盘杀毒，并重启电脑。"
fi
