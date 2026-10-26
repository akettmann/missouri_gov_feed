// One source link in a compare-page cell, built from DOM calls so it can be tested with a stand-in document.
export interface ValueLink {
  text: string;
  href: string;
  context?: string;
}

function el(doc: Document, tag: string, text?: string, cls?: string): HTMLElement {
  const e = doc.createElement(tag);
  if (text != null) e.textContent = text;
  if (cls) e.className = cls;
  return e;
}

/** A `div.small` holding the link; the screen-reader context is sr-only text and the arrow is aria-hidden (same markup as SourceLink). */
export function valueLinkLine(doc: Document, l: ValueLink): HTMLElement {
  const a = el(doc, "a", l.text) as HTMLAnchorElement;
  if (l.context) a.append(" ", el(doc, "span", l.context, "sr-only"));
  const arrow = el(doc, "span", "↗");
  arrow.setAttribute("aria-hidden", "true");
  a.append(arrow);
  a.href = l.href;
  a.rel = "noopener noreferrer";
  a.target = "_blank";
  const line = el(doc, "div", undefined, "small");
  line.append(a);
  return line;
}
