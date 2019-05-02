module tt;


import core.atomic;
import std.format;
import std.stdio;
import types;
static import config;


__gshared private TTEntry[] TT;
shared long stat_nothing = 0;
shared long stat_misshit = 0;
shared long stat_hit = 0;
shared long stat_stored = 0;


shared static this()
{
    TT.length = config.TT_SIZE + 1;
}


struct TTEntry
{
    uint key32;
    ushort move16;
    ushort _;
}


Move probe(ulong key)
{
    for (int i = 0; i < 5; i++)
    {
        TTEntry e = TT[((key & config.TT_SIZE) + i * 2) % (config.TT_SIZE + 1)];
        if (e.key32 == 0)
        {
            //atomicOp!"+="(stat_nothing, 1);
            return cast(Move)(0);
        }
        if (e.key32 == (key >> 32))
        {
            //atomicOp!"+="(stat_hit, 1);
            return cast(Move)(e.move16);
        }
        //atomicOp!"+="(stat_misshit, 1);
        //return cast(Move)(0);
    }
    //atomicOp!"+="(stat_misshit, 1);
    return cast(Move)(0);
}


void store(ulong key, Move m)
{
    for (int i = 0; i < 5; i++)
    {
        const long address = ((key & config.TT_SIZE) + i * 2) % (config.TT_SIZE + 1);
        if (TT[address].key32 == 0 || TT[address].key32 == (key >> 32))
        {
            TT[address] = TTEntry((key >> 32), m.i);
            //atomicOp!"+="(stat_stored, 1);
            return;
        }
        //return;
    }
}


long hashfull()
{
    long cnt = 0;
    foreach (TTEntry e; TT)
    {
        cnt += e.move16 == 0 ? 0 : 1;
    }
    return cnt * 1000 / (config.TT_SIZE + 1);
    //return cnt;
}


/**
 * 例："TT: 33,554,432 entries, 268,435,456 bytes"
 */
string info()
{
    return format("TT: %,d entries, %,d bytes", TT.length, TT.length * TTEntry.sizeof);
}
