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
