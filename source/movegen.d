import types;

/**
 * 駒を取る手を返す
 */
int capturelMoves(const ref Position p, move_t[] out_moves)
{
    if (p.piecesInHand[Side.BLACK][Type.KING] > 0 || p.piecesInHand[Side.WHITE][Type.KING] > 0) {
        return 0;
    }

    // 盤上の駒を動かす
    int length = 0;
    for (int from = 11; from <= 99; from++) {
        if (!Square.isFriend(p.squares[from], p.sideToMove)) {
            continue;
        }
        foreach (dir_t d ; DIRECTIONS[Square.typeOf(p.squares[from])]) {
            int v = (p.sideToMove == Side.BLACK ? Dir.value(d) : -Dir.value(d));
            for (int to = from + v; p.squares[to] == Square.EMPTY || Square.isEnemy(p.squares[to], p.sideToMove);  to += v) {
                if (Square.isEnemy(p.squares[to], p.sideToMove)) {
                    if (canPromote(p.squares[from], from, to)) {
                        out_moves[length++] = Move.createPromote(from, to);
                        if (Square.typeOf(p.squares[from]) == Type.SILVER
                            || ((RANK_OF[to] == 3 || RANK_OF[to] == 7) && (Square.typeOf(p.squares[from]) == Type.LANCE || Square.typeOf(p.squares[from]) == Type.KNIGHT))) {
                            out_moves[length++] = Move.create(from, to); // 銀か, 3段目,7段目の香,桂なら不成も生成する
                        }
                    } else if (RANK_MIN[p.squares[from]] <= RANK_OF[to] && RANK_OF[to] <= RANK_MAX[p.squares[from]]) {
                        out_moves[length++] = Move.create(from, to);
                    }
                    break;
                }
                if (!Dir.isFly(d)) {
                    break;
                }
            }
        }
    }
    return length;
}

/**
 * 合法手を返す
 */
int legalMoves(const ref Position p, move_t[] out_moves)
{
    if (p.piecesInHand[Side.BLACK][Type.KING] > 0 || p.piecesInHand[Side.WHITE][Type.KING] > 0) {
        return 0;
    }

    bool[10] pawned = false; // 0～9筋に味方の歩があるか

    // 駒を取る手を生成する
    int length = p.capturelMoves(out_moves);

    // 盤上の駒を動かす
    for (int from = 11; from <= 99; from++) {
        if (!Square.isFriend(p.squares[from], p.sideToMove)) {
            continue;
        }
        pawned[FILE_OF[from]] |= (Square.typeOf(p.squares[from]) == Type.PAWN);
        foreach (dir_t d ; DIRECTIONS[Square.typeOf(p.squares[from])]) {
            int v = (p.sideToMove == Side.BLACK ? Dir.value(d) : -Dir.value(d));
            for (int to = from + v; p.squares[to] == Square.EMPTY; to += v) {
                if (canPromote(p.squares[from], from, to)) {
                    out_moves[length++] = Move.createPromote(from, to);
                    if (Square.typeOf(p.squares[from]) == Type.SILVER
                        || ((RANK_OF[to] == 3 || RANK_OF[to] == 7) && (Square.typeOf(p.squares[from]) == Type.LANCE || Square.typeOf(p.squares[from]) == Type.KNIGHT))) {
                        out_moves[length++] = Move.create(from, to); // 銀か, 3段目,7段目の香,桂なら不成も生成する
                    }
                } else if (RANK_MIN[p.squares[from]] <= RANK_OF[to] && RANK_OF[to] <= RANK_MAX[p.squares[from]]) {
                    out_moves[length++] = Move.create(from, to);
                }
                if (!Dir.isFly(d)) {
                    break; // 飛び駒でなければここでbreak
                }
            }
        }
    }

    // 持ち駒を打つ
    for (int to = 11; to <= 99; to++) {
        if (p.squares[to] != Square.EMPTY) {
            continue;
        }
        for (type_t t = (pawned[FILE_OF[to]] ? Type.LANCE : Type.PAWN); t <= Type.GOLD; t++) { // 歩,香,桂,銀,角,飛,金
            if (p.piecesInHand[p.sideToMove][t] > 0 && RANK_OF[to] >= RANK_MIN[p.sideToMove << 4 | t] && RANK_MAX[p.sideToMove << 4 | t] >= RANK_OF[to]) {
                out_moves[length++] = Move.createDrop(t, to);
            }
        }
    }
    return length;
}

private bool canPromote(square_t sq, int from, int to)
{
    if (Square.typeOf(sq) > Type.ROOK) {
        return false;
    }
    return (Square.isBlack(sq) ? (RANK_OF[from] <= 3 || RANK_OF[to] <= 3) : (RANK_OF[from] >= 7 || RANK_OF[to] >= 7));
}

private immutable dir_t[][] DIRECTIONS = [
    [ Dir.N ],                                                              //  0:PAWN
    [ Dir.FN ],                                                             //  1:LANCE
    [ Dir.NNE, Dir.NNW ],                                                   //  2:KNIGHT
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.SE,  Dir.SW ],                         //  3:SILVER
    [ Dir.FNE, Dir.FNW, Dir.FSE, Dir.FSW ],                                 //  4:BISHOP
    [ Dir.FN,  Dir.FE,  Dir.FW,  Dir.FS ],                                  //  5:ROOK
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  //  6:GOLD
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S,  Dir.SE, Dir.SW ], //  7:KING
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  //  8:PROMOTED_PAWN
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  //  9:PROMOTED_LANCE
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  // 10:PROMOTED_KNIGHT
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  // 11:PROMOTED_SILVER
    [ Dir.FNE, Dir.FNW, Dir.FSE, Dir.FSW, Dir.N,  Dir.E,  Dir.W,  Dir.S ],  // 12:PROMOTED_BISHOP
    [ Dir.FN,  Dir.FE,  Dir.FW,  Dir.FS,  Dir.NE, Dir.NW, Dir.SE, Dir.SW ], // 13:PROMOTED_ROOK
];

// ▲歩,香,桂,銀,角,飛,金,王,と,成香,成桂,成銀,馬,龍,-,-,△歩,香,桂,銀,角,飛,金,王,と,成香,成桂,成銀,馬,龍
private immutable ubyte[] RANK_MIN = [
    2, 2, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
];

// ▲歩,香,桂,銀,角,飛,金,王,と,成香,成桂,成銀,馬,龍,-,-,△歩,香,桂,銀,角,飛,金,王,と,成香,成桂,成銀,馬,龍
private immutable ubyte[] RANK_MAX = [
    9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 0, 0, 8, 8, 7, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
];

private immutable ubyte[] FILE_OF = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
];

private immutable ubyte[] RANK_OF = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
];
