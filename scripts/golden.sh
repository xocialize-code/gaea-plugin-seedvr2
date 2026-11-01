#!/bin/zsh
# The plugin against in-process MLXServeEngine: upscales run on the signed bundle the way Gaea runs them
# (gaea-plugin-check: launch under the launch requirement, configure, prepare, run) and through seedvr2-inproc with the
# lane configuration and request the worker uses. Each pair must decode to the same frames, byte for byte (ffmpeg's
# framemd5): the files differ only in the MP4's creation time, to the second. Each has the source's frames at its size
# × scale, in HEVC. Gaea retimes the output and puts the sound back (GaeaVideo), so neither is checked here.
#
#   scripts/golden.sh <out-dir>     (after scripts/build-plugin.sh)
#
# Cases: Tests/Fixtures/clip.mp4 (128×96, 17 frames at 24 fps, with sound) at scales 2 and 4 on int8, and at 2 on fp16;
# clip180.mp4 (320×180, 48 frames, five 9-frame windows) at 2 on int8. fp16's weights (8.4 GB) are fetched into the
# models root by the engine on the first run. Needs ffprobe for the frame counts.
set -uo pipefail
ROOT=${0:A:h:h}
cd $ROOT
OUT=${1:?out dir}; mkdir -p $OUT
B=$ROOT/dist/seedvr2.gaeaplugin
F=$ROOT/Tests/Fixtures
MODELS=${CHECK_MODELS_ROOT:-$HOME/Library/Application Support/MLXEngine/Models}
SWIFTPM=(-c release --build-system swiftbuild)
xcrun swift build $SWIFTPM --product seedvr2-inproc > /dev/null && xcrun swift build -c release --product gaea-plugin-check > /dev/null
INPROC=$(xcrun swift build $SWIFTPM --show-bin-path)/seedvr2-inproc; CHECK=$(xcrun swift build -c release --show-bin-path)/gaea-plugin-check
LOG=$OUT/golden.log; : > $LOG
pass=0; fail=0
say() { print -r -- "$*" | tee -a $LOG }
say "# SeedVR2 golden check $(date -u +%FT%TZ): $(python3 -c "import json; m=json.load(open('$B/Contents/Resources/manifest.json')); print(m['id'], m['version'])")"
probe() { ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=codec_name,width,height,nb_read_frames -of csv=p=0 $1 }
frames() { ffmpeg -v error -i $1 -map 0:v -f framemd5 - | grep -v '^#' | awk -F', *' '{print $NF}' | shasum -a 256 | cut -c1-16 }
outputs() { grep -o '"path":"[^"]*"' $1 | sed 's/"path":"//; s/"$//; s/\\\//\//g' | awk '!seen[$0]++' }

# case <name> <quant> <clip> <scale> <width> <height> <source frames>
case_() {
  local name=$1 quant=$2 clip=$3 scale=$4 w=$5 h=$6 frames=$7
  $CHECK $B --operation video.upscale --model seedvr2-$quant --lane $quant --params "{\"scale\":$scale,\"content\":\"live_action\"}" \
    --input "video=$clip" --models-root "$MODELS" --budget 64000000000 --timeout 3600 --session $OUT/$name.gpp > $OUT/$name-gpp.log 2>&1
  local file=$(outputs $OUT/$name-gpp.log | head -1); [[ -f $file ]] && cp $file $OUT/$name-gpp.mp4
  $INPROC --video $clip --scale $scale --quant $quant --models-root "$MODELS" --out $OUT/$name-inproc.mp4 2>> $LOG | tail -1 > $OUT/$name-inproc.json
  say "      $name: over GPP $(grep -o 'ran in [0-9.]* s' $OUT/$name-gpp.log | head -1); in-process $(cat $OUT/$name-inproc.json)"
  local a=$(frames $OUT/$name-gpp.mp4 2>/dev/null) b=$(frames $OUT/$name-inproc.mp4 2>/dev/null)
  local got=$(probe $OUT/$name-gpp.mp4 2>/dev/null) want="hevc,$(( w * scale )),$(( h * scale )),$frames"
  if [[ -n $a && $a == $b && $got == $want ]]; then pass=$((pass+1)); say "PASS  $name: the same decoded frames, $got, framemd5 sha256 $a…"
  else fail=$((fail+1)); say "FAIL  $name: $a… / $b…, $got (want $want)"; fi
}

case_ int8-x2 int8 $F/clip.mp4 2 128 96 17
case_ int8-x4 int8 $F/clip.mp4 4 128 96 17
case_ int8-x2-180p int8 $F/clip180.mp4 2 320 180 48
case_ fp16-x2 fp16 $F/clip.mp4 2 128 96 17

for s in $OUT/*.gpp; do
  if python3 ${GAEA_SPEC_ROOT:-$ROOT/../gaea-mes-media-server}/tools/validate.py --transcript $s >> $LOG 2>&1; then pass=$((pass+1)); say "PASS  ${s:t} passes validate.py"
  else fail=$((fail+1)); say "FAIL  ${s:t} fails validate.py"; fi
done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
