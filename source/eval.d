// eval.d.nnue
module eval;

import core.stdc.stdio;
import std.algorithm;
import std.exception;
import std.stdint;
import std.stdio;
import types;

private enum FV_SCALE = 16;
__gshared private int16_t[256]             featureTransformerBiases;
__gshared private int16_t[256 * 81 * 1548] featureTransformerWeights;
__gshared private int32_t[32]              hiddenLayer1Biases;
__gshared private int8_t [32 * 512]        hiddenLayer1Weights;
__gshared private int32_t[32]              hiddenLayer2Biases;
__gshared private int8_t [32 * 32]         hiddenLayer2Weights;
__gshared private int32_t[1]               outputLayerBiases;
__gshared private int8_t [1 * 32]          outputLayerWeights;


/**
 * 静的コンストラクタ
 * 評価関数バイナリをロードする
 */
shared static this()
{
    File f = File("nn.bin", "r");

    uint32_t[] version_ = f.rawRead(new uint32_t[1]);
    uint32_t[] hash = f.rawRead(new uint32_t[1]);
    uint32_t[] size = f.rawRead(new uint32_t[1]);
    char[] architecture = f.rawRead(new char[size[0]]); // char[178]
    uint32_t[] header1 = f.rawRead(new uint32_t[1]);
    f.rawRead(featureTransformerBiases);
    f.rawRead(featureTransformerWeights);
    uint32_t[] header2 = f.rawRead(new uint32_t[1]);
    f.rawRead(hiddenLayer1Biases);
    f.rawRead(hiddenLayer1Weights);
    f.rawRead(hiddenLayer2Biases);
    f.rawRead(hiddenLayer2Weights);
    f.rawRead(outputLayerBiases);
    f.rawRead(outputLayerWeights);
    enforce(f.tell == f.size, "invalid loading");
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

    int bk = 0;
    int wk = 0;
    int[38] blist;
    int[38] wlist;
    int length = 0;

    for (int i = SQ11; i <= SQ99; i++) {
        if (pos.board[i] == Square.B_KING) bk =      i;
        if (pos.board[i] == Square.W_KING) wk = 80 - i;
    }

    // 持ち駒
    for (int t = Type.PAWN; t <= Type.ROOK; t++) {
        for (int i = 0; i < pos.piecesInHand[Color.BLACK][t]; i++) {
            blist[length] = bk * 1548 + OFFSET_HAND[Color.BLACK][t] + i;
            wlist[length] = wk * 1548 + OFFSET_HAND[Color.WHITE][t] + i;
            length++;
        }
        for (int i = 0; i < pos.piecesInHand[Color.WHITE][t]; i++) {
            blist[length] = bk * 1548 + OFFSET_HAND[Color.WHITE][t] + i;
            wlist[length] = wk * 1548 + OFFSET_HAND[Color.BLACK][t] + i;
            length++;
        }
    }
    for (int i = SQ11; i <= SQ99; i++) {
        Square sq = pos.board[i];
        if (sq != Square.EMPTY && sq.type != Type.KING) {
            blist[length] = bk * 1548 + OFFSET_PP[sq.i] + i;
            wlist[length] = wk * 1548 + OFFSET_PP[sq.inv.i] + (SQ99 - i);
            length++;
        }
    }
    assert(length == 38);

    int16_t[256] yb;
    int16_t[256] yw;
    w1(blist.ptr, featureTransformerBiases.ptr, featureTransformerWeights.ptr, yb.ptr); // blistからybを作る（先手の分）
    w1(wlist.ptr, featureTransformerBiases.ptr, featureTransformerWeights.ptr, yw.ptr); // wlistからybを作る（後手の分）

    uint8_t[512] z1;
    if (pos.sideToMove == Color.BLACK) {
        transform(yb.ptr, yw.ptr, z1.ptr); // yb, ywを連結してz1を作る（先手番）
    } else {
        transform(yw.ptr, yb.ptr, z1.ptr); // yw, ybを連結してz1を作る（後手番）
    }

    uint8_t[32] z2;
    w2(z1.ptr, hiddenLayer1Biases.ptr, hiddenLayer1Weights.ptr, z2.ptr); // z1からz2を作る

    uint8_t[32] z3;
    w3(z2.ptr, hiddenLayer2Biases.ptr, hiddenLayer2Weights.ptr, z3.ptr); // z2からz3を作る

    int32_t[1] z4;
    w4(z3.ptr, outputLayerBiases.ptr, outputLayerWeights.ptr, z4.ptr); // z3からz4を作る

    return cast(short)(z4[0] / 16);
}

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



private void transform(int16_t* p0, int16_t* p1, uint8_t* output) {
    for (int i = 0; i < 256; i++) {
        output[0 * 256 + i] = cast(uint8_t)(max(0, min(127, p0[i])));
    }
    for (int i = 0; i < 256; i++) {
        output[1 * 256 + i] = cast(uint8_t)(max(0, min(127, p1[i])));
    }
}

private void w1(int* kp, int16_t* biases, int16_t* weights, int16_t* output) {
    for (int i = 0; i < 256; i++) { // 行
        output[i] = biases[i];
    }
    for (int j = 0; j < 38; j++) { // 列
        for (int i = 0; i < 256; i++) { // 行
            output[i] += weights[kp[j] * 256 + i];
        }
    }
}

// ClippedReLU[32](AffineTransform[32<-512])
private void w2(uint8_t* input, int32_t* biases, int8_t* weights, uint8_t* output) {
    for (int i = 0; i < 32; i++) { // 行
        int32_t sum = biases[i];
        for (int j = 0; j < 512; j++) { // 列
            sum += weights[i * 512 + j] * input[j];
        }
        output[i] = cast(uint8_t)(max(0, min(127, sum >> 6)));
    }
}

// ClippedReLU[32](AffineTransform[32<-32])
private void w3(uint8_t* input, int32_t* biases, int8_t* weights, uint8_t* output) {
    for (int i = 0; i < 32; i++) { // 行
        int32_t sum = biases[i];
        for (int j = 0; j < 32; j++) { // 列
            sum += weights[i * 32 + j] * input[j];
        }
        output[i] = cast(uint8_t)(max(0, min(127, sum >> 6)));
    }
}

// AffineTransform[1<-32]
private void w4(uint8_t* input, int32_t* biases, int8_t* weights, int32_t* output) {
    for (int i = 0; i < 1; i++) { // 行
        int32_t sum = biases[i];
        for (int j = 0; j < 32; j++) { // 列
            sum += weights[i * 32 + j] * input[j];
        }
        output[i] = sum;
    }
}
