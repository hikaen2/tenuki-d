import types;
import book;
import text;
import position;
import movegen;
import eval;
import std.random;
import std.stdio;
import std.algorithm.comparison;
import std.algorithm.mutation;
import std.algorithm.searching;
import std.datetime.stopwatch;

private int COUNT = 0;

private immutable MASK = 0xffffff;  // 1024 * 1024 * 16 - 1
private move_t[MASK + 1] TT = 0;

private StopWatch SW;
private int SECOND = 20;

int remainSeconds = 300;

int ponder(const ref Position p, move_t[] outPv)
{

    SECOND = min(20, remainSeconds);
    remainSeconds += 10;

    move_t m = 0;
    int score = 0;

    // for (int depth = 1; depth <= 6; depth++) {
    //     Position q = p;
    //     p.search0(depth, outPv, score);
    // }

    if (p.toSfen in BOOK) {
        outPv[0] = BOOK[p.toSfen][ uniform(0, BOOK[p.toSfen].length) ];
        outPv[1] = 0;
        return 0;
    }

    SW = StopWatch(AutoStart.yes);
    for (int depth = 1; SW.peek().total!"seconds" < SECOND; depth++) {
        p.search0(depth, outPv, score);
    }
    if (score <= -15000) {
        outPv[0] = Move.TORYO;
        outPv[1] = 0;
    }

    writeln(COUNT);
    return score;
}

/**
 * ルート局面用のsearch
 * 読み筋をstderrに出力する
 * Params:
 *      p        = 局面
 *      depth    = 探索深さ(>=1)
 *      outPv    = 読み筋を出力する
 *      outScore = 評価値を出力する
 * Returns: 評価値
 */
private int search0(Position p, int depth, move_t[] outPv, ref int outScore)
{
    move_t[64] pv;
    COUNT++;

    move_t[593] moves;
    int length = p.legalMoves(moves);
    if (length == 0) {
        return 0;
    }
    randomShuffle(moves[0..length]);
    if (outPv[0] != 0) {
        swap(moves[0], moves[0..length].find(outPv[0])[0]);
    }

    int a = short.min;
    const int b = short.max;
    stderr.writef("%d: ", depth);
    foreach (move_t move; moves[0..length]) {
        int value = -p.doMove(move).search(depth - 1, -b, -a, pv);
        if (SW.peek().total!"seconds" >= SECOND) {
            break;
        }
        if (a < value) {
            a = value;
            // if (outPv[0] != move) {
            //     SW.reset();
            // }
            outPv[0] = move;
            outPv[1..64] = pv[0..63];
            stderr.writef("%s(%d) ", move.toString(p), value);
            outScore = value;
        }
    }
    stderr.write(" : ");
    Position q = p;
    for (int i = 0; outPv[i] != 0; q = q.doMove(outPv[i]), i++) {
        stderr.writef("%s ", outPv[i].toString(q));
    }
    stderr.write("\n");
    return a;
}

/**
 * search
 * @param p
 * @param depth
 * @param a 探索済みminノードの最大値
 * @param b 探索済みmaxノードの最小値
 * @return 評価値
 */
private int search(Position p, int depth, int a, const int b, move_t[] outPv, bool doNullMove = true)
{
    assert(a < b);

    outPv[0] = 0;
    if (SW.peek().total!"seconds" >= SECOND) {
        return 0;
    }

    if (p.inUchifuzume) {
        return 15000; // 打ち歩詰めされていれば勝ち
    }

    if (depth <= 0) {
        return p.qsearch(depth + 4, a, b, outPv);
    }
    COUNT++;

    // if (!p.inCheck && depth + 1 <= 3 && b <= p.staticValue - 200) {
    //     return b;
    // }

    move_t[64] pv;

    if (doNullMove /* && !p.inCheck */ ) {
        immutable R = 2;
        int value = -p.doMove(Move.NULL_MOVE).search(depth - R - 1, -b, -b + 1, pv, false);
        if (b <= value) {
            return b;
        }
    }

    {
        move_t move = TT[p.hash & MASK];
        if (move.isValid(p)) {
            int value = -p.doMove(move).search(depth - 1, -b, -a, pv);
            if (a < value) {
                a = value;
                if (b <= a) {
                    return b;
                }
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
            }
        }
    }

    move_t[593] moves;
    int length = p.legalMoves(moves);
    if (length == 0) {
        return p.staticValue;
    }
    foreach (move_t move; moves[0..length]) {
        int value = -p.doMove(move).search(depth - 1, -b, -a, pv);
        if (a < value) {
            a = value;
            TT[p.hash & MASK] = move;
            if (b <= a) {
                return b;
            }
            outPv[0] = move;
            outPv[1..64] = pv[0..63];
        }
    }
    return a;
}

/**
 * 静止探索
 */
private int qsearch(Position p, int depth, int a, const int b, move_t[] outPv)
{
    assert(a < b);

    COUNT++;
    outPv[0] = 0;
    move_t[64] pv;

    if (depth <= 0) {
        return p.staticValue;
    }

    a = max(a, p.staticValue);
    if (b <= a) {
        return b;
    }

    {
        move_t move = TT[p.hash & MASK];
        if (move.isValid(p) && p.squares[move.to].isEnemy(p.sideToMove)) {
            int value = -p.doMove(move).qsearch(depth - 1, -b, -a, pv);
            if (a < value) {
                a = value;
                if (b <= a) {
                    return b;
                }
                outPv[0] = move;
                outPv[1..64] = pv[0..63];
            }
        }
    }

    move_t[128] moves;
    int length = p.capturelMoves(moves);
    foreach (move_t move; moves[0..length]) {
        int value = -p.doMove(move).qsearch(depth - 1, -b, -a, pv);
        if (a < value) {
            a = value;
            TT[p.hash & MASK] = move;
            if (b <= a) {
                return b;
            }
            outPv[0] = move;
            outPv[1..64] = pv[0..63];
        }
    }
    return a;
}

/**
 * 局面pにおいて手番のある側が打ち歩詰めされているかどうかを返す
 */
private bool inUchifuzume(Position p)
{
    if (!p.previousMove.isDrop || p.previousMove.from != Type.PAWN || !p.inCheck) {
        return false; // 直前の指し手が打ち歩でない，または現局面が王手をかけられていない場合は，打ち歩詰めでない
    }

    move_t[593] moves;
    int length = p.legalMoves(moves);
    foreach (move_t move; moves[0..length]) {
        if (!p.doMove(move).doMove(Move.NULL_MOVE).inCheck) {
            return false; // 王手を解除する手があれば打ち歩詰めでない
        }
    }
    return true; // 王手を解除する手がなければ打ち歩詰め
}
