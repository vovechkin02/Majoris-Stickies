/** Pure, compositor-independent multi-monitor placement calculations. */
const MIN_WIDTH = 240;
const MIN_HEIGHT = 85;
const GAP = 12;

/** Return the rectangle intersection area, or zero for disjoint rectangles. */
export function intersectionArea(left, right) {
    const width = Math.max(0, Math.min(left.x + left.width, right.x + right.width) -
        Math.max(left.x, right.x));
    const height = Math.max(0, Math.min(left.y + left.height, right.y + right.height) -
        Math.max(left.y, right.y));
    return width * height;
}

/** Pick a surviving monitor by saved monitor overlap, not numerical monitor ID. */
export function chooseWorkArea(saved, workAreas, fallbackIndex = 0) {
    if (workAreas.length === 0) {
        return null;
    }
    const fallback = workAreas.find(area => area.index === fallbackIndex) ?? workAreas[0];
    const previous = saved?.monitorArea ?? saved;
    if (!validRectangle(previous)) {
        return fallback;
    }
    let bestArea = null;
    let greatestOverlap = 0;
    for (const area of workAreas) {
        const overlap = intersectionArea(previous, area);
        if (overlap > greatestOverlap) {
            bestArea = area;
            greatestOverlap = overlap;
        }
    }
    return bestArea ?? fallback;
}

/** Validate persisted rectangle values before passing them to Mutter. */
export function validRectangle(rect) {
    return rect != null && [rect.x, rect.y, rect.width, rect.height]
        .every(Number.isFinite) && rect.width > 0 && rect.height > 0 &&
        Math.abs(rect.x) < 100000 && Math.abs(rect.y) < 100000 &&
        rect.width <= 100000 && rect.height <= 100000;
}

/** Constrain a restored note to the selected monitor's usable work area. */
export function clampRect(saved, area) {
    if (!validRectangle(saved) || !validRectangle(area)) {
        return null;
    }
    const width = Math.min(area.width, Math.max(Math.min(MIN_WIDTH, area.width), saved.width));
    const height = Math.min(area.height, Math.max(Math.min(MIN_HEIGHT, area.height), saved.height));
    return {
        x: Math.max(area.x, Math.min(saved.x, area.x + area.width - width)),
        y: Math.max(area.y, Math.min(saved.y, area.y + area.height - height)),
        width: Math.floor(width),
        height: Math.floor(height),
    };
}

/** Calculate per-monitor grid/cascade positions in the caller's order. */
export function arrangeRects(count, area, mode) {
    if (!validRectangle(area) || count <= 0 || count > 64) {
        return [];
    }
    const columns = Math.min(count, Math.max(1,
        Math.floor((area.width - GAP) / (MIN_WIDTH + GAP))));
    const rows = Math.ceil(count / columns);
    const cellWidth = Math.max(1, Math.floor((area.width - GAP * (columns + 1)) / columns));
    const cellHeight = Math.max(1, Math.floor((area.height - GAP * (rows + 1)) / rows));
    const rectangles = [];
    for (let index = 0; index < count; index++) {
        let rect;
        if (mode === 'cascade') {
            const width = Math.max(1, Math.min(400, area.width - 2 * GAP));
            const height = Math.max(1, Math.min(340, area.height - 2 * GAP));
            const dx = Math.max(1, area.width - width - GAP);
            const dy = Math.max(1, area.height - height - GAP);
            rect = {
                x: area.x + GAP + (index * 32) % dx,
                y: area.y + GAP + (index * 32) % dy,
                width, height,
            };
        } else {
            rect = {
                x: area.x + GAP + (index % columns) * (cellWidth + GAP),
                y: area.y + GAP + Math.floor(index / columns) * (cellHeight + GAP),
                width: cellWidth, height: cellHeight,
            };
        }
        rectangles.push(clampRect(rect, area));
    }
    return rectangles;
}
