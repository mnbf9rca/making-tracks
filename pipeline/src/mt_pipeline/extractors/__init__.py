"""Extractor registry shared by source-specific pipeline modules."""

from __future__ import annotations

from typing import Protocol, runtime_checkable


@runtime_checkable
class Extractor(Protocol):
    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int: ...


class Registry:
    def __init__(self) -> None:
        self._order: list[str] = []
        self._by_source: dict[str, object] = {}

    def register(self, source: str, extractor) -> None:
        if source not in self._by_source:
            self._order.append(source)
        self._by_source[source] = extractor

    def enabled_for(self, sources: dict) -> list[tuple[str, object]]:
        return [
            (source, self._by_source[source])
            for source in self._order
            if sources.get(source) is True
        ]

    def registered_sources(self) -> set[str]:
        return set(self._by_source)
