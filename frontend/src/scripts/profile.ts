// Draws the profile charts from the per-official JSON and keeps charts + table twins in step with the
// "hide possible matches" toggle. Tables are already server-rendered, so this only enhances.
import * as Plot from "@observablehq/plot";
import type { OfficialBundle } from "../lib/exports/types";
import { attendedAxisMin, missedAxisMax } from "../lib/attendance";
import { count, money } from "../lib/format";
import { cellText, VIZ, type Row, type VizSpec } from "../lib/viz";

const compactUsd = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  notation: "compact",
  maximumFractionDigits: 1,
});

// long names (lobbyist principals) are clipped on the axis; tooltip and table keep them whole
const MAX_LABEL = 32;
const clip = (s: string) => (s.length > MAX_LABEL ? `${s.slice(0, MAX_LABEL - 1)}…` : s);

function thinTicks(values: string[], width: number): string[] {
  const unique = [...new Set(values)];
  const every = Math.max(1, Math.ceil(unique.length / Math.max(1, Math.floor(width / 50))));
  return unique.filter((_, i) => i % every === 0);
}

const css = (name: string) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
const seriesColors = () => [1, 2, 3, 4, 5].map((i) => css(`--series-${i}`));
const hideMedium = () => document.documentElement.classList.contains("hide-medium");

