"""Canonical refs for a source record."""

from __future__ import annotations

import re

import mt_contracts

from .redirects import canonicalize_ref

_QID = re.compile(r"Q[0-9]+")


def refs_of(
    source: str, source_ref: str, props: dict, redirect_map: dict[str, str]
) -> set[str]:
    del source
    out: set[str] = set()
    own_ref = canonicalize_ref(source_ref, redirect_map)
    if mt_contracts.is_canonical_ref(own_ref):
        out.add(own_ref)

    wikidata = props.get("wikidata")
    if isinstance(wikidata, str) and _QID.fullmatch(wikidata):
        join_ref = canonicalize_ref(f"wd:{wikidata}", redirect_map)
        if mt_contracts.is_canonical_ref(join_ref):
            out.add(join_ref)
    return out
