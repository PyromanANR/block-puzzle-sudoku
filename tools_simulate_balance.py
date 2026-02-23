#!/usr/bin/env python3
"""Offline approximation simulator for quick balancing sanity checks."""
import json, random, statistics

SIZE=9
SHAPES={
    'I':[(0,0),(1,0),(2,0),(3,0)],'O':[(0,0),(1,0),(0,1),(1,1)],'T':[(0,0),(1,0),(2,0),(1,1)],
    'S':[(1,0),(2,0),(0,1),(1,1)],'Z':[(0,0),(1,0),(1,1),(2,1)],'J':[(0,0),(0,1),(1,1),(2,1)],'L':[(2,0),(0,1),(1,1),(2,1)],
    'Dot':[(0,0)],'DominoH':[(0,0),(1,0)],'DominoV':[(0,0),(0,1)],'TriLineH':[(0,0),(1,0),(2,0)],'TriLineV':[(0,0),(0,1),(0,2)],'TriL':[(0,0),(1,0),(0,1)],'Square2':[(0,0),(1,0),(0,1),(1,1)],'Plus5':[(1,0),(0,1),(1,1),(2,1),(1,2)]
}

with open('Scripts/Core/balance_config.json','r',encoding='utf-8') as f: cfg=json.load(f)

ALL=list(SHAPES)

def can_place(b,shape,ax,ay):
    for dx,dy in SHAPES[shape]:
        x,y=ax+dx,ay+dy
        if not (0<=x<SIZE and 0<=y<SIZE) or b[y][x]: return False
    return True

def place_and_clear(b,shape,ax,ay):
    for dx,dy in SHAPES[shape]: b[ay+dy][ax+dx]=1
    clear=set()
    for y in range(SIZE):
        if all(b[y][x] for x in range(SIZE)):
            for x in range(SIZE): clear.add((x,y))
    for x in range(SIZE):
        if all(b[y][x] for y in range(SIZE)):
            for y in range(SIZE): clear.add((x,y))
    for by in range(0,SIZE,3):
        for bx in range(0,SIZE,3):
            cells=[(bx+dx,by+dy) for dy in range(3) for dx in range(3)]
            if all(b[y][x] for x,y in cells): clear|=set(cells)
    for x,y in clear: b[y][x]=0
    return len(clear)

def eval_shape(b,shape):
    best=None
    for y in range(SIZE):
        for x in range(SIZE):
            if can_place(b,shape,x,y):
                center=1.0-(abs(4-x)+abs(4-y))*0.05
                if best is None or center>best[0]: best=(center,x,y)
    return best

def run(games=120,seed=7,well_size=None):
    random.seed(seed)
    local=dict(cfg)
    if well_size is not None:
        local['PileMax']=well_size
    lengths=[]
    clears_total=0
    no_move=0
    overflow=0
    pity_total=0
    for _ in range(games):
        b=[[0]*SIZE for _ in range(SIZE)]
        pity_spawns=0
        no_progress=0
        well_load=0.0
        t=0.0
        clears=0
        for m in range(local['SimulationMaxMoves']):
            level=1 + m/max(1, local['PointsPerLevel']//10)
            fall_speed=min(local['MaxFallSpeedCap'], local['BaseFallSpeed']*(local['LevelSpeedGrowth']**max(0,level-1)))
            move_time=max(0.65, 2.6-0.02*m)
            inflow=move_time*(fall_speed/30.0)
            well_load=max(0.0, well_load+inflow-1.0)
            if well_load>local['PileMax']:
                overflow+=1
                break

            scored=[]
            for k in ALL:
                e=eval_shape(b,k)
                if e: scored.append((e[0],k,e[1],e[2]))
            if not scored:
                no_move+=1
                break
            scored.sort(reverse=True)

            ideal=local['IdealPieceChanceEarly']-local['IdealChanceDecayPerMinute']*(t/60.0)
            ideal=max(local['IdealChanceFloor'], min(1.0, ideal))
            pity = pity_spawns>=local['PityEveryNSpawns'] or no_progress>=local['NoProgressMovesForPity']
            if pity or random.random()<ideal:
                _,k,x,y=scored[0]
                if pity: pity_total+=1
                pity_spawns=0
            else:
                top=scored[:max(1,min(local['CandidateTopBand'],len(scored)))]
                _,k,x,y=random.choice(top)
                pity_spawns+=1

            c=place_and_clear(b,k,x,y)
            clears += c
            clears_total += c
            no_progress = 0 if c>0 else no_progress+1
            t += move_time
        lengths.append(t)

    avg_t=sum(lengths)/games
    return {
        'games':games,
        'well_size': local['PileMax'],
        'avg_time_sec': avg_t,
        'p50_time_sec': statistics.median(lengths),
        'p90_time_sec': sorted(lengths)[int(0.9*(games-1))],
        'avg_clears_per_min': (clears_total/games)/(avg_t/60.0) if avg_t>0 else 0,
        'no_move_loss_rate': no_move/games,
        'well_overflow_rate': overflow/games,
        'pity_triggers_per_game': pity_total/games,
    }

if __name__=='__main__':
    out={
      'well_8': run(games=120,seed=7,well_size=8),
      'well_6': run(games=120,seed=7,well_size=6),
      'well_5': run(games=120,seed=7,well_size=5),
    }
    print(json.dumps(out,indent=2))
