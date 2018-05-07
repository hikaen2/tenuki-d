
alias side_t = ubyte;
alias type_t = ubyte;
alias square_t = ubyte;

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
    square_t[81] squares;
    ubyte[8][2] piecesInHand;
    bool sideToMove;
    ulong hash;
    ushort moveCount = 1;
    Move previousMove; // 直前の指し手
}

enum Side : side_t
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
    BISHOP            = 4,  // 角
    ROOK              = 5,  // 飛
    GOLD              = 6,  // 金
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
 * xxx1xxxx side
 * xxxx1111 type
 */
enum Square : square_t
{
    W                 = 0b00010000,
    B_PAWN            = 0,
    B_LANCE           = 1,
    B_KNIGHT          = 2,
    B_SILVER          = 3,
    B_BISHOP          = 4,
    B_ROOK            = 5,
    B_GOLD            = 6,
    B_KING            = 7,
    B_PROMOTED_PAWN   = 8,
    B_PROMOTED_LANCE  = 9,
    B_PROMOTED_KNIGHT = 10,
    B_PROMOTED_SILVER = 11,
    B_PROMOTED_BISHOP = 12,
    B_PROMOTED_ROOK   = 13,
    EMPTY             = 14,

    W_PAWN            = 16,
    W_LANCE           = 17,
    W_KNIGHT          = 18,
    W_SILVER          = 19,
    W_BISHOP          = 20,
    W_ROOK            = 21,
    W_GOLD            = 22,
    W_KING            = 23,
    W_PROMOTED_PAWN   = 24,
    W_PROMOTED_LANCE  = 25,
    W_PROMOTED_KNIGHT = 26,
    W_PROMOTED_SILVER = 27,
    W_PROMOTED_BISHOP = 28,
    W_PROMOTED_ROOK   = 29,
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
    bool isFly() { return (i & 1) != 0; }
    int value() { return i >> 1; }
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
    ubyte from() { return cast(ubyte)((i >> 7) & 0b01111111); }
    ubyte to() { return cast(ubyte)(i & 0b01111111); }
    bool isPromote() { return (i & 0b1000000000000000) != 0; }
    bool isDrop() { return (i & 0b0100000000000000) != 0; }
}

// square_tを引数にとる関数
bool isBlack(square_t sq) { return sq <= Square.B_PROMOTED_ROOK; }
bool isWhite(square_t sq) { return sq >= Square.W_PAWN; }
bool isFriend(square_t sq, side_t s) { return s == Side.BLACK ? sq.isBlack() : sq.isWhite(); }
bool isEnemy(square_t sq, side_t s) { return s == Side.BLACK ? sq.isWhite() : sq.isBlack(); }
type_t type(square_t sq) { return sq & 0b00001111; }
square_t promote(square_t sq) { return sq | 0b00001000; }
square_t unpromote(square_t sq) { return sq & 0b11110111; }

// move_tを返す関数
Move createMove(int from, int to) { return Move(cast(ushort)(from << 7 | to)); }
Move createPromote(int from, int to) { return Move(cast(ushort)(from << 7 | to | 0b1000000000000000)); }
Move createDrop(type_t t, int to) { return Move(cast(ushort)(t << 7 | to | 0b0100000000000000)); }


enum SQ11 = 0;
enum SQ99 = 80;
