// eval.d.pp
module eval;

import std.exception;
import std.stdint;
import std.stdio;
import types;

enum FV_SCALE = 16;
enum N = 2344;
__gshared int16_t[N][N] PP;


/**
 * 評価関数バイナリをロードする
 */
void loadPP(string path)
{
    File f = File(path, "r");
    enforce(f.size == N * N * int16_t.sizeof, "invalid pp.bin size");
    f.rawRead(PP[]);
}

/**
 * 手番のある側から見た評価値を返す
 */
short staticValue(const ref Position pos)
{
    if (pos.piecesInHand[Color.BLACK][Type.KING] > 0) {
        return pos.sideToMove == Color.BLACK ? +15000 : -15000;
    }
    if (pos.piecesInHand[Color.WHITE][Type.KING] > 0) {
        return pos.sideToMove == Color.BLACK ? -15000 : +15000;
    }

    int[40] list;
    int length = pieceList(pos, list);

    int sum = 0;
    for (int i = 0; i < length; i++) {
        for (int j = i; j < length; j++) {
            sum += PP[list[i]][list[j]];
        }
    }

    int value = sum / FV_SCALE;
    assert(short.min <= value && value <= short.max);
    return cast(short)(pos.sideToMove == Color.BLACK ? value : -value);
}

/**
 * 駒リストを作る
 * returns: 駒リストの長さ
 */
int pieceList(const ref Position pos, ref int[40] list)
{
    int length = 0;

    // 持ち駒
    for (int t = Type.PAWN; t <= Type.ROOK; t++) {
        for (int c = Color.BLACK; c <= Color.WHITE; c++) {
            for (int i = 0; i < pos.piecesInHand[c][t]; i++) {
                list[length++] = OFFSET_HAND[c][t] + i;
            }
        }
    }
    // 盤上の駒
    for (int i = SQ11; i <= SQ99; i++) {
        if (pos.board[i] != Square.EMPTY) {
            list[length++] = OFFSET_PP[pos.board[i].i] + i;
        }
    }
    return length;
}

/*
 * 持ち駒からオフセットを引く表
 * key: [color_t][type_t]
 */
immutable short[][] OFFSET_HAND = [
  // 歩, 香, 桂, 銀, 金, 角, 飛,
    [ 0, 36, 44, 52, 60, 68, 72, ],
    [18, 40, 48, 56, 64, 70, 74, ],
];

/*
 * 盤上の駒からオフセットを引く表
 * key: Square
 */
immutable short[] OFFSET_PP = [
  // 歩,  香,  桂,  銀,  金,  角,   飛,   王,   と, 成香, 成桂, 成銀,   馬,   龍,
     76, 238, 400, 562, 724, 886, 1048, 2182, 1210, 1372, 1534, 1696, 1858, 2020,
    157, 319, 481, 643, 805, 967, 1129, 2263, 1291, 1453, 1615, 1777, 1939, 2101,
];
