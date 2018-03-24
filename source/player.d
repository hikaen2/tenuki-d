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
immutable SECOND = 2;

int ponder(const ref Position p, out move_t result)
{
    move_t m = 0;
    int score = 0;

    // for (int depth = 1; depth <= 6; depth++) {
    //     search0(p, depth, m, score);
    // }

    SW = StopWatch(AutoStart.yes);
    for (int depth = 1; SW.peek().total!"seconds" < SECOND; depth++) {
        search0(p, depth, m, score);
    }
    writeln(COUNT);
    result = m;
    return score;
}

/**
 * ルート局面用のsearch
 * 候補をstderrに出力する
 * @return 評価値
 */
private int search0(Position p, int depth, ref move_t in_out_move, ref int out_score)
{
    COUNT++;

    move_t[593] moves;
    int length = p.legalMoves(moves);
    if (length == 0) {
        return 0;
    }
    moves[0..length].randomShuffle();
    if (in_out_move != 0) {
        swap(moves[0], moves[0..length].find(in_out_move)[0]);
    }

    int a = short.min;
    const int b = short.max;
    stderr.write(format("%d: ", depth));
    for (int i = 0; i < length; i++) {
        int value = -search(p.doMove(moves[i]), depth - 1, -b, -a, true);
        if (a < value && SW.peek().total!"seconds" < SECOND) {
            a = value;
            in_out_move = moves[i];
            out_score = value;
            stderr.write(format("%s(%d) ", moves[i].toString(p), value));
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
private int search(Position p, int depth, int a, const int b, bool doNullMove)
{
    if (SW.peek().total!"seconds" >= SECOND) {
        return 0;
    }

    if (depth <= 0) {
        return doNullMove ? quies(p, 4, a, b) : p.staticValue;
    }
    COUNT++;

    if (!p.inCheck && doNullMove) {
        p.sideToMove ^= 1;
        int value = -search(p, depth - 2 - 1, -b, -b + 1, false);
        p.sideToMove ^= 1;
        if (b <= value) {
            return value;
        }
    }

    move_t m = TT[p.hash & MASK];
    if (m.isValid(p)) {
        a = max(a, -search(p.doMove(m), depth - 1, -b, -a, true));
        if (b <= a) {
            return b; // bカット
        }
    }

    move_t[593] moves;
    int length = p.legalMoves(moves);
    if (length == 0) {
        return p.staticValue;
    }
    for (int i = 0; i < length; i++) {
        int value = -search(p.doMove(moves[i]), depth - 1, -b, -a, true);
        if (a < value) {
            a = value;
            TT[p.hash & MASK] = moves[i];
        }
        if (b <= a) {
            return b; // bカット
        }
    }
    return a;
}

private int quies(Position p, int depth, int a, const int b)
{
    COUNT++;

    if (depth == 0) {
        return p.staticValue;
    }

    int standpat = p.staticValue;
    if (b <= standpat) {
        return b; // bカット
    }
    a = max(a, standpat);

    move_t m = TT[p.hash & MASK];
    if (m.isValid(p)) {
        a = max(a, -quies(p.doMove(m), depth - 1, -b, -a));
        if (b <= a) {
            return b; // bカット
        }
    }

    move_t[128] moves;
    int length = p.capturelMoves(moves);
    for (int i = 0; i < length; i++) {
        int value = -quies(p.doMove(moves[i]), depth - 1, -b, -a);
        if (a < value) {
            a = value;
            TT[p.hash & MASK] = moves[i];
        }
        if (b <= value) {
            return b; // bカット
        }
    }
    return a;
}
