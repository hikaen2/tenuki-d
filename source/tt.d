/*
module tt;

import types;

private immutable MASK = 0xffffff; // 1024 * 1024 * 16 - 1
shared TTEntry[MASK + 1] TT;

struct TTEntry
{
    uint key32;
    ushort move16;
    ushort depth16;
}

Move* probe(ulong key)
{
    const uint key32 = key >> 32;
    TTEntry e = TT[key & MASK];

    if (e.key32 == key32)
    {
        return cast(Move)(e.move16);
    }
    return cast(Move)(0);
}

void store(ulong key, Move m)
{
    const uint key32 = key >> 32;
    TTEntry e = TT[key & MASK];

}

int hashfull()
{
    int cnt = 0;
    foreach (TTEntry e; TT)
    {
        cnt += e.move16 == 0 ? 0 : 1;
    }
    return cnt * 1000 / (MASK + 1);
}
*/
