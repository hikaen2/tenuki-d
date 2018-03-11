import types;
import std.string;
import std.stdio;
import std.format;
import std.conv;

/**
 * do_move
 */
Position doMove(Position p, move_t m) {
    if (Move.isDrop(m)) {
        p.squares[Move.to(m)] = ((p.sideToMove == Side.BLACK ? 0 : Square.W) | Move.from(m));
        p.piecesInHand[p.sideToMove][Move.from(m)]--;
    } else {
        // capture
        if (p.squares[Move.to(m)] != Square.EMPTY) {
            p.piecesInHand[p.sideToMove][Square.typeOf(Square.unpromote(p.squares[Move.to(m)]))]++;
        }
        p.squares[Move.to(m)] = Move.isPromote(m) ? Square.promote(p.squares[Move.from(m)]) : p.squares[Move.from(m)];
        p.squares[Move.from(m)] = Square.EMPTY;
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

    short result = 0;
    for (int i = 11; i <= 99; i++) {
        result += SCORE[p.squares[i]];
    }
    for (int t = Type.PAWN; t <= Type.ROOK; t++) {
        result += (p.piecesInHand[Side.BLACK][t] - p.piecesInHand[Side.WHITE][t]) * SCORE[t];
    }
    return result;
}

string toString(move_t m, const ref Position p)
{
    //    歩,   香,   桂,   銀,  角,    飛,   金,   玉,   と, 成香, 成桂, 成銀,   馬,   龍,
    immutable string[] CSA = [
        "FU", "KY", "KE", "GI", "KA", "HI", "KI", "OU", "TO", "NY", "NK", "NG", "UM", "RY",
    ];
    int from = Move.isDrop(m) ? 0 : Move.from(m);
    int to = Move.to(m);
    type_t t = Move.isDrop(m) ? Move.from(m) : Move.isPromote(m) ? Square.typeOf(Square.promote(p.squares[Move.from(m)])) : Square.typeOf(p.squares[Move.from(m)]);
    return format("%s%02d%02d%s", (p.sideToMove == Side.BLACK ? "+" : "-"), from, to, CSA[t]);
}

string toString(const ref Position p)
{
    immutable string[] BOARD = [
        " 歩", " 香", " 桂", " 銀", " 角", " 飛", " 金", " 玉", " と", " 杏", " 圭", " 全", " 馬", " 龍", " ・", " 壁",
        "v歩", "v香", "v桂", "v銀", "v角", "v飛", "v金", "v玉", "vと", "v杏", "v圭", "v全", "v馬", "v龍",
    ];

    immutable string[] HAND = [
        "歩", "香", "桂", "銀", "角", "飛", "金",
    ];

    immutable string[] NUM = [
        "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八",
    ];

    string[2] hand;
    for (side_t s = Side.BLACK; s <= Side.WHITE; s++) {
        for (type_t t = Type.PAWN; t <= Type.GOLD; t++) {
            int n = p.piecesInHand[s][t];
            if (n > 0) {
                hand[s] ~= format("%s%s　", HAND[t], (n > 1 ? NUM[n] : ""));
            }
        }
    }

    string s;
    s ~= format("後手の持駒：%s\n", (hand[Side.WHITE] == "" ? "なし" : hand[Side.WHITE]));
    s ~= "  ９ ８ ７ ６ ５ ４ ３ ２ １\n";
    s ~= "+---------------------------+\n";
    for (int rank = 1; rank <= 9; rank++) {
        s ~= "|";
        for (int file = 9; file >= 1; file--) {
            s ~= BOARD[p.squares[file * 10 + rank]];
        }
        s ~= format("|%s\n", NUM[rank]);
    }
    s ~= "+---------------------------+\n";
    s ~= format("先手の持駒：%s\n", (hand[Side.BLACK] == "" ? "なし" : hand[Side.BLACK]));
    return s;
}

Position createPosition(string sfen)
{
    immutable square_t[string] TO_SQUARE = [
        "1":  Square.EMPTY,
        "P":  Square.B_PAWN,
        "L":  Square.B_LANCE,
        "N":  Square.B_KNIGHT,
        "S":  Square.B_SILVER,
        "B":  Square.B_BISHOP,
        "R":  Square.B_ROOK,
        "G":  Square.B_GOLD,
        "K":  Square.B_KING,
        "+P": Square.B_PROMOTED_PAWN,
        "+L": Square.B_PROMOTED_LANCE,
        "+N": Square.B_PROMOTED_KNIGHT,
        "+S": Square.B_PROMOTED_SILVER,
        "+B": Square.B_PROMOTED_BISHOP,
        "+R": Square.B_PROMOTED_ROOK,
        "p":  Square.W_PAWN,
        "l":  Square.W_LANCE,
        "n":  Square.W_KNIGHT,
        "s":  Square.W_SILVER,
        "b":  Square.W_BISHOP,
        "r":  Square.W_ROOK,
        "g":  Square.W_GOLD,
        "k":  Square.W_KING,
        "+p": Square.W_PROMOTED_PAWN,
        "+l": Square.W_PROMOTED_LANCE,
        "+n": Square.W_PROMOTED_KNIGHT,
        "+s": Square.W_PROMOTED_SILVER,
        "+b": Square.W_PROMOTED_BISHOP,
        "+r": Square.W_PROMOTED_ROOK,
    ];

    immutable type_t[string] TO_TYPE = [
        "P":  Type.PAWN,
        "L":  Type.LANCE,
        "N":  Type.KNIGHT,
        "S":  Type.SILVER,
        "B":  Type.BISHOP,
        "R":  Type.ROOK,
        "G":  Type.GOLD,
        "p":  Type.PAWN,
        "l":  Type.LANCE,
        "n":  Type.KNIGHT,
        "s":  Type.SILVER,
        "b":  Type.BISHOP,
        "r":  Type.ROOK,
        "g":  Type.GOLD,
    ];

    import std.ascii;
    import std.array;
    import std.regex;
    import std.conv;
    Position p;
    p.squares = Square.WALL;

    string[] ss = sfen.strip().split(regex("\\s+"));
    string boardState = ss[0];
    string sideToMove = ss[1];
    string piecesInHand = ss[2];
    string moveCount = ss[3];

    // 手番
    if (sideToMove != "b" && sideToMove != "w") {
        throw new StringException(sfen);
    }
    p.sideToMove = sideToMove == "b" ? Side.BLACK : Side.WHITE;

    // 盤面
    for (int i = 9; i >= 2; i--) {
        boardState = boardState.replace(to!string(i), "1".replicate(i)); // 2～9を1に開いておく
    }
    boardState = boardState.replace("/", "");
    auto m = boardState.matchAll(regex("\\+?."));
    for (int rank = 1; rank <= 9; rank++) {
        for (int file = 9; file >= 1; file--) {
            p.squares[file * 10 + rank] = TO_SQUARE[m.front.hit];
            m.popFront();
        }
    }

    // 持ち駒
    if (piecesInHand != "-") {
        // 例：S, 4P, b, 3n, p, 18P
        foreach (c; piecesInHand.matchAll(regex("(\\d*)(\\D)"))) {
            int num = (c[1] == "") ? 1 : to!int(c[1]);
            string piece = c[2];
            p.piecesInHand[piece[0].isUpper() ? Side.BLACK : Side.WHITE][TO_TYPE[piece]] += num;
        }
    }
    return p;
}

string toSfen(const ref Position p)
{
    import std.array;
    import std.container;
    import std.conv;

    //   歩,  香,  桂,  銀,  角,  飛,  金,  王,   と, 成香, 成桂, 成銀,   馬,   龍,  空, 壁
    immutable string[] TO_SFEN = [
        "P", "L", "N", "S", "B", "R", "G", "K", "+P", "+L", "+N", "+S", "+B", "+R", "1", "",
        "p", "l", "n", "s", "b", "r", "g", "k", "+p", "+l", "+n", "+s", "+b", "+r",
    ];

    Array!string lines;
    for (int rank = 1; rank <= 9; rank++) {
        string line;
        for (int file = 9; file >= 1; file--) {
            line ~= TO_SFEN[p.squares[file * 10 + rank]];
        }
        lines.insert(line);
    }
    string s = lines[].join("/");
    for (int i = 9; i >= 2; i--) {
        s = s.replace("1".replicate(i), to!string(i)); // '1'をまとめる
    }
    return s;
}
