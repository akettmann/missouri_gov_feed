"""Shared lxml parsing for XML sources: one hardened parser config and namespace-agnostic element selection.

Loaders parse XML with this (never regex) and select elements by local name, so attributes, namespaces,
entities, CDATA and comments are handled by the parser.
"""

from collections.abc import Iterator

from lxml import etree


def parse(data: bytes, errors: list[str] | None = None) -> etree._Element:
    """Root element of an XML document. Tolerant of malformed input; never resolves entities or touches the network.
    When lxml had to recover from errors, they are appended to `errors` (if given) so the caller can report them."""
    parser = etree.XMLParser(recover=True, resolve_entities=False, no_network=True, huge_tree=True)
    root = etree.fromstring(data, parser)
    if root is None:
        raise ValueError("no XML root element")
    if errors is not None:
        errors.extend(str(e) for e in parser.error_log)
    return root


def iter_text(root: etree._Element, *local_names: str) -> Iterator[tuple[str, str]]:
    """(local name, stripped text) of every non-empty element with one of these local names, in document order."""
    wanted = set(local_names)
    for el in root.iter():
        if not isinstance(el.tag, str):
            continue
        name = etree.QName(el).localname
        if name in wanted and (text := "".join(el.itertext()).strip()):
            yield name, text
