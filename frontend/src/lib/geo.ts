/** Even-odd ray casting over every ring, so holes (enclaves) count as outside. */
export function inside(polygons: number[][][], x: number, y: number): boolean {
  let hit = false;
  for (const rings of polygons)
    for (const r of rings)
      for (let i = 0, j = r.length - 2; i < r.length; j = i, i += 2) {
        const [xi, yi, xj, yj] = [r[i], r[i + 1], r[j], r[j + 1]];
        if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) hit = !hit;
      }
  return hit;
}
