import types;

/**
 * 局面pにおいて手番のある側が王手をかけられているかどうかを返す
 */
bool inCheck(ref Position p)
{
    move_t[128] moves;
    p.sideToMove ^= 1;
    int length = capturelMoves(p, moves);
    p.sideToMove ^= 1;
    for (int i = 0; i < length; i++) {
        if (p.squares[moves[i].to].type == Type.KING) {
            return true;
        }
    }
    return false;
}

/**
 * 局面pにおいて指し手mが有効（不正でない）かどうかを返す
 */
bool isValid(move_t m, const ref Position p)
{
    if (m.isDrop) {
        return (!m.isPromote && m.from < Type.KING && 11 <= m.to && m.to <= 99 && p.piecesInHand[p.sideToMove][m.from] > 0 && p.squares[m.to] == Square.EMPTY);
    }

    if (m.from < 11 || 99 < m.from || m.to < 11 || 99 < m.to) {
        return false;
    }
    square_t sq_from = p.squares[m.from];
    square_t sq_to = p.squares[m.to];
    if (!sq_from.isFriend(p.sideToMove)) {
        return false;
    }
    if (sq_to != Square.EMPTY && !sq_to.isEnemy(p.sideToMove)) {
        return false;
    }
    if (m.isPromote && !canPromote(sq_from, m.from, m.to)) {
        return false;
    }
    foreach (dir_t d; DIRECTIONS[sq_from]) {
        for (int to = m.from + d.value; p.squares[to] == Square.EMPTY || p.squares[to].isEnemy(p.sideToMove);  to += d.value) {
            if (to == m.to) {
                return true;
            }
            if (!d.isFly || p.squares[to].isEnemy(p.sideToMove)) {
                break;
            }
        }
    }
    return false;
}

/**
 * 駒を取る手を生成する
 * @return 生成した数
 */
int capturelMoves(const ref Position p, move_t[] out_moves)
{
    if (p.piecesInHand[Side.BLACK][Type.KING] > 0 || p.piecesInHand[Side.WHITE][Type.KING] > 0) {
        return 0;
    }

    // 盤上の駒を動かす
    int length = 0;
    for (int from = 11; from <= 99; from++) {
        if (!p.squares[from].isFriend(p.sideToMove)) {
            continue;
        }
        foreach (dir_t d; DIRECTIONS[p.squares[from]]) {
            for (int to = from + d.value; p.squares[to] == Square.EMPTY || p.squares[to].isEnemy(p.sideToMove);  to += d.value) {
                if (p.squares[to].isEnemy(p.sideToMove)) {
                    if (canPromote(p.squares[from], from, to)) {
                        out_moves[length++] = createPromote(from, to);
                        if (p.squares[from].type == Type.SILVER
                            || ((RANK_OF[to] == 3 || RANK_OF[to] == 7) && (p.squares[from].type == Type.LANCE || p.squares[from].type == Type.KNIGHT))) {
                            out_moves[length++] = createMove(from, to); // 銀か, 3段目,7段目の香,桂なら不成も生成する
                        }
                    } else if (RANK_MIN[p.squares[from]] <= RANK_OF[to] && RANK_OF[to] <= RANK_MAX[p.squares[from]]) {
                        out_moves[length++] = createMove(from, to);
                    }
                    break;
                }
                if (!d.isFly) {
                    break;
                }
            }
        }
    }
    return length;
}

