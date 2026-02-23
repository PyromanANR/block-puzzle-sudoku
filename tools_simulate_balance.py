#!/usr/bin/env python3
"""Offline approximation simulator for quick balancing sanity checks."""
import json, random
from dataclasses import dataclass

SIZE=9
SHAPES={
    'I':[(0,0),(1,0),(2,0),(3,0)],'O':[(0,0),(1,0),(0,1),(1,1)],'T':[(0,0),(1,0),(2,0),(1,1)],
    'S':[(1,0),(2,0),(0,1),(1,1)],'Z':[(0,0),(1,0),(1,1),(2,1)],'J':[(0,0),(0,1),(1,1),(2,1)],'L':[(2,0),(0,1),(1,1),(2,1)],
    'Dot':[(0,0)],'DominoH':[(0,0),(1,0)],'DominoV':[(0,0),(0,1)],'TriLineH':[(0,0),(1,0),(2,0)],'TriLineV':[(0,0),(0,1),(0,2)],'TriL':[(0,0),(1,0),(0,1)],'Square2':[(0,0),(1,0),(0,1),(1,1)],'Plus5':[(1,0),(0,1),(1,1),(2,1),(1,2)]
}

with open('Scripts/Core/balance_config.json','r',encoding='utf-8') as f: cfg=json.load(f)

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
                # simple value: prefer immediate clear + compact center
                center=1.0-(abs(4-x)+abs(4-y))*0.05
                sc=center
                if best is None or sc>best[0]: best=(sc,x,y)
    return best

def run(games=500,seed=7):
    random.seed(seed)
    allk=list(SHAPES)
    total_moves=0; total_clears=0; no_move_losses=0
    for _ in range(games):
        b=[[0]*SIZE for _ in range(SIZE)]
        pity=0
        moves=0
        for _m in range(cfg['SimulationMaxMoves']):
            scored=[]
            for k in allk:
                e=eval_shape(b,k)
                if e: scored.append((e[0],k,e[1],e[2]))
            if not scored:
                no_move_losses+=1; break
            scored.sort(reverse=True)
            ideal=(pity>=cfg['PityEveryNSpawns']) or random.random()<cfg['IdealPieceChanceEarly']
            if ideal:
                _,k,x,y=scored[0]; pity=0
            else:
                top=scored[:max(1,min(cfg['CandidateTopBand'],len(scored)))]
                _,k,x,y=random.choice(top); pity+=1
            c=place_and_clear(b,k,x,y)
            total_clears+=c
            total_moves+=1
            moves+=1
    return {
        'games':games,
        'avg_moves': total_moves/games,
        'avg_clears': total_clears/games,
        'no_move_loss_rate': no_move_losses/games,
        'total_no_move_losses': no_move_losses,
    }

if __name__=='__main__':
    out=run(games=120)
    print(json.dumps(out,indent=2))
