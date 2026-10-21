#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$project_dir/.." && pwd)
resource_dir=${MIR2X_RES_REPO_PATH:-"$repo_dir/../mir2x_res"}
godot_bin=${GODOT_BIN:-}

if [ -z "$godot_bin" ]; then
    for candidate in /home/czx/godot /home/czx/godot_bin "$(command -v godot4 2>/dev/null || true)"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            godot_bin=$candidate
            break
        fi
    done
fi

if [ -z "$godot_bin" ] || [ ! -x "$godot_bin" ]; then
    echo "Godot executable not found: $godot_bin" >&2
    exit 1
fi
if [ ! -d "$resource_dir" ]; then
    echo "mir2x_res not found: $resource_dir" >&2
    exit 1
fi

mkdir -p "$project_dir/assets/font"
cp "$resource_dir/font/00_SIMSUN.TTF" "$project_dir/assets/font/00_SIMSUN.ttf"
cp "$resource_dir/font/01_Yahei.TTF" "$project_dir/assets/font/01_Yahei.ttf"
cp "$resource_dir/font/02_CALIBRI.TTF" "$project_dir/assets/font/02_CALIBRI.ttf"
cp "$resource_dir/font/03_MONOWIDE.TTF" "$project_dir/assets/font/03_MONOWIDE.ttf"
cp "$resource_dir/font/04_YaHei_Consolas_Hybrid.TTF" "$project_dir/assets/font/04_YaHei_Consolas_Hybrid.ttf"
cp "$resource_dir/font/05_NSIMSUN.TTF" "$project_dir/assets/font/05_NSIMSUN.ttf"
cp "$resource_dir/font/06_YaHei_Monaco_Hybrid.TTF" "$project_dir/assets/font/06_YaHei_Monaco_Hybrid.ttf"
cp "$resource_dir/font/07_fusion-pixel-12px-monospaced-zh_hans.TTF" "$project_dir/assets/font/07_fusion-pixel-12px-monospaced-zh_hans.ttf"
cp "$resource_dir/font/08_fusion-pixel-12px-proportional-zh_hans.TTF" "$project_dir/assets/font/08_fusion-pixel-12px-proportional-zh_hans.ttf"
cp "$resource_dir/font/09_WenQuanYi_Bitmap_Song_15_px.TTF" "$project_dir/assets/font/09_WenQuanYi_Bitmap_Song_15_px.ttf"
cp "$resource_dir/font/0A_WenQuanYi_Bitmap_Song_15_px.TTF" "$project_dir/assets/font/0A_WenQuanYi_Bitmap_Song_15_px.ttf"
cp "$resource_dir/font/0B_WenQuanYi_Bitmap_Song_15_px.TTF" "$project_dir/assets/font/0B_WenQuanYi_Bitmap_Song_15_px.ttf"
cp "$resource_dir/font/0C_WenQuanYi_Bitmap_Song_18_px.TTF" "$project_dir/assets/font/0C_WenQuanYi_Bitmap_Song_18_px.ttf"
cp "$resource_dir/font/0D_WenQuanYi_Bitmap_Song_18_px.TTF" "$project_dir/assets/font/0D_WenQuanYi_Bitmap_Song_18_px.ttf"

mkdir -p "$project_dir/assets/generated/emoji"
cp -a "$resource_dir/emoji/." "$project_dir/assets/generated/emoji/"

mkdir -p "$project_dir/build/audio/bgm"
cp -a "$resource_dir/sound/bgm/." "$project_dir/build/audio/bgm/"
mkdir -p "$project_dir/build/audio/seff"
cp -a "$resource_dir/sound/seff/." "$project_dir/build/audio/seff/"
touch "$project_dir/build/audio/.gdignore"

if [ "${MIR2X_SKIP_CPP_BUILD:-0}" = "1" ]; then
    echo "MIR2X_SKIP_CPP_BUILD=1: 跳过 C++ 目标重建，直接使用现有 build/Release/godotworldres"
    if [ ! -x "$repo_dir/build/Release/godotworldres" ]; then
        echo "godotworldres 不存在，无法跳过重建: $repo_dir/build/Release/godotworldres" >&2
        exit 1
    fi
else
    "$repo_dir/build.sh" Release --mir2x-res "$resource_dir" --target godotworldres
fi
build_signature=$(sed -n 's/^MIR2X_BUILD_SIGNATURE:STRING=//p' "$repo_dir/build/Release/CMakeCache.txt" | head -n 1)
if [ -z "$build_signature" ]; then
    echo "failed to read MIR2X_BUILD_SIGNATURE from CMakeCache.txt" >&2
    exit 1
fi
mkdir -p "$project_dir/assets/generated"
printf '%s\n' "$build_signature" > "$project_dir/assets/generated/build_signature.txt"
if [ ! -f "$repo_dir/build/Release/res/map/mapbin.zsdb" ]; then
    "$repo_dir/build.sh" Release --mir2x-res "$resource_dir" --target zsdbdeploy
fi

world_res_dir="$project_dir/build/world_res"
mkdir -p "$world_res_dir"
# 客户端直接读取 ZSDB（scripts/resource/），这里只产出索引/元数据，
# 不再把 37 万帧 PNG 铺到磁盘上；.gdignore 仍然保留，避免编辑器扫描运行时资源目录。
touch "$world_res_dir/.gdignore"

# 把纹理 ZSDB 挂到 world_res/texture 供 ResourceStore 解析；
# 同一文件系统用硬链接，避免 1.4G 重复占用（无法硬链接时退回复制）。
mkdir -p "$world_res_dir/texture"
for zsdb_path in "$repo_dir"/build/Release/res/texture/*.zsdb; do
    cp -l "$zsdb_path" "$world_res_dir/texture/" 2>/dev/null || cp "$zsdb_path" "$world_res_dir/texture/"
done

map_id_args=""
if [ -n "${MIR2X_GODOT_MAP_ID:-}" ]; then
    map_id_args=$MIR2X_GODOT_MAP_ID
fi
"$repo_dir/build/Release/godotworldres" \
    "$repo_dir/build/Release/res/map/mapbin.zsdb" \
    "$repo_dir/build/Release/res/texture/map.zsdb" \
    "$world_res_dir" $map_id_args --no-png
"$repo_dir/build/Release/godotworldres" --sprites "$world_res_dir" \
    hero "$repo_dir/build/Release/res/texture/hero.zsdb" \
    hair "$repo_dir/build/Release/res/texture/hair.zsdb" \
    helmet "$repo_dir/build/Release/res/texture/helmet.zsdb" \
    weapon "$repo_dir/build/Release/res/texture/weapon.zsdb" \
    monster "$repo_dir/build/Release/res/texture/monster.zsdb" \
    npc "$repo_dir/build/Release/res/texture/npc.zsdb" \
    item "$repo_dir/build/Release/res/texture/item.zsdb" \
    equip "$repo_dir/build/Release/res/texture/equip.zsdb" \
    proguse "$repo_dir/build/Release/res/texture/proguse.zsdb" \
    selectchar "$repo_dir/build/Release/res/texture/selectchar.zsdb" \
    magic "$repo_dir/build/Release/res/texture/magic.zsdb" --no-png

mkdir -p "$project_dir/build"
"$godot_bin" --headless --editor --path "$project_dir" --quit
"$godot_bin" --headless --path "$project_dir" --export-pack Linux "$project_dir/build/mir2x-client.pck"
