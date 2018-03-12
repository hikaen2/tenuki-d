import types;
import text;
import std.string;
import std.stdio;
import std.format;
import std.conv;
import std.array;
import std.container;
import std.conv;
import std.regex;

/**
 * do_move
 */
Position doMove(Position p, move_t m) {
    if (m.isDrop()) {
        p.squares[m.to()] = ((p.sideToMove == Side.BLACK ? 0 : Square.W) | m.from());
        p.piecesInHand[p.sideToMove][m.from()]--;
    } else {
        // capture
        if (p.squares[m.to()] != Square.EMPTY) {
            p.piecesInHand[p.sideToMove][p.squares[m.to()].unpromote().type()]++;
        }
        p.squares[m.to()] = m.isPromote() ? p.squares[m.from()].promote() : p.squares[m.from()];
        p.squares[m.from()] = Square.EMPTY;
    }
    p.sideToMove = (p.sideToMove == Side.BLACK) ? Side.WHITE : Side.BLACK;
    return p;
}

/**
 * pの静的評価値を返す
 */
short staticValue(const ref Position p) {

    //   歩,   香,   桂,   銀,   角,   飛,   金,    王,   と, 成香, 成桂, 成銀,   馬,   龍, 空, 壁,
    immutable short[] SCORE = [
         87,  235,  254,  371,  571,  647,  447,  9999,  530,  482,  500,  489,  832,  955,  0,  0,
        -87, -235, -254, -371, -571, -647, -447, -9999, -530, -482, -500, -489, -832, -955,
    ];

    if (p.piecesInHand[Side.BLACK][Type.KING] > 0) {
        return 15000;
    }
    if (p.piecesInHand[Side.WHITE][Type.KING] > 0) {
        return -15000;
    }

    short result = 0;
    for (int i = 11; i <= 99; i++) {
        result += SCORE[p.squares[i]];
    }
    for (int t = Type.PAWN; t <= Type.ROOK; t++) {
        result += (p.piecesInHand[Side.BLACK][t] - p.piecesInHand[Side.WHITE][t]) * SCORE[t];
    }
    return result;
}

