/** Confirm the pure Shell layout operations stay correct on multiple monitors. */
import assert from 'node:assert/strict';
import {arrangeRects, chooseWorkArea, clampRect, intersectionArea} from
    '../../shell/majoris-stickies@majoris.org/layout.js';

const areas = [
    {index: 0, x: 0, y: 0, width: 1920, height: 1040},
    {index: 1, x: -1280, y: 0, width: 1280, height: 984},
];
const saved = {x: -1100, y: 80, width: 370, height: 330,
    monitorArea: {x: -1280, y: 0, width: 1280, height: 984}};
assert.equal(chooseWorkArea(saved, areas, 0)?.index, 1);
assert.equal(chooseWorkArea(saved, [areas[0]], 0)?.index, 0);
assert.deepEqual(clampRect(saved, areas[0]),
    {x: 0, y: 80, width: 370, height: 330});
assert.equal(intersectionArea(areas[0], areas[1]), 0);
const arrangement = arrangeRects(8, areas[1], 'grid');
assert.equal(arrangement.length, 8);
for (const item of arrangement) {
    assert.ok(item.x >= areas[1].x && item.y >= areas[1].y);
    assert.ok(item.x + item.width <= areas[1].x + areas[1].width);
    assert.ok(item.y + item.height <= areas[1].y + areas[1].height);
}
assert.equal(arrangeRects(3, areas[0], 'cascade').length, 3);
assert.equal(arrangeRects(0, areas[0], 'grid').length, 0);
console.log('Multi-monitor placement tests passed');
