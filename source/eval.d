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
    for (int i = SQ11; i <= SQ99; i++) {
        material += P_VALUE[p.squares[i].i];
        bk = (p.squares[i] == Square.B_KING ? ADDRESS_OF[i       ] : bk);
        wk = (p.squares[i] == Square.W_KING ? ADDRESS_OF[SQ99 - i] : wk);
    }
    for (int t = Type.PAWN; t <= Type.ROOK; t++) {
        material += (p.piecesInHand[Color.BLACK][t] - p.piecesInHand[Color.WHITE][t]) * P_VALUE[t];
    }

    // KPの計算
    int sum = 0;
    short[40] list = void;
    int nlist = 0;
    for (int i = SQ11; i <= SQ99; i++) {
        if (p.squares[i] != Square.EMPTY && p.squares[i].type != Type.KING) {
            sum += FV_KP[bk][ KP_OFFSET[p.squares[i].i    ] + ADDRESS_OF[i       ] ];
            sum -= FV_KP[wk][ KP_OFFSET[p.squares[i].inv.i] + ADDRESS_OF[SQ99 - i] ];
            list[nlist++] = cast(short)(PP_OFFSET[p.squares[i].i] + ADDRESS_OF[i]);
        }
    }
    for (type_t t = Type.PAWN; t <= Type.ROOK; t++) {
        sum += FV_KP[bk][ OFFSET_HAND[Color.BLACK][t] + p.piecesInHand[Color.BLACK][t] ];
        sum += FV_KP[bk][ OFFSET_HAND[Color.WHITE][t] + p.piecesInHand[Color.WHITE][t] ];
        sum -= FV_KP[wk][ OFFSET_HAND[Color.BLACK][t] + p.piecesInHand[Color.WHITE][t] ];
        sum -= FV_KP[wk][ OFFSET_HAND[Color.WHITE][t] + p.piecesInHand[Color.BLACK][t] ];
    }

    // PPの計算
    for (int i = 0; i < nlist; i++) {
        for (int j = i + 1; j < nlist; j++) {
            assert(FV_PP[list[i]][list[j]] == FV_PP[list[j]][list[i]]);
            sum += FV_PP[list[i]][list[j]];
        }
    }

    sum /= FV_SCALE;
    int value = material + sum;
    return cast(short)(p.sideToMove == Color.BLACK ? value : -value);
}

private enum FV_SCALE = 32;
private immutable short[1386][1386] FV_PP;
private immutable short[1476][81] FV_KP;

static this()
{
    short[1386][693] ppOri;
    File f = File("fv_mini.bin", "r");
    scope(exit) f.close();
    for (int i = 0; i < 693; i++) {
        for (int j = 0; j < 1386; j++) {
            short[1] buf;
            ppOri[i][j] = f.rawRead(buf)[0];
        }
    }

    {
        struct Hoge {
            int base, invBase, start, end;
        }
        immutable Hoge[18] tbl = [
            {PP_OFFSET[Square.B_PAWN.i]            , PP_OFFSET[Square.W_PAWN.i],             9, 81},
            {PP_OFFSET[Square.B_LANCE.i]           , PP_OFFSET[Square.W_LANCE.i] ,           9, 81},
            {PP_OFFSET[Square.B_KNIGHT.i]          , PP_OFFSET[Square.W_KNIGHT.i],          18, 81},
            {PP_OFFSET[Square.B_SILVER.i]          , PP_OFFSET[Square.W_SILVER.i],           0, 81},
            {PP_OFFSET[Square.B_GOLD.i]            , PP_OFFSET[Square.W_GOLD.i]  ,           0, 81},
            {PP_OFFSET[Square.B_BISHOP.i]          , PP_OFFSET[Square.W_BISHOP.i],           0, 81},
            {PP_OFFSET[Square.B_PROMOTED_BISHOP.i] , PP_OFFSET[Square.W_PROMOTED_BISHOP.i],  0, 81},
            {PP_OFFSET[Square.B_ROOK.i]            , PP_OFFSET[Square.W_ROOK.i]  ,           0, 81},
            {PP_OFFSET[Square.B_PROMOTED_ROOK.i]   , PP_OFFSET[Square.W_PROMOTED_ROOK.i],    0, 81},
            {PP_OFFSET[Square.W_PAWN.i]            , PP_OFFSET[Square.B_PAWN.i]  ,           0, 72},
            {PP_OFFSET[Square.W_LANCE.i]           , PP_OFFSET[Square.B_LANCE.i] ,           0, 72},
            {PP_OFFSET[Square.W_KNIGHT.i]          , PP_OFFSET[Square.B_KNIGHT.i],           0, 63},
            {PP_OFFSET[Square.W_SILVER.i]          , PP_OFFSET[Square.B_SILVER.i],           0, 81},
            {PP_OFFSET[Square.W_GOLD.i]            , PP_OFFSET[Square.B_GOLD.i]  ,           0, 81},
            {PP_OFFSET[Square.W_BISHOP.i]          , PP_OFFSET[Square.B_BISHOP.i],           0, 81},
            {PP_OFFSET[Square.W_PROMOTED_BISHOP.i] , PP_OFFSET[Square.B_PROMOTED_BISHOP.i] , 0, 81},
            {PP_OFFSET[Square.W_ROOK.i]            , PP_OFFSET[Square.B_ROOK.i]  ,           0, 81},
            {PP_OFFSET[Square.W_PROMOTED_ROOK.i]   , PP_OFFSET[Square.B_PROMOTED_ROOK.i],    0, 81},
        ];
        int inv(int sq) {
            return 81 - 1 - sq;
        }
        for (int i = 0; i < 9; i++) {
            for (int sq1 = tbl[i].start; sq1 < tbl[i].end; sq1++) {
                for (int j = 0; j < 18; j++) {
                    for (int sq2 = tbl[j].start; sq2 < tbl[j].end; sq2++) {
                        const int p1    = tbl[i].base    +     sq1;
                        const int p1inv = tbl[i].invBase + inv(sq1);
                        const int p2    = tbl[j].base    +     sq2;
                        const int p2inv = tbl[j].invBase + inv(sq2);
                        FV_PP[p1][p2] =  ppOri[p1][p2];
                        FV_PP[p1inv][p2inv] = (p2inv < PP_OFFSET[Square.W_PAWN.i] ? ppOri[p2inv][p1inv] : -ppOri[p1][p2]);
                    }
                }
            }
        }
    }

    // KP
    for (int i = 0; i < 81; i++) {
        for (int j = 0; j < 1476; j++) {
            short[1] buf;
            FV_KP[i][j] = f.rawRead(buf)[0];
        }
    }
}

