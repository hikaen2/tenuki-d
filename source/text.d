import types;
import position;
import eval;
import hash_seed;
import std.string;
import std.stdio;
import std.format;
import std.conv;
import std.array;
import std.container;
import std.conv;
import std.regex;
import std.ascii;
import std.array;
import std.regex;
import std.conv;

/**
 * 手をCSA形式の文字列にする
 */
string toString(move_t m, const ref Position p)
{
    //    歩,   香,   桂,   銀,  角,    飛,   金,   玉,   と, 成香, 成桂, 成銀,   馬,   龍,
    immutable string[] CSA = [
        "FU", "KY", "KE", "GI", "KA", "HI", "KI", "OU", "TO", "NY", "NK", "NG", "UM", "RY",
    ];
    int from = m.isDrop() ? 0 : m.from();
    int to = m.to();
    type_t t = m.isDrop() ? m.from() : m.isPromote() ? p.squares[m.from()].promote().type() : p.squares[m.from()].type();
    return format("%s%02d%02d%s", (p.sideToMove == Side.BLACK ? "+" : "-"), from, to, CSA[t]);
}


string toString(const ref Position p)
{
    return format("hash: 0x%016x\nstaticValue: %d\n%s\n", p.hash, p.staticValue(), p.toKi2());
}

/**
 * 局面をSFEN形式の文字列にする
 */
string toSfen(const ref Position p)
{
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

/**
 * 局面をKI2形式の文字列にする
 */
string toKi2(const ref Position p)
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

    // ハッシュ値
    p.hash = 0;
    for (int i = 11; i <= 99; i++) {
        p.hash ^= HASH_SEED_BOARD[ p.squares[i] ][i];
    }
    for (side_t s = Side.BLACK; s <= Side.WHITE; s++) {
        for (type_t t = Type.PAWN; t <= Type.KING; t++) {
            p.hash ^= HASH_SEED_HAND[s][t][ p.piecesInHand[s][t] ];
        }
    }
    return p;
}

move_t parseMove(string s, const ref Position p)
{
    immutable type_t[string] DIC = [
        "FU": Type.PAWN,
        "KY": Type.LANCE,
        "KE": Type.KNIGHT,
        "GI": Type.SILVER,
        "KI": Type.GOLD,
        "KA": Type.BISHOP,
        "HI": Type.ROOK,
        "OU": Type.KING,
        "TO": Type.PROMOTED_PAWN,
        "NY": Type.PROMOTED_LANCE,
        "NK": Type.PROMOTED_KNIGHT,
        "NG": Type.PROMOTED_SILVER,
        "UM": Type.PROMOTED_BISHOP,
        "RY": Type.PROMOTED_ROOK,
    ];

    auto m = s.match(regex("(-|\\+)(\\d{2})(\\d{2})(\\w{2})"));
    int from = to!int(m.front[2]);
    int to = to!int(m.front[3]);
    type_t t = DIC[m.front[4]];

    if (from == 0) {
        return createDrop(t, to); // fromが0なら駒打ち
    } else if (t != p.squares[from].type()) {
        return createPromote(from, to); // 成る
    } else {
        return createMove(from, to);
    }
}
