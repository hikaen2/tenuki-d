
alias color_t = ubyte;
alias type_t = ubyte;

/**
 * 局面
 *
 * squares[81]:
 *  9  8  7  6  5  4  3  2  1
 * --------------------------+
 * 72 63 54 45 36 27 18  9  0|一
 * 73 64 55 46 37 28 19 10  1|二
 * 74 65 56 47 38 29 20 11  2|三
 * 75 66 57 48 39 30 21 12  3|四
 * 76 67 58 49 40 31 22 13  4|五
 * 77 68 59 50 41 32 23 14  5|六
 * 78 69 60 51 42 33 24 15  6|七
 * 79 70 61 52 43 34 25 16  7|八
 * 80 71 62 53 44 35 26 17  8|九
 *
 */
struct Position
{
    Square[81] squares;
    ubyte[8][2] piecesInHand;
    bool sideToMove;
    ulong key;
    ushort moveCount = 1;
    Move previousMove; // 直前の指し手
}

enum Color : color_t
{
    BLACK             = 0,  // 先手
    WHITE             = 1,  // 後手
}

enum Type : type_t
{
    PAWN              = 0,  // 歩
    LANCE             = 1,  // 香
    KNIGHT            = 2,  // 桂
    SILVER            = 3,  // 銀
    GOLD              = 4,  // 金
    BISHOP            = 5,  // 角
    ROOK              = 6,  // 飛
    KING              = 7,  // 王
    PROMOTED_PAWN     = 8,  // と
    PROMOTED_LANCE    = 9,  // 成香
    PROMOTED_KNIGHT   = 10, // 成桂
    PROMOTED_SILVER   = 11, // 成銀
    PROMOTED_BISHOP   = 12, // 馬
    PROMOTED_ROOK     = 13, // 龍
    EMPTY             = 14, // 空
}

/**
 * 升
 */
struct Square
{
    enum Square B_PAWN            = Square(0);
    enum Square B_LANCE           = Square(1);
    enum Square B_KNIGHT          = Square(2);
    enum Square B_SILVER          = Square(3);
    enum Square B_GOLD            = Square(4);
    enum Square B_BISHOP          = Square(5);
    enum Square B_ROOK            = Square(6);
    enum Square B_KING            = Square(7);
    enum Square B_PROMOTED_PAWN   = Square(8);
    enum Square B_PROMOTED_LANCE  = Square(9);
    enum Square B_PROMOTED_KNIGHT = Square(10);
    enum Square B_PROMOTED_SILVER = Square(11);
    enum Square B_PROMOTED_BISHOP = Square(12);
    enum Square B_PROMOTED_ROOK   = Square(13);
    enum Square W_PAWN            = Square(14);
    enum Square W_LANCE           = Square(15);
    enum Square W_KNIGHT          = Square(16);
    enum Square W_SILVER          = Square(17);
    enum Square W_GOLD            = Square(18);
    enum Square W_BISHOP          = Square(19);
    enum Square W_ROOK            = Square(20);
    enum Square W_KING            = Square(21);
    enum Square W_PROMOTED_PAWN   = Square(22);
    enum Square W_PROMOTED_LANCE  = Square(23);
    enum Square W_PROMOTED_KNIGHT = Square(24);
    enum Square W_PROMOTED_SILVER = Square(25);
    enum Square W_PROMOTED_BISHOP = Square(26);
    enum Square W_PROMOTED_ROOK   = Square(27);
    enum Square EMPTY             = Square(28);

    ubyte i;
    this(ubyte i) { this.i = i; }
    this(color_t c, type_t t) { this.i = cast(ubyte)(c * Square.W_PAWN.i + t); }
    bool isBlack() const { return COLOR[i] == Color.BLACK; }
    bool isWhite() const { return COLOR[i] == Color.WHITE; }
    bool isFriend(color_t c) const { return COLOR[i] == c; }
    bool isEnemy(color_t c) const { return COLOR[i] == (c ^ 1); }
    bool isPromotable() const { return PROMOTABLE[i]; }
    type_t type() const { return TYPE[i]; }
    type_t baseType() const { return BASETYPE[i]; }
    Square promote() const { return PROMOTE[i]; }
    Square inv() const { return INV[i]; }
}

/**
 * Direction
 * 1111111x value
 * xxxxxxx1 fly
 */
struct Dir {
    enum Dir N   = {-1 * 2}; // -1 << 1
    enum Dir E   = {-9 * 2}; // -9 << 1
    enum Dir W   = {+9 * 2}; // +9 << 1
    enum Dir S   = {+1 * 2}; // +1 << 1
    enum Dir NE  = {N.i + E.i};
    enum Dir NW  = {N.i + W.i};
    enum Dir SE  = {S.i + E.i};
    enum Dir SW  = {S.i + W.i};
    enum Dir NNE = {N.i + N.i + E.i};
    enum Dir NNW = {N.i + N.i + W.i};
    enum Dir SSE = {S.i + S.i + E.i};
    enum Dir SSW = {S.i + S.i + W.i};
    enum Dir FN  = {N.i | 1};
    enum Dir FE  = {E.i | 1};
    enum Dir FW  = {W.i | 1};
    enum Dir FS  = {S.i | 1};
    enum Dir FNE = {NE.i | 1};
    enum Dir FNW = {NW.i | 1};
    enum Dir FSE = {SE.i | 1};
    enum Dir FSW = {SW.i | 1};

