/*
 * fv_nano.binには符号付き16ビット整数がリトルエンディアンで1,476 x 81 = 119,556個格納されている(239,112バイト)。
 * 1エントリーの長さは1476で，これが自玉の位置に合わせて81レコード格納されている。
 * 最初のエントリー(FV[0])は自玉が1一にいるときの評価値である。
 * 9番目のエントリー(FV[8])は自玉が9一にいるときの評価値である。
 * 最後のエントリー(FV[80])は自玉が9九にいるときの評価値である。
 * エントリーの内訳は次のとおり：
 *
 * 内容                                       index from index to 要素数
 * ------------------------------------------ ---------- -------- ------
 * 自軍の持駒に歩が0～18枚あるときの評価値             0       18     19
 * 敵軍の持駒に歩が0～18枚あるときの評価値            19       37     19
 * 自軍の持駒に香が0～4枚あるときの評価値             38       42      5
 * 敵軍の持駒に香が0～4枚あるときの評価値             43       47      5
 * 自軍の持駒に桂が0～4枚あるときの評価値             48       52      5
 * 敵軍の持駒に桂が0～4枚あるときの評価値             53       57      5
 * 自軍の持駒に銀が0～4枚あるときの評価値             58       62      5
 * 敵軍の持駒に銀が0～4枚あるときの評価値             63       67      5
 * 自軍の持駒に金が0～4枚あるときの評価値             68       72      5
 * 敵軍の持駒に金が0～4枚あるときの評価値             73       77      5
 * 自軍の持駒に角が0～2枚あるときの評価値             78       80      3
 * 敵軍の持駒に角が0～2枚あるときの評価値             81       83      3
 * 自軍の持駒に飛が0～2枚あるときの評価値             84       86      3
 * 敵軍の持駒に飛が0～2枚あるときの評価値             87       89      3
 * 自軍の歩がアドレス9～80にいるときの評価値          90      161     72
 * 敵軍の歩がアドレス0～71にいるときの評価値         162      233     72
 * 自軍の香がアドレス9～80にいるときの評価値         234      305     72
 * 敵軍の香がアドレス0～71にいるときの評価値         306      377     72
 * 自軍の桂がアドレス18～80にいるときの評価値        378      440     63
 * 敵軍の桂がアドレス0～62にいるときの評価値         441      503     63
 * 自軍の銀がアドレス0～80にいるときの評価値         504      584     81
 * 敵軍の銀がアドレス0～80にいるときの評価値         585      665     81
 * 自軍の金がアドレス0～80にいるときの評価値         666      746     81
 * 敵軍の金がアドレス0～80にいるときの評価値         747      827     81
 * 自軍の角がアドレス0～80にいるときの評価値         828      908     81
 * 敵軍の角がアドレス0～80にいるときの評価値         909      989     81
 * 自軍の馬がアドレス0～80にいるときの評価値         990     1070     81
 * 敵軍の馬がアドレス0～80にいるときの評価値        1071     1151     81
 * 自軍の飛がアドレス0～80にいるときの評価値        1152     1232     81
 * 敵軍の飛がアドレス0～80にいるときの評価値        1233     1313     81
 * 自軍の龍がアドレス0～80にいるときの評価値        1314     1394     81
 * 敵軍の龍がアドレス0～80にいるときの評価値        1395     1475     81
 * ------------------------------------------ ---------- -------- ------
 *                                                            合計：1476
 */

import types;
import std.stdio;

private const short[1476][81] FV;
enum FV_SCALE = 32;

static this()
{
    File f = File("fv_nano.bin", "r");
    scope(exit) f.close();
    short[1] buf;
    for (int i = 0; i < 81; i++) {
        for (int j = 0; j < 1476; j++) {
            FV[i][j] = f.rawRead(buf)[0];
        }
    }
}

/*
 * value: FVのオフセット
 * key: [side_t][type_t]
 */
private immutable ushort[][] OFFSET_HAND = [
  // 歩, 香, 桂, 銀, 角, 飛, 金,
    [ 0, 38, 48, 58, 78, 84, 68],
    [19, 43, 53, 63, 81, 87, 73]
];

