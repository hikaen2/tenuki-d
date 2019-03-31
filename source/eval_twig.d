import types;
import std.stdio;


private enum FV_SCALE = 32;
private immutable int[2][81][81] KK;
private immutable int[2][1548][81][81] KKP;
private immutable short[2][1548][1548][81] KPP;

/**
 * 静的コンストラクタ
 * 評価関数バイナリをロードする
 */
/*
static this()
{
    {
        File f = File("KK_synthesized.bin", "r");
        scope (exit) {
            f.close();
        }
        for (int i = 0; i < 81; i++) {
            for (int j = 0; j < 81; j++) {
                int[2] buf;
                KK[i][j] = f.rawRead(buf);
            }
        }
    }

    {
        File f = File("KKP_synthesized.bin", "r");
        scope (exit) {
            f.close();
        }
        for (int i = 0; i < 81; i++) {
            for (int j = 0; j < 81; j++) {
                for (int k = 0; k < 1548; k++) {
                    int[2] buf;
                    KKP[i][j][k] = f.rawRead(buf);
                }
            }
        }
    }

    {
        File f = File("KPP_synthesized.bin", "r");
        scope (exit) {
            f.close();
        }
        for (int i = 0; i < 81; i++) {
            for (int j = 0; j < 1548; j++) {
                for (int k = 0; k < 1548; k++) {
                    short[2] buf;
                    KPP[i][j][k] = f.rawRead(buf);
                }
            }
        }
    }
}
*/

/**
 * 手番のある側から見た評価値を返す
 */
/*
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
        material += P_VALUE[p.board[i].i];
        bk = (p.board[i] == Square.B_KING) ? i : bk;
        wk = (p.board[i] == Square.W_KING) ? i : wk;
    }
    // 持ち駒
    for (int t = Type.PAWN; t <= Type.ROOK; t++) {
        material += (p.piecesInHand[Color.BLACK][t] - p.piecesInHand[Color.WHITE][t]) * P_VALUE[t];
    }

    // リストを作る
    short[40] list_fb;
    short[40] list_fw;
    int length = 0;
    for (int i = SQ11; i <= SQ99; i++) {
        if (p.board[i] != Square.EMPTY && p.board[i].type != Type.KING) {
            list_fb[length] = cast(short)(PP_OFFSET[p.board[i].i] + i);
            list_fw[length] = cast(short)(PP_OFFSET[p.board[i].i] + i);
            length++;
        }
    }

    // KK
    int sum2_0 = KK[bk][wk][0];
    int sum2_1 = KK[bk][wk][1];

    for (i = 0; i < length ; i++) {
        int k0 = list_fb[i];
        int k1 = list_fw[i];

        // KKP
        sum2_0 += KKP[bk][wk][k0][0];
        sum2_1 += KKP[bk][wk][k0][1];

        for (j = 0; j < i; j++) {
            int l0 = list_fb[j];
            int l1 = list_fw[j];

            // KPP
            sum0_0 += KPP[bk][k0][l0][0];
            sum0_1 += KPP[bk][k0][l0][1];
            sum1_0 += KPP[inv(wk)][k1][l1][0];
            sum1_1 += KPP[inv(wk)][k1][l1][1];
        }
    }

    sum /= FV_SCALE;
    int value = material + sum;
    return cast(short)(p.sideToMove == Color.BLACK ? value : -value);
}
*/


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
    [ 0, 38, 48, 58, 68, 78, 84, ],
    [19, 43, 53, 63, 73, 81, 87, ],
];

/*
 * 駒からオフセットを引く表
 * key: Square
 * see https://github.com/HiraokaTakuya/apery/blob/32216277e51c3b008e3c8eea6954f1bb3c416b57/src/evaluate.hpp#L36
 */
private immutable short[] PP_OFFSET = [
  // 歩,  香,  桂,  銀,  金,  角,   飛, 王,  と, 成香, 成桂, 成銀,   馬,   龍,
     90, 252, 414, 576, 738, 900, 1224,  0, 738,  738,  738,  738, 1062, 1386,
    171, 333, 495, 657, 819, 981, 1305,  0, 819,  819,  819,  819, 1143, 1467,
];