    byte i;
    bool isFly() const { return (i & 1) != 0; }
    int  value() const { return i >> 1; }
}

/**
 * 手
 * 1xxxxxxx xxxxxxxx promote
 * x1xxxxxx xxxxxxxx drop
 * xx111111 1xxxxxxx from
 * xxxxxxxx x1111111 to
 */
struct Move
{
    enum Move NULL      = {0};
    enum Move NULL_MOVE = {0b00111111_11111110};
    enum Move TORYO     = {0b00111111_11111111};

    ushort i;
    ubyte type() const { return cast(ubyte)((i >> 7) & 0b01111111); }
    ubyte from() const { return cast(ubyte)((i >> 7) & 0b01111111); }
    ubyte to() const { return cast(ubyte)(i & 0b01111111); }
    bool isPromote() const { return (i & 0b1000000000000000) != 0; }
    bool isDrop() const { return (i & 0b0100000000000000) != 0; }
}

// move_tを返す関数
Move createMove(int from, int to) { return Move(cast(ushort)(from << 7 | to)); }
Move createPromote(int from, int to) { return Move(cast(ushort)(from << 7 | to | 0b1000000000000000)); }
Move createDrop(type_t t, int to) { return Move(cast(ushort)(t << 7 | to | 0b0100000000000000)); }


enum SQ11 = 0;
enum SQ99 = 80;


private immutable color_t[] COLOR = [
    Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK,
    Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK,
    Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE,
    Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE,
    255,
];

private immutable type_t[] TYPE = [
    Type.PAWN, Type.LANCE, Type.KNIGHT, Type.SILVER, Type.GOLD, Type.BISHOP, Type.ROOK, Type.KING,
    Type.PROMOTED_PAWN, Type.PROMOTED_LANCE, Type.PROMOTED_KNIGHT, Type.PROMOTED_SILVER, Type.PROMOTED_BISHOP, Type.PROMOTED_ROOK,
    Type.PAWN, Type.LANCE, Type.KNIGHT, Type.SILVER, Type.GOLD, Type.BISHOP, Type.ROOK, Type.KING,
    Type.PROMOTED_PAWN, Type.PROMOTED_LANCE, Type.PROMOTED_KNIGHT, Type.PROMOTED_SILVER, Type.PROMOTED_BISHOP, Type.PROMOTED_ROOK,
    Type.EMPTY
];

private immutable type_t[] BASETYPE = [
    Type.PAWN, Type.LANCE, Type.KNIGHT, Type.SILVER, Type.GOLD, Type.BISHOP, Type.ROOK, Type.KING,
    Type.PAWN, Type.LANCE, Type.KNIGHT, Type.SILVER, Type.BISHOP, Type.ROOK,
    Type.PAWN, Type.LANCE, Type.KNIGHT, Type.SILVER, Type.GOLD, Type.BISHOP, Type.ROOK, Type.KING,
    Type.PAWN, Type.LANCE, Type.KNIGHT, Type.SILVER, Type.BISHOP, Type.ROOK,
    Type.EMPTY
];

private immutable Square[] PROMOTE = [
    Square.B_PROMOTED_PAWN, Square.B_PROMOTED_LANCE, Square.B_PROMOTED_KNIGHT, Square.B_PROMOTED_SILVER, Square.B_GOLD, Square.B_PROMOTED_BISHOP, Square.B_PROMOTED_ROOK, Square.B_KING,
    Square.B_PROMOTED_PAWN, Square.B_PROMOTED_LANCE, Square.B_PROMOTED_KNIGHT, Square.B_PROMOTED_SILVER, Square.B_PROMOTED_BISHOP, Square.B_PROMOTED_ROOK,
    Square.W_PROMOTED_PAWN, Square.W_PROMOTED_LANCE, Square.W_PROMOTED_KNIGHT, Square.W_PROMOTED_SILVER, Square.W_GOLD, Square.W_PROMOTED_BISHOP, Square.W_PROMOTED_ROOK, Square.W_KING,
    Square.W_PROMOTED_PAWN, Square.W_PROMOTED_LANCE, Square.W_PROMOTED_KNIGHT, Square.W_PROMOTED_SILVER, Square.W_PROMOTED_BISHOP, Square.W_PROMOTED_ROOK,
    Square.EMPTY,
];

private immutable Square[] INV = [
    Square.W_PAWN, Square.W_LANCE, Square.W_KNIGHT, Square.W_SILVER, Square.W_GOLD, Square.W_BISHOP, Square.W_ROOK, Square.W_KING,
    Square.W_PROMOTED_PAWN, Square.W_PROMOTED_LANCE, Square.W_PROMOTED_KNIGHT, Square.W_PROMOTED_SILVER, Square.W_PROMOTED_BISHOP, Square.W_PROMOTED_ROOK,
    Square.B_PAWN, Square.B_LANCE, Square.B_KNIGHT, Square.B_SILVER, Square.B_GOLD, Square.B_BISHOP, Square.B_ROOK, Square.B_KING,
    Square.B_PROMOTED_PAWN, Square.B_PROMOTED_LANCE, Square.B_PROMOTED_KNIGHT, Square.B_PROMOTED_SILVER, Square.B_PROMOTED_BISHOP, Square.B_PROMOTED_ROOK,
    Square.EMPTY,
];

private immutable bool[] PROMOTABLE = [
    true, true, true, true, false, true, true, false, false, false, false, false, false, false,
    true, true, true, true, false, true, true, false, false, false, false, false, false, false,
    false,
];
