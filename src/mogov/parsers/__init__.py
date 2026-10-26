"""Parsers turn landed raw files into statically typed rows. A loader lands a source's files unchanged;
its parser walks them (here with lxml) and emits one dataclass row per entity the documents contain."""