/*
 * value: FVのオフセット
 * key: square_t
 */
private immutable ushort[] OFFSET_BOARD = [
  // 歩,  香,  桂,  銀,  角,   飛,  金, 王,  と, 成香, 成桂, 成銀,   馬,   龍, 空, 壁,
     81, 225, 360, 504, 828, 1152, 666,  0, 666,  666,  666,  666,  990, 1314,  0,  0,
    162, 306, 441, 585, 909, 1233, 747,  0, 747,  747,  747,  747, 1071, 1395,
];

/*
 * value: FVのアドレス
 * key: Position.squaresのインデックス
 */
private immutable ubyte[] ADDRESS_OF = [
     0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
     0,  0,  9, 18, 27, 36, 45, 54, 63, 72,
     0,  1, 10, 19, 28, 37, 46, 55, 64, 73,
     0,  2, 11, 20, 29, 38, 47, 56, 65, 74,
     0,  3, 12, 21, 30, 39, 48, 57, 66, 75,
     0,  4, 13, 22, 31, 40, 49, 58, 67, 76,
     0,  5, 14, 23, 32, 41, 50, 59, 68, 77,
     0,  6, 15, 24, 33, 42, 51, 60, 69, 78,
     0,  7, 16, 25, 34, 43, 52, 61, 70, 79,
     0,  8, 17, 26, 35, 44, 53, 62, 71, 80,
];

/*
 * value: 駒得のスコア
 * key: square_t
 */
immutable short[] SCORE = [
  // 歩,   香,   桂,   銀,   角,   飛,   金,     王,   と, 成香, 成桂, 成銀,   馬,   龍, 空, 壁,
     91,  243,  242,  376,  548,  658,  449,  15000,  545,  511,  523,  519,  840,  955,  0,  0,
    -91, -243, -242, -376, -548, -658, -449, -15000, -545, -511, -523, -519, -840, -955,
];

/**
 * pの静的評価値を返す
 */
short staticValue(const ref Position p)
{
    if (p.piecesInHand[Side.BLACK][Type.KING] > 0) {
        return 15000;
    }
    if (p.piecesInHand[Side.WHITE][Type.KING] > 0) {
        return -15000;
    }

    int material = 0;
    int bk = 0;
    int wk = 0;
    for (int i = 11; i <= 99; i++) {
        material += SCORE[p.squares[i]];
        bk = (p.squares[i] == Square.B_KING ? ADDRESS_OF[i      ] : bk);
        wk = (p.squares[i] == Square.W_KING ? ADDRESS_OF[110 - i] : wk);
    }
    for (int t = Type.PAWN; t <= Type.GOLD; t++) {
        material += (p.piecesInHand[Side.BLACK][t] - p.piecesInHand[Side.WHITE][t]) * SCORE[t];
    }

    int sum = 0;
    for (type_t t = Type.PAWN; t <= Type.GOLD; t++) {
        sum += FV[bk][ OFFSET_HAND[Side.BLACK][t] + p.piecesInHand[Side.BLACK][t] ];
        sum += FV[bk][ OFFSET_HAND[Side.WHITE][t] + p.piecesInHand[Side.WHITE][t] ];
        sum -= FV[wk][ OFFSET_HAND[Side.BLACK][t] + p.piecesInHand[Side.WHITE][t] ];
        sum -= FV[wk][ OFFSET_HAND[Side.WHITE][t] + p.piecesInHand[Side.BLACK][t] ];
    }
    for (int i = 11; i <= 99; i++) {
        if ((p.squares[i].isBlack() || p.squares[i].isWhite()) && p.squares[i].type() != Type.KING) {
            sum += FV[bk][ OFFSET_BOARD[p.squares[i]             ] + ADDRESS_OF[i      ] ];
            sum -= FV[wk][ OFFSET_BOARD[p.squares[i] ^ 0b00010000] + ADDRESS_OF[110 - i] ];
        }
    }
    sum /= FV_SCALE;
    return cast(short)(material + sum);
}