/*
 * value: 駒得の評価値
 * key: Square
 */
private immutable short[] P_VALUE = [
   // 歩,   香,   桂,   銀,   金,   角,   飛,     王,   と, 成香, 成桂, 成銀,   馬,    龍,
     100,  260,  235,  392,  389,  625,  844,  15000,  458,  401,  423,  409,  800,  1164,
    -100, -260, -235, -392, -389, -625, -844, -15000, -458, -401, -423, -409, -800, -1164, 0,
];

/*
 * PPのオフセット
 * key: Square
 */
private immutable short[] PP_OFFSET = [
  // 歩,  香,  桂,  銀,  金,   角,   飛, 王,  と, 成香, 成桂, 成銀,   馬,   龍,
     -9,  63, 126, 207, 288,  369,  531,  0, 288,  288,  288,  288,  450,  612,
    693, 765, 837, 900, 981, 1062, 1224,  0, 981,  981,  981,  981, 1143, 1305, 0,
];

/*
 * FVのオフセット
 * key: [color_t][type_t]
 */
private immutable short[][] OFFSET_HAND = [
  // 歩, 香, 桂, 銀, 金, 角, 飛,
    [ 0, 38, 48, 58, 68, 78, 84, ],
    [19, 43, 53, 63, 73, 81, 87, ]
];

/*
 * KPのオフセット
 * key: Square
 */
private immutable short[] KP_OFFSET = [
  // 歩,  香,  桂,  銀,  金,  角,   飛, 王,  と, 成香, 成桂, 成銀,   馬,   龍,
     81, 225, 360, 504, 666, 828, 1152,  0, 666,  666,  666,  666,  990, 1314,
    162, 306, 441, 585, 747, 909, 1233,  0, 747,  747,  747,  747, 1071, 1395,
];

/*
 * FVのインデックス
 * key: Position.squaresのインデックス
 */
private immutable ubyte[] ADDRESS_OF = [
     0,  9, 18, 27, 36, 45, 54, 63, 72,
     1, 10, 19, 28, 37, 46, 55, 64, 73,
     2, 11, 20, 29, 38, 47, 56, 65, 74,
     3, 12, 21, 30, 39, 48, 57, 66, 75,
     4, 13, 22, 31, 40, 49, 58, 67, 76,
     5, 14, 23, 32, 41, 50, 59, 68, 77,
     6, 15, 24, 33, 42, 51, 60, 69, 78,
     7, 16, 25, 34, 43, 52, 61, 70, 79,
     8, 17, 26, 35, 44, 53, 62, 71, 80,
];