/**
 * 合法手を生成する
 * @return 生成した数
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
        if (!p.squares[from].isFriend(p.sideToMove)) {
            continue;
        }
        pawned[FILE_OF[from]] |= (p.squares[from].type == Type.PAWN);
        foreach (dir_t d; DIRECTIONS[p.squares[from]]) {
            for (int to = from + d.value; p.squares[to] == Square.EMPTY; to += d.value) {
                if (canPromote(p.squares[from], from, to)) {
                    out_moves[length++] = createPromote(from, to);
                    if (p.squares[from].type == Type.SILVER
                        || ((RANK_OF[to] == 3 || RANK_OF[to] == 7) && (p.squares[from].type == Type.LANCE || p.squares[from].type == Type.KNIGHT))) {
                        out_moves[length++] = createMove(from, to); // 銀か, 3段目,7段目の香,桂なら不成も生成する
                    }
                } else if (RANK_MIN[p.squares[from]] <= RANK_OF[to] && RANK_OF[to] <= RANK_MAX[p.squares[from]]) {
                    out_moves[length++] = createMove(from, to);
                }
                if (!d.isFly) {
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
                out_moves[length++] = createDrop(t, to);
            }
        }
    }
    return length;
}

private bool canPromote(square_t sq, int from, int to)
{
    if (sq.type > Type.ROOK) {
        return false;
    }
    return (sq.isBlack ? (RANK_OF[from] <= 3 || RANK_OF[to] <= 3) : (RANK_OF[from] >= 7 || RANK_OF[to] >= 7));
}

private immutable dir_t[][] DIRECTIONS = [
    [ Dir.N  ],                                                             //  0:B_PAWN
    [ Dir.FN ],                                                             //  1:B_LANCE
    [ Dir.NNE, Dir.NNW ],                                                   //  2:B_KNIGHT
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.SE,  Dir.SW ],                         //  3:B_SILVER
    [ Dir.FNE, Dir.FNW, Dir.FSE, Dir.FSW ],                                 //  4:B_BISHOP
    [ Dir.FN,  Dir.FE,  Dir.FW,  Dir.FS  ],                                 //  5:B_ROOK
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  //  6:B_GOLD
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S,  Dir.SE, Dir.SW ], //  7:B_KING
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  //  8:B_PROMOTED_PAWN
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  //  9:B_PROMOTED_LANCE
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  // 10:B_PROMOTED_KNIGHT
    [ Dir.N,   Dir.NE,  Dir.NW,  Dir.E,   Dir.W,  Dir.S ],                  // 11:B_PROMOTED_SILVER
    [ Dir.FNE, Dir.FNW, Dir.FSE, Dir.FSW, Dir.N,  Dir.E,  Dir.W,  Dir.S  ], // 12:B_PROMOTED_BISHOP
    [ Dir.FN,  Dir.FE,  Dir.FW,  Dir.FS,  Dir.NE, Dir.NW, Dir.SE, Dir.SW ], // 13:B_PROMOTED_ROOK
    [],                                                                     // 14:EMPTY
    [],                                                                     // 15:WALL
    [ Dir.S  ],                                                             // 16:W_PAWN
    [ Dir.FS ],                                                             // 17:W_LANCE
    [ Dir.SSW, Dir.SSE ],                                                   // 18:W_KNIGHT
    [ Dir.S,   Dir.SW,  Dir.SE,  Dir.NW,  Dir.NE ],                         // 19:W_SILVER
    [ Dir.FSW, Dir.FSE, Dir.FNW, Dir.FNE ],                                 // 20:W_BISHOP
    [ Dir.FS,  Dir.FW,  Dir.FE,  Dir.FN  ],                                 // 21:W_ROOK
    [ Dir.S,   Dir.SW,  Dir.SE,  Dir.W,   Dir.E,  Dir.N ],                  // 22:W_GOLD
    [ Dir.S,   Dir.SW,  Dir.SE,  Dir.W,   Dir.E,  Dir.N,  Dir.NW, Dir.NE ], // 23:W_KING
    [ Dir.S,   Dir.SW,  Dir.SE,  Dir.W,   Dir.E,  Dir.N ],                  // 24:W_PROMOTED_PAWN
    [ Dir.S,   Dir.SW,  Dir.SE,  Dir.W,   Dir.E,  Dir.N ],                  // 25:W_PROMOTED_LANCE
    [ Dir.S,   Dir.SW,  Dir.SE,  Dir.W,   Dir.E,  Dir.N ],                  // 26:W_PROMOTED_KNIGHT
    [ Dir.S,   Dir.SW,  Dir.SE,  Dir.W,   Dir.E,  Dir.N ],                  // 27:W_PROMOTED_SILVER
    [ Dir.FSW, Dir.FSE, Dir.FNW, Dir.FNE, Dir.S,  Dir.W,  Dir.E,  Dir.N  ], // 28:W_PROMOTED_BISHOP
    [ Dir.FS,  Dir.FW,  Dir.FE,  Dir.FN,  Dir.SW, Dir.SE, Dir.NW, Dir.NE ], // 29:W_PROMOTED_ROOK
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
