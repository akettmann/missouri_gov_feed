"""Lossless-enough XML -> JSON so XML sources can land in DuckDB as JSON for dbt to unpack.

Every element with children becomes {child_tag: [values...]} — children are *always* lists, even
when there's one, so dbt can use stable paths like `$.Action[*].RollCall[0].TotalYes[0]`.
Leaf elements become their stripped text. Attributes go under "@attr".
"""

from lxml import etree

from mogov import xmlparse


def element_to_obj(el: etree._Element) -> object:
    children = [c for c in el if isinstance(c.tag, str)]
    if not children and not el.attrib:
        return (el.text or "").strip()
    obj: dict[str, object] = {}
    if el.attrib:
        obj["@attr"] = dict(el.attrib)
    if not children:
        obj["#text"] = (el.text or "").strip()
    for c in children:
        obj.setdefault(c.tag, []).append(element_to_obj(c))
    return obj


def parse(data: bytes) -> object:
    return element_to_obj(xmlparse.parse(data))
