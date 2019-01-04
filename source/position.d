import types;
import text;
import movegen;
import std.string;
import std.stdio;
import std.format;
import std.conv;
import std.array;
import std.container;
import std.conv;
import std.regex;
static import zobrist;

/**
 * do_move
 */
Position doMove(Position p, Move m)
{
    if (m != Move.NULL_MOVE && m != Move.TORYO) {
        if (m.isDrop) {
            type_t t = m.type;
            p.squares[m.to] = Square(p.sideToMove, t);
            p.hash ^= zobrist.PSQ[p.squares[m.to].i][m.to];
            p.hash ^= zobrist.HAND[p.sideToMove][t][ p.piecesInHand[p.sideToMove][t] ];
            p.piecesInHand[p.sideToMove][t]--;
            p.hash ^= zobrist.HAND[p.sideToMove][t][ p.piecesInHand[p.sideToMove][t] ];
        } else {
            // capture
            if (p.squares[m.to] != Square.EMPTY) {
                type_t t = p.squares[m.to].baseType;
                p.hash ^= zobrist.PSQ[p.squares[m.to].i][m.to];
                p.hash ^= zobrist.HAND[p.sideToMove][t][ p.piecesInHand[p.sideToMove][t] ];
                p.piecesInHand[p.sideToMove][t]++;
                p.hash ^= zobrist.HAND[p.sideToMove][t][ p.piecesInHand[p.sideToMove][t] ];
            }
            p.squares[m.to] = m.isPromote ? p.squares[m.from].promote : p.squares[m.from];
            p.hash ^= zobrist.PSQ[p.squares[m.to].i][m.to];
            p.hash ^= zobrist.PSQ[p.squares[m.from].i][m.from];
            p.squares[m.from] = Square.EMPTY;
        }
    }
    p.sideToMove ^= 1;
    p.hash ^= zobrist.SIDE;
    p.moveCount++;
    p.previousMove = m;
    return p;
}