function chart(spec: VizSpec, rows: Row[], width: number): SVGSVGElement | HTMLElement {
  const style = { background: "transparent", color: css("--ink-2"), fontSize: "12px" };
  if (spec.kind === "hstack") {
    // melt the wide table rows into one segment per stack key; colors follow the key's fixed slot
    const keys = spec.stackKeys ?? [];
    const colors = seriesColors();
    const long = rows.flatMap((r) =>
      keys.map((k) => ({ y: String(r[spec.y]), part: k.label, n: Number(r[k.key]) })),
    );
    const longest = Math.min(MAX_LABEL, Math.max(...rows.map((r) => String(r[spec.y]).length)));
    return Plot.plot({
      width,
      style,
      marginLeft: 16 + longest * 6.5,
      height: 24 * rows.length + 60,
      x: { grid: true, label: null, tickFormat: (d: number) => count(d) },
      y: { label: null, domain: rows.map((r) => String(r[spec.y])), tickFormat: clip },
      color: { domain: keys.map((k) => k.label), range: keys.map((_, i) => colors[i]), legend: true },
      marks: [
        Plot.barX(long, {
          x: "n",
          y: "y",
          fill: "part",
          order: keys.map((k) => k.label),
          insetTop: 3,
          insetBottom: 3,
          tip: true,
        }),
        Plot.ruleX([0], { stroke: css("--axis") }),
      ],
    });
  }
  if (spec.kind === "dumbbell") {
    const ink = css("--ink");
    const muted = css("--muted");
    const longest = Math.max(...rows.map((r) => String(r[spec.y]).length));
    // dots need no zero baseline; attendance clusters near 100%, so start just below the data
    const from = attendedAxisMin(rows.flatMap((r) => [Number(r[spec.x]), Number(r[spec.x2!])]));
    return Plot.plot({
      width,
      style,
      marginLeft: 16 + longest * 6.5,
      height: 26 * rows.length + 40,
      x: { domain: [from, 100], grid: true, label: null, tickFormat: (d: number) => `${d}%` },
      y: { label: null, domain: rows.map((r) => String(r[spec.y])) },
      marks: [
        Plot.link(rows, { x1: spec.x2!, x2: spec.x, y1: spec.y, y2: spec.y, stroke: muted, strokeWidth: 2 }),
        Plot.dot(rows, {
          x: spec.x2!,
          y: spec.y,
          r: 5,
          stroke: muted,
          strokeWidth: 2,
          fill: css("--surface"),
        }),
        Plot.dot(rows, {
          x: spec.x,
          y: spec.y,
          r: 5,
          fill: ink,
          tip: { format: { x: (d: number) => `${d.toFixed(1)}%` } },
        }),
      ],
    });
  }
  if (spec.kind === "missed") {
    // the flipped attendance view: values cluster near 0%, so the axis ends just above the data
    const parts = [
      { key: spec.x, label: "Absent or not voting" },
      { key: spec.x2!, label: "Absent with leave" },
    ];
    const colors = seriesColors();
    const long = rows.flatMap((r) =>
      parts.map((p) => ({ y: String(r[spec.y]), part: p.label, n: Number(r[p.key]) })),
    );
    const to = missedAxisMax(
      rows.flatMap((r) => [Number(r[spec.x]) + Number(r[spec.x2!]), Number(r.chamber)]),
    );
    const longest = Math.max(...rows.map((r) => String(r[spec.y]).length));
    return Plot.plot({
      width,
      style,
      marginLeft: 16 + longest * 6.5,
      height: 26 * rows.length + 60,
      x: { domain: [0, to], grid: true, label: null, tickFormat: (d: number) => `${d}%` },
      y: { label: null, domain: rows.map((r) => String(r[spec.y])) },
      color: { domain: parts.map((p) => p.label), range: [colors[0], colors[2]], legend: true },
      marks: [
        Plot.barX(long, {
          x: "n",
          y: "y",
          fill: "part",
          order: parts.map((p) => p.label),
          insetTop: 4,
          insetBottom: 4,
          tip: { format: { x: (d: number) => `${d.toFixed(1)}%` } },
        }),
        Plot.tickX(rows, { x: "chamber", y: spec.y, stroke: css("--ink"), strokeWidth: 2, tip: false }),
        Plot.ruleX([0], { stroke: css("--axis") }),
      ],
    });
  }
  if (spec.kind === "hbar") {
    const longest = Math.min(MAX_LABEL, Math.max(...rows.map((r) => String(r[spec.y]).length)));
    return Plot.plot({
      width,
      style,
      marginLeft: 16 + longest * 6.5,
      height: 28 * rows.length + 40,
      x: { grid: true, label: null, tickFormat: (d: number) => compactUsd.format(d) },
      y: { label: null, domain: rows.map((r) => String(r[spec.y])), tickFormat: clip },
      marks: [
        Plot.barX(rows, {
          x: spec.x,
          y: spec.y,
          fill: css("--series-1"),
          insetTop: 3,
          insetBottom: 3,
          rx: 2,
          tip: { format: { x: (d: number) => money(d) } },
        }),
        Plot.ruleX([0], { stroke: css("--axis") }),
      ],
    });
  }
  // stacked columns; color follows the series' fixed slot, so hiding one never repaints the others
  const order = spec.seriesOrder ?? [];
  const colors = seriesColors();
  const present = order.filter((s) => rows.some((r) => r[spec.series!] === s));
  return Plot.plot({
    width,
    style,
    height: 240,
    marginLeft: 56,
    // long year ranges (a judge's 40 years of cases) would overlap: label about one band per 50px
    x: {
      label: null,
      type: "band",
      ticks: thinTicks(
        rows.map((r) => String(r[spec.x])),
        width,
      ),
    },
    y: { grid: true, label: null, tickFormat: (d: number) => (spec.count ? count(d) : compactUsd.format(d)) },
    color: {
      domain: present,
      range: present.map((s) => colors[order.indexOf(s) % colors.length]),
      legend: present.length > 1,
    },
    marks: [
      Plot.barY(rows, {
        x: spec.x,
        y: spec.y,
        fill: spec.series,
        order: present,
        insetLeft: 2,
        insetRight: 2,
        tip: { format: { y: (d: number) => (spec.count ? count(d) : money(d)) } },
      }),
      Plot.ruleY([0], { stroke: css("--axis") }),
    ],
  });
}

