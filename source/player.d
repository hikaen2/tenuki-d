import types;
import text;
import position;
import movegen;
import eval;
import std.format;
import std.random;
import std.stdio;
import std.datetime.stopwatch;
import std.algorithm.searching;
import std.algorithm.mutation;
import std.algorithm.comparison;


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
    //     score = p.search0(depth, out_pv);
    //     for (int i = 0; out_pv[i] != 0; i++) {
    //         stderr.writef("%s ", out_pv[i].toString(q));
    //         q = q.doMove(out_pv[i]);
    //     }
    //     stderr.write("\n");
    // }

    // if (p.moveCount == 1) {
    //     int s = uniform(0, 4); // [0..3]
    //     result = (s == 0 ? createMove(77, 76) : s == 1 ? createMove(27, 26) : s == 2 ? createMove(28, 68) : createMove(28, 78));
    //     return 0;
    // }
    // if (p.moveCount == 2) {
    //     result = (uniform(0, 2) == 0 ? createMove(33, 34) : createMove(83, 84));
    //     return 0;
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
    stderr.write(format("%d: ", depth));
    foreach (move_t move; moves[0..length]) {
        int value = -p.doMove(move).search(depth - 1, -b, -a, pv);
        if (a < value && SW.peek().total!"seconds" < SECOND) {
            a = value;
            out_pv[0] = move;
            for (int i = 0; (out_pv[i + 1] = pv[i]) != 0; i++) {}
            stderr.write(format("%s(%d) ", move.toString(p), value));
            out_score = value;
        }
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
private int search(Position p, int depth, int a, const int b, move_t[] out_pv, bool doNullMove = true)
{
    out_pv[0] = 0;
    if (SW.peek().total!"seconds" >= SECOND) {
        return 0;
    }

    if (depth <= 0) {
        return doNullMove ? p.quies(4, a, b, out_pv) : p.staticValue;
    }
    COUNT++;

    move_t[64] pv;

    if (doNullMove && !p.inCheck) {
        int value = -p.doMove(Move.NULL_MOVE).search(depth - 2 - 1, -b, -b + 1, pv, false);
        if (b <= value) {
            return value;
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
            }
            if (b <= a) {
                return b;
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
            for (int i = 0; (out_pv[i + 1] = pv[i]) != 0; i++) {}
            TT[p.hash & MASK] = move;
        }
        if (b <= a) {
            return b;
        }
    }
    return a;
}

private int quies(Position p, int depth, int a, const int b, move_t[] out_pv)
{
    COUNT++;
    move_t[64] pv;
    out_pv[0] = 0;

    if (depth == 0) {
        return p.staticValue;
    }

    int standpat = p.staticValue;
    if (b <= standpat) {
        return b;
    }
    a = max(a, standpat);

    {
        move_t move = TT[p.hash & MASK];
        if (move.isValid(p)) {
            int value = -p.doMove(move).quies(depth - 1, -b, -a, pv);
            if (a < value) {
                a = value;
                out_pv[0] = move;
                for (int i = 0; (out_pv[i + 1] = pv[i]) != 0; i++) {}
            }
            if (b <= a) {
                return b;
            }
        }
    }

    move_t[128] moves;
    int length = p.capturelMoves(moves);
    foreach (move_t move; moves[0..length]) {
        int value = -p.doMove(move).quies(depth - 1, -b, -a, pv);
        if (a < value) {
            a = value;
            out_pv[0] = move;
            for (int i = 0; (out_pv[i + 1] = pv[i]) != 0; i++) {}
            TT[p.hash & MASK] = move;
        }
        if (b <= value) {
            return b;
        }
    }
    return a;
}
