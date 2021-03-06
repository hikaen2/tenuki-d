module position;

import movegen;
import std.array;
import std.container;
import std.conv;
import std.conv;
import std.format;
import std.regex;
import std.stdio;
import std.string;
import text;
import types;
import zobrist;
static import parser;

/**
 * do_move
 */
Position doMove(Position p, Move m)
{
    if (m != Move.NULL_MOVE && m != Move.TORYO) {
        if (m.isDrop) {
            type_t t = m.type;
            p.board[m.to] = Square(p.sideToMove, t);
            p.key ^= Zobrist.PSQ[p.board[m.to].i][m.to];
            p.key ^= Zobrist.HAND[p.sideToMove][t][ p.piecesInHand[p.sideToMove][t] ];
            p.piecesInHand[p.sideToMove][t]--;
            p.key ^= Zobrist.HAND[p.sideToMove][t][ p.piecesInHand[p.sideToMove][t] ];
        } else {
            // capture
            if (p.board[m.to] != Square.EMPTY) {
                type_t t = p.board[m.to].baseType;
                p.key ^= Zobrist.PSQ[p.board[m.to].i][m.to];
                p.key ^= Zobrist.HAND[p.sideToMove][t][ p.piecesInHand[p.sideToMove][t] ];
                p.piecesInHand[p.sideToMove][t]++;
                p.key ^= Zobrist.HAND[p.sideToMove][t][ p.piecesInHand[p.sideToMove][t] ];
            }
            p.board[m.to] = m.isPromote ? p.board[m.from].promote : p.board[m.from];
            p.key ^= Zobrist.PSQ[p.board[m.to].i][m.to];
            p.key ^= Zobrist.PSQ[p.board[m.from].i][m.from];
            p.board[m.from] = Square.EMPTY;
        }
    }
    p.sideToMove ^= 1;
    p.key ^= Zobrist.SIDE;
    p.moveCount++;
    p.previousMove = m;

    assert(parser.parsePosition(p.toSfen()).key == p.key); // ハッシュ値の差分計算したやつと差分計算してないやつが一致すること

    return p;
}
