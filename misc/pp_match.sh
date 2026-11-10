#!/bin/bash
#
# 2つの PP 評価関数ファイルで tenuki 同士を対局させ、勝敗を集計する
#
# usage: misc/pp_match.sh [-n games] [-t time] [-p port] EVAL_A EVAL_B
#
#   EVAL_A, EVAL_B  評価関数ファイル（例: pp.0.bin pp.30.bin）
#   -n games        対局数（既定: 20）。先後を1局ごとに入れ替える
#   -t time         持ち時間（既定: 300-2F = 5分+1手2秒加算）
#   -p port         shogi-server のポート（既定: 4091）
#
# 環境変数:
#   SHOGI_SERVER  shogi-server のディレクトリ（既定: ~/src/shogi-server）
#   WORK_DIR      作業ディレクトリ（既定: ./match）
#   HASH_MB       各 tenuki の置換表サイズ（既定: 256）
#   THREADS       各 tenuki の探索スレッド数（既定: 2）
#   MAX_MOVES     最大手数（既定: 512）
#
# 例:
#   misc/pp_match.sh pp.0.bin pp.30.bin
#   misc/pp_match.sh -n 100 -t 60-1F pp.0.bin pp.30.bin
#
# shogi-server はこのスクリプトが起動し、終了時に止める。
# 棋譜は shogi-server のディレクトリに保存される。

set -u

GAMES=20
TIME=300-2F
PORT=4091
while getopts n:t:p: opt; do
    case $opt in
        n) GAMES=$OPTARG ;;
        t) TIME=$OPTARG ;;
        p) PORT=$OPTARG ;;
        *) sed -n 3,26p "$0"; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
