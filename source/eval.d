import core.stdc.stdio;
import std.stdint;
import types;

private enum FV_SCALE = 32;
private immutable int32_t[2][81][81] KK;
private immutable int32_t[2][1548][81][81] KKP;
private immutable int16_t[2][1548][1548][81] KPP;


/**
 * 静的コンストラクタ
 * 評価関数バイナリをロードする
 */
shared static this()
{
    FILE* fp;

    fp = fopen("KK_synthesized.bin", "r");
    fread(cast(void*)KK, int32_t.sizeof, 2 * 81 * 81, fp);
    fclose(fp);

    fp = fopen("KKP_synthesized.bin", "r");
    fread(cast(void*)KKP, int32_t.sizeof, 2 * 1548 * 81 * 81, fp);
    fclose(fp);

    fp = fopen("KPP_synthesized.bin", "r");
    fread(cast(void*)KPP, int16_t.sizeof, 2 * 1548 * 1548 * 81, fp);
    fclose(fp);
}


/**
 * 手番のある側から見た評価値を返す
 */
short staticValue(const ref Position p)
{
    if (p.piecesInHand[Color.BLACK][Type.KING] > 0) {
        return p.sideToMove == Color.BLACK ? +15000 : -15000;
    }
    if (p.piecesInHand[Color.WHITE][Type.KING] > 0) {
        return p.sideToMove == Color.BLACK ? -15000 : +15000;
    }

    // 駒割りの計算
    int material = 0;
    int bk = 0;
    int wk = 0;
    int[38] list;
    int[38] list_inv;
    int length = 0;

    // 持ち駒
    for (int t = Type.PAWN; t <= Type.ROOK; t++) {
        material += (p.piecesInHand[Color.BLACK][t] - p.piecesInHand[Color.WHITE][t]) * P_VALUE[t];
        for (int i = 0; i < p.piecesInHand[Color.BLACK][t]; i++) {
            list    [length] = OFFSET_HAND[Color.BLACK][t] + i;
            list_inv[length] = OFFSET_HAND[Color.WHITE][t] + i;
            length++;
        }
        for (int i = 0; i < p.piecesInHand[Color.WHITE][t]; i++) {
            list    [length] = OFFSET_HAND[Color.WHITE][t] + i;
            list_inv[length] = OFFSET_HAND[Color.BLACK][t] + i;
            length++;
        }
    }
    for (int i = SQ11; i <= SQ99; i++) {
        Square sq = p.board[i];
        material += P_VALUE[sq.i];
        bk = (sq == Square.B_KING) ? i : bk;
        wk = (sq == Square.W_KING) ? i : wk;
        if (sq != Square.EMPTY && sq.type != Type.KING) {
            list    [length] = OFFSET_PP[sq.i] + i;
            list_inv[length] = OFFSET_PP[sq.inv.i] + (SQ99 - i);
            length++;
        }
    }
    assert(length == 38);

    int sum0a, sum0b; // 先手玉から見たKPP,  先手玉から見たKPPの手番ボーナス
    int sum1a, sum1b; // 後手玉から見たKPP,  後手玉から見たKPPの手番ボーナス
    int sum2a, sum2b; // KK + KKP,  KKの手番ボーナス + KKPの手番ボーナス

    // KK
    sum2a = KK[bk][wk][0];
    sum2b = KK[bk][wk][1];
    for (int i = 0; i < 38; i++) {
        const int k     = list[i];
        const int k_inv = list_inv[i];

        // KKP
        sum2a += KKP[bk][wk][k][0];
        sum2b += KKP[bk][wk][k][1];

        for (int j = 0; j < i; j++) {
            const int l     = list[j];
            const int l_inv = list_inv[j];

            // KPP
            sum0a += KPP[bk][k][l][0];
            sum0b += KPP[bk][k][l][1];
            sum1a += KPP[SQ99 - wk][k_inv][l_inv][0];
            sum1b += KPP[SQ99 - wk][k_inv][l_inv][1];
        }
    }

    // 手番に依存しない評価値合計
    const int scoreBoard = sum0a - sum1a + sum2a + (material * FV_SCALE); // 先手玉から見たKKP - 後手玉から見たKPP + KK + KKP + 駒割

    // 手番に依存する評価値合計
    const int scoreTurn  = sum0b + sum1b + sum2b; // 先手玉から見たKKPの手番ボーナス + 後手玉から見たKPPの手番ボーナス + KKの手番ボーナス + KKPの手番ボーナス

    // stderr.writefln("material:%d", material);
    // stderr.writefln("scoreBoard:%d", scoreBoard / FV_SCALE);
    // stderr.writefln("scoreTurn:%d", scoreTurn / FV_SCALE);
    return cast(short)(((p.sideToMove == Color.BLACK ? scoreBoard : -scoreBoard) + scoreTurn) / FV_SCALE);
}


/*
 * value: 駒割りの評価値
 * key: Square
 * see: https://github.com/HiraokaTakuya/apery/blob/32216277e51c3b008e3c8eea6954f1bb3c416b57/src/pieceScore.hpp#L28
 */
private immutable short[] P_VALUE = [
  // 歩,   香,   桂,   銀,   金,   角,   飛,     王,   と, 成香, 成桂, 成銀,   馬,    龍,
     90,  315,  405,  495,  540,  855,  990,  15000,  540,  540,  540,  540,  945,  1395,
    -90, -315, -405, -495, -540, -855, -990, -15000, -540, -540, -540, -540, -945, -1395, 0,
];


/*
 * 持ち駒（手番と駒のタイプ）からオフセットを引く表
 * key: [color_t][type_t]
 * see https://github.com/HiraokaTakuya/apery/blob/32216277e51c3b008e3c8eea6954f1bb3c416b57/src/evaluate.hpp#L36
 */
private immutable short[][] OFFSET_HAND = [
  // 歩, 香, 桂, 銀, 金, 角, 飛,
    [ 1, 39, 49, 59, 69, 79, 85, ],
    [20, 44, 54, 64, 74, 82, 88, ],
];


/*
 * 駒からオフセットを引く表
 * key: Square
 * see https://github.com/HiraokaTakuya/apery/blob/32216277e51c3b008e3c8eea6954f1bb3c416b57/src/evaluate.hpp#L36
 */
private immutable short[] OFFSET_PP = [
  // 歩,  香,  桂,  銀,  金,  角,   飛, 王,  と, 成香, 成桂, 成銀,   馬,   龍,
     90, 252, 414, 576, 738, 900, 1224,  0, 738,  738,  738,  738, 1062, 1386,
    171, 333, 495, 657, 819, 981, 1305,  0, 819,  819,  819,  819, 1143, 1467,
];