/** Only reachable by hiding possible matches: every record behind this chart was a medium match. */
function emptyNote(): HTMLElement {
  const p = document.createElement("p");
  p.className = "small muted";
  p.textContent =
    'All records here are possible matches, which are hidden. Untick "Hide possible matches" to see them.';
  return p;
}

/** Swap the title, note, button states and table head to the figure's active view. */
function showView(fig: HTMLElement, id: string) {
  const spec = VIZ[id];
  fig.dataset.active = id;
  fig.querySelector("figcaption")!.textContent = spec.title;
  const note = fig.querySelector<HTMLElement>(":scope > p.small");
  if (note) note.textContent = spec.note ?? "";
  for (const b of fig.querySelectorAll<HTMLButtonElement>(".views button"))
    b.setAttribute("aria-pressed", String(b.dataset.view === id));
  const tr = document.createElement("tr");
  for (const c of spec.columns) {
    const th = document.createElement("th");
    th.textContent = c.label;
    if (c.money || c.num || c.pct) th.className = "num";
    tr.append(th);
  }
  fig.querySelector("thead")?.replaceChildren(tr);
}

function fillTable(fig: Element, spec: VizSpec, rows: Row[]) {
  const tbody = fig.querySelector("tbody");
  if (!tbody) return;
  tbody.replaceChildren(
    ...rows.map((r) => {
      const tr = document.createElement("tr");
      spec.columns.forEach((c, i) => {
        const td = document.createElement("td");
        if (c.link) {
          const url = String(r[c.key]);
          if (url) {
            const a = Object.assign(document.createElement("a"), {
              href: url,
              target: "_blank",
              rel: "noopener noreferrer",
            });
            a.textContent = "source ↗";
            td.append(a);
          } else {
            td.innerHTML = '<span class="muted">no link</span>';
          }
        } else {
          td.textContent = cellText(c, r);
        }
        if (c.money || c.num || c.pct) td.className = "num";
        if (i === 0 && r.confidence === "medium") {
          const b = document.createElement("span");
          b.className = "badge medium";
          b.textContent = "possible match";
          td.append(" ", b);
        }
        tr.append(td);
      });
      return tr;
    }),
  );
}

function render(bundle: OfficialBundle, tablesToo: boolean) {
  for (const fig of document.querySelectorAll<HTMLElement>("figure[data-viz]")) {
    const spec = VIZ[fig.dataset.active ?? fig.dataset.viz!];
    const target = fig.querySelector<HTMLElement>(".chart");
    if (!spec || !target) continue;
    const rows = spec.rows(bundle, hideMedium());
    if ((tablesToo && spec.usesConfidence) || fig.dataset.refill) fillTable(fig, spec, rows);
    delete fig.dataset.refill;
    target.replaceChildren(rows.length ? chart(spec, rows, Math.max(280, target.clientWidth)) : emptyNote());
  }
}

async function main() {
  const article = document.querySelector<HTMLElement>("article[data-bundle-url]");
  if (!article || !document.querySelector("figure[data-viz]")) return;
  const res = await fetch(article.dataset.bundleUrl!);
  if (!res.ok) return; // tables still show everything
  const bundle = (await res.json()) as OfficialBundle;
  // the server tables include medium rows; redraw them if the reader already hides those
  render(bundle, hideMedium());
  for (const fig of document.querySelectorAll<HTMLElement>("figure[data-viz]")) {
    fig.addEventListener("click", (e) => {
      const id = (e.target as HTMLElement).closest<HTMLElement>(".views button")?.dataset.view;
      if (!id || id === (fig.dataset.active ?? fig.dataset.viz)) return;
      showView(fig, id);
      fig.dataset.refill = "1";
      render(bundle, false);
    });
  }
  document.addEventListener("hide-medium-change", () => render(bundle, true));
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => render(bundle, false));
  let lastWidth = window.innerWidth;
  window.addEventListener("resize", () => {
    if (Math.abs(window.innerWidth - lastWidth) < 40) return;
    lastWidth = window.innerWidth;
    render(bundle, false);
  });
}

main();