if [ $# -ne 2 ]; then
    sed -n 3,26p "$0"
    exit 1
fi

REPO=$(cd "$(dirname "$0")/.." && pwd)
TENUKI=$REPO/tenuki
SHOGI_SERVER=${SHOGI_SERVER:-$HOME/src/shogi-server}
WORK_DIR=${WORK_DIR:-./match}
HASH_MB=${HASH_MB:-256}
THREADS=${THREADS:-2}
MAX_MOVES=${MAX_MOVES:-512}
GAME_NAME=match-$TIME

EVALS=("$(realpath "$1")" "$(realpath "$2")")
for f in "${EVALS[@]}" "$TENUKI" "$REPO/book.db" "$SHOGI_SERVER/shogi-server"; do
    if [ ! -e "$f" ]; then
        echo "not found: $f" >&2
        exit 1
    fi
done

# プレイヤー名: pp.30.bin -> pp_30
player_name() {
    basename "$1" .bin | tr -c 'A-Za-z0-9_\n' '_'
}
NAMES=("$(player_name "${EVALS[0]}")" "$(player_name "${EVALS[1]}")")
if [ "${NAMES[0]}" = "${NAMES[1]}" ]; then
    NAMES=("${NAMES[0]}_a" "${NAMES[1]}_b")
fi

# 作業ディレクトリ: プレイヤーごとに pp.bin / book.db / tenuki.conf / log を置く
mkdir -p "$WORK_DIR"
WORK_DIR=$(realpath "$WORK_DIR")
for i in 0 1; do
    d=$WORK_DIR/${NAMES[$i]}
    mkdir -p "$d/log" "$WORK_DIR/games"
    ln -sfn "${EVALS[$i]}" "$d/pp.bin"
    ln -sfn "$REPO/book.db" "$d/book.db"
    printf 'hash_mb = %d\nthreads = %d\n' "$HASH_MB" "$THREADS" > "$d/tenuki.conf"
done

# shogi-server を起動する
if nc -z localhost "$PORT" 2>/dev/null; then
    echo "port $PORT is already in use" >&2
    exit 1
fi
ruby "$SHOGI_SERVER/shogi-server" --max-moves "$MAX_MOVES" match "$PORT" > "$WORK_DIR/server.log" 2>&1 &
SERVER_PID=$!
cleanup() {
    trap - EXIT INT TERM
    # 先に tenuki（play のサブシェルの子）を止める。接続が残っていると shogi-server が終わらない
    for p in $(jobs -p); do pkill -TERM -P "$p" 2>/dev/null; done
    kill $(jobs -p) 2>/dev/null
    for _ in $(seq 1 10); do
        kill -0 "$SERVER_PID" 2>/dev/null || break
        sleep 0.5
    done
    kill -KILL "$SERVER_PID" 2>/dev/null
    wait 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM
for _ in $(seq 1 50); do
    nc -z localhost "$PORT" 2>/dev/null && break
    sleep 0.2
done
if ! nc -z localhost "$PORT" 2>/dev/null; then
    echo "shogi-server did not start (see $WORK_DIR/server.log)" >&2
    exit 1
fi

# 1局指す。結果（WIN / LOSE / DRAW / ERROR）を "$WORK_DIR/games/<局>-<名前>.result" に書く
play() {
    local game=$1 name=$2 turn=$3
    local d=$WORK_DIR/$name
    local err=$WORK_DIR/games/$game-$name.err
    (cd "$d" && exec "$TENUKI" -p "$PORT" localhost "$name" "$GAME_NAME-$turn,x" > /dev/null 2> "$err")
    local r
    r=$(grep -oE '^<"#(WIN|LOSE|DRAW|CENSORED)' "$err" | tail -1 | tr -d '<"#')
    [ "$r" = CENSORED ] && r=DRAW # 最大手数に達した
    echo "${r:-ERROR}" > "$WORK_DIR/games/$game-$name.result"
}

declare -A WIN LOSE DRAW ERR
for n in "${NAMES[@]}"; do WIN[$n]=0; LOSE[$n]=0; DRAW[$n]=0; ERR[$n]=0; done
declare -A BLACK_WIN
BLACK_WIN[total]=0

echo "${NAMES[0]} = ${EVALS[0]}"
echo "${NAMES[1]} = ${EVALS[1]}"
echo "games: $GAMES, time: $TIME, hash_mb: $HASH_MB, threads: $THREADS, port: $PORT"
echo "work dir: $WORK_DIR"
echo

for g in $(seq 1 "$GAMES"); do
    game=$(printf '%03d' "$g")
    # 奇数局は NAMES[0] が先手、偶数局は NAMES[1] が先手
    if [ $((g % 2)) = 1 ]; then black=${NAMES[0]}; white=${NAMES[1]}; else black=${NAMES[1]}; white=${NAMES[0]}; fi

    play "$game" "$black" B & pb=$!
    sleep 0.5
    play "$game" "$white" W & pw=$!

    # 片方が先に終わったら、もう片方を最大60秒待ってから止める（相手を待ち続けないように）
    while kill -0 $pb 2>/dev/null && kill -0 $pw 2>/dev/null; do sleep 1; done
    for _ in $(seq 1 60); do
        kill -0 $pb 2>/dev/null || kill -0 $pw 2>/dev/null || break
        sleep 1
    done
    pkill -P $pb 2>/dev/null; pkill -P $pw 2>/dev/null
    wait $pb $pw 2>/dev/null

    rb=$(cat "$WORK_DIR/games/$game-$black.result" 2>/dev/null || echo ERROR)
    rw=$(cat "$WORK_DIR/games/$game-$white.result" 2>/dev/null || echo ERROR)
    for pair in "$black:$rb" "$white:$rw"; do
        n=${pair%%:*}; r=${pair#*:}
        case $r in
            WIN)  WIN[$n]=$((WIN[$n] + 1)) ;;
            LOSE) LOSE[$n]=$((LOSE[$n] + 1)) ;;
            DRAW) DRAW[$n]=$((DRAW[$n] + 1)) ;;
            *)    ERR[$n]=$((ERR[$n] + 1)) ;;
        esac
    done
    [ "$rb" = WIN ] && BLACK_WIN[total]=$((BLACK_WIN[total] + 1))

    printf '%s  先手 %-10s %-5s  後手 %-10s %-5s  |  %s %d-%d-%d  %s %d-%d-%d\n' \
        "$game" "$black" "$rb" "$white" "$rw" \
        "${NAMES[0]}" "${WIN[${NAMES[0]}]}" "${LOSE[${NAMES[0]}]}" "${DRAW[${NAMES[0]}]}" \
        "${NAMES[1]}" "${WIN[${NAMES[1]}]}" "${LOSE[${NAMES[1]}]}" "${DRAW[${NAMES[1]}]}"
    sleep 1
done

echo
for n in "${NAMES[@]}"; do
    w=${WIN[$n]}; l=${LOSE[$n]}; d=${DRAW[$n]}
    decided=$((w + l))
    rate=$( [ $decided -gt 0 ] && awk "BEGIN { printf \"%.1f%%\", 100 * $w / $decided }" || echo "-" )
    echo "$n: ${w}勝 ${l}敗 ${d}分 (エラー ${ERR[$n]})  勝率 $rate"
done
echo "先手勝ち: ${BLACK_WIN[total]} / $GAMES"
