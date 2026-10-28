import {describe,it,expect} from 'vitest';
import {reorder,dateLabel} from './types';
describe('attendee list',()=>{it('moves attendees by stable ID including duplicate names',()=>{const p=[{id:'a',name:'김'},{id:'b',name:'김'},{id:'c',name:'이'}];expect(reorder(p,1,-1).map(x=>x.id)).toEqual(['b','a','c']);expect(p[0].id).toBe('a');});it('keeps out-of-range moves unchanged',()=>{expect(reorder(['a','b'],0,-1)).toEqual(['a','b']);});});
describe('meeting date',()=>{it('formats Korean dates without UTC day shift',()=>{expect(dateLabel('2026-10-18')).toContain('18일');});});
