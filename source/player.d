import types;
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
immutable SECOND = 10;

int ponder(const ref Position p, move_t[] out_pv)
{
    move_t m = 0;
    int score = 0;

    // for (int depth = 1; depth <= 6; depth++) {
    //     Position q = p;
    //     p.search0(depth, out_pv, score);
    //     for (int i = 0; out_pv[i] != 0; i++) {
    //         stderr.writef("%s ", out_pv[i].toString(q));
    //         q = q.doMove(out_pv[i]);
    //     }
    //     stderr.write("\n");
    // }

    SW = StopWatch(AutoStart.yes);
    for (int depth = 1; SW.peek().total!"seconds" < SECOND; depth++) {
        Position q = p;
        p.search0(depth, out_pv, score);
        for (int i = 0; out_pv[i] != 0; i++) {
            stderr.writef("%s ", out_pv[i].toString(q));
            q = q.doMove(out_pv[i]);
        }
        stderr.write("\n");
    }

    writeln(COUNT);
    return score;
}

/**
 * ルート局面用のsearch
 * 候補をstderrに出力する
 * @return 評価値
 */
private int search0(Position p, int depth, move_t[] out_pv, ref int out_score)
{
    move_t[64] pv;
    COUNT++;

    move_t[593] moves;
    int length = p.legalMoves(moves);
    if (length == 0) {
        return 0;
    }
    randomShuffle(moves[0..length]);
    if (out_pv[0] != 0) {
        swap(moves[0], moves[0..length].find(out_pv[0])[0]);
    }

    int a = short.min;
    const int b = short.max;
    stderr.writef("%d: ", depth);
    foreach (move_t move; moves[0..length]) {
        int value = -p.doMove(move).search(depth - 1, -b, -a, pv);
        if (a < value && SW.peek().total!"seconds" < SECOND) {
            a = value;
            out_pv[0] = move;
            for (int i = 0; (out_pv[i + 1] = pv[i]) != 0; i++) {}
            stderr.writef("%s(%d) ", move.toString(p), value);
            out_score = value;
        }
    }
    stderr.write(" : ");
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
private int search(Position p, int depth, int a, const int b, move_t[] out_pv, bool doNullMove = true)
{
    assert(a < b);

    out_pv[0] = 0;
    if (SW.peek().total!"seconds" >= SECOND) {
        return 0;
    }

    if (depth <= 0) {
        return doNullMove ? p.qsearch(4, a, b, out_pv) : p.staticValue;
    }
    COUNT++;

    if (p.inUchifuzume) {
        return 15000; // 打ち歩詰めされていれば勝ち
    }

    move_t[64] pv;

    if (doNullMove && !p.inCheck) {
        int value = -p.doMove(Move.NULL_MOVE).search(depth - 2 - 1, -b, -b + 1, pv, false);
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
                out_pv[0] = move;
                for (int i = 0; (out_pv[i + 1] = pv[i]) != 0; i++) {}
                if (b <= a) {
                    return b;
                }
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
            out_pv[0] = move;
            TT[p.hash & MASK] = move;
            for (int i = 0; (out_pv[i + 1] = pv[i]) != 0; i++) {}
            if (b <= a) {
                return b;
            }
        }
    }
    return a;
}

/**
 * 静止探索
 */
private int qsearch(Position p, int depth, int a, const int b, move_t[] out_pv)
{
    assert(a < b);

    COUNT++;
    move_t[64] pv;
    out_pv[0] = 0;

    if (depth <= 0) {
        return p.staticValue;
    }

    a = max(a, p.staticValue);
    if (b <= a) {
        return b;
    }

    {
        move_t move = TT[p.hash & MASK];
        if (move.isValid(p)) {
            int value = -p.doMove(move).qsearch(depth - 1, -b, -a, pv);
            if (a < value) {
                a = value;
                out_pv[0] = move;
                for (int i = 0; (out_pv[i + 1] = pv[i]) != 0; i++) {}
                if (b <= a) {
                    return b;
                }
            }
        }
    }

    move_t[128] moves;
    int length = p.capturelMoves(moves);
    foreach (move_t move; moves[0..length]) {
        int value = -p.doMove(move).qsearch(depth - 1, -b, -a, pv);
        if (a < value) {
            a = value;
            out_pv[0] = move;
            TT[p.hash & MASK] = move;
            for (int i = 0; (out_pv[i + 1] = pv[i]) != 0; i++) {}
            if (b <= a) {
                return b;
            }
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
    if (length == 0) {
        return true;
    }
    foreach (move_t move; moves[0..length]) {
        if (!p.doMove(move).doMove(Move.NULL_MOVE).inCheck) {
            return false; // 王手を解除する手があれば打ち歩詰めでない
        }
    }
    return true; // 王手を解除する手がなければ打ち歩詰め
}
