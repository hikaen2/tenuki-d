module tt;

import std.stdio;
import core.atomic;
import types;
import text;

private immutable MASK = 0xffffff; // 1024 * 1024 * 16 - 1
__gshared private TTEntry[MASK + 1] TT;

struct TTEntry
{
    ulong key64;
    ushort move16;
}

Move probe(ulong key)
{
    TTEntry e = TT[key & MASK];

    if (e.key64 == key)
    {
        return cast(Move)(e.move16);
    }
    return cast(Move)(0);
}

void store(ulong key, Move m)
{
    TT[key & MASK] = TTEntry(key, m.i);
}

long hashfull()
{
    long cnt = 0;
    foreach (TTEntry e; TT)
    {
        cnt += e.move16 == 0 ? 0 : 1;
    }
    return cnt * 1000 / (MASK + 1);
}
