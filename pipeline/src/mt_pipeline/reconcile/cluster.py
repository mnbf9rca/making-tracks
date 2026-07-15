"""Candidate-place clustering over shared canonical refs."""

from __future__ import annotations

import difflib
import math
import unicodedata
from dataclasses import dataclass, field

MAX_NAME_LEN = 256
EARTH_RADIUS_M = 6_371_000.0


@dataclass(frozen=True)
class Member:
    source: str
    source_ref: str
    name: str
    lat: float
    lon: float
    refs: frozenset[str]


@dataclass
class Cluster:
    members: list[Member]
    refs: set[str] = field(default_factory=set)


@dataclass(frozen=True)
class FuzzyConfig:
    sim_defer: float = 0.85
    dist_defer_m: float = 150.0
    min_alnum: int = 4


@dataclass(frozen=True)
class FuzzyDefer:
    anchor_a: str
    anchor_b: str
    sim: float
    dist_m: float


class _UnionFind:
    def __init__(self) -> None:
        self.parent: dict[str, str] = {}

    def find(self, item: str) -> str:
        self.parent.setdefault(item, item)
        root = item
        while self.parent[root] != root:
            root = self.parent[root]
        while self.parent[item] != root:
            self.parent[item], item = root, self.parent[item]
        return root

    def union(self, left: str, right: str) -> None:
        left_root = self.find(left)
        right_root = self.find(right)
        if left_root == right_root:
            return
        keep, replace = sorted((left_root, right_root))
        self.parent[replace] = keep


def cluster_by_refs(members) -> list[Cluster]:
    uf = _UnionFind()
    ref_owner: dict[str, str] = {}
    member_keys = []
    for index, member in enumerate(members):
        member_key = f"m{index}"
        member_keys.append(member_key)
        uf.find(member_key)
        for ref in sorted(member.refs):
            if ref in ref_owner:
                uf.union(member_key, ref_owner[ref])
            else:
                ref_owner[ref] = member_key
                uf.union(member_key, ref)

    grouped: dict[str, list[Member]] = {}
    for member_key, member in zip(member_keys, members):
        grouped.setdefault(uf.find(member_key), []).append(member)

    clusters = []
    for group in grouped.values():
        refs = set()
        for member in group:
            refs.update(member.refs)
        if not refs:
            continue
        clusters.append(
            Cluster(
                members=sorted(group, key=lambda item: item.source_ref),
                refs=refs,
            )
        )
    return sorted(clusters, key=lambda cluster: min(cluster.refs))


def normalize_name(value: str) -> str:
    capped = str(value)[:MAX_NAME_LEN]
    decomposed = unicodedata.normalize("NFKD", capped)
    stripped = "".join(
        char for char in decomposed if not unicodedata.combining(char)
    ).casefold()
    words = []
    current = []
    for char in stripped:
        if char.isalnum():
            current.append(char)
        elif current:
            words.append("".join(current))
            current = []
    if current:
        words.append("".join(current))
    return " ".join(words).strip()


def _alnum_count(value: str) -> int:
    return sum(1 for char in value if char.isalnum())


def name_similarity(left: str, right: str) -> float:
    return difflib.SequenceMatcher(
        None, normalize_name(left), normalize_name(right)
    ).ratio()


def haversine_m(left_lat: float, left_lon: float, right_lat: float, right_lon: float) -> float:
    phi1 = math.radians(left_lat)
    phi2 = math.radians(right_lat)
    delta_phi = math.radians(right_lat - left_lat)
    delta_lambda = math.radians(right_lon - left_lon)
    term = (
        math.sin(delta_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    )
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(term)))


def _anchor(cluster: Cluster) -> str:
    return min(cluster.refs)


def fuzzy_defer(clusters: list[Cluster], config: FuzzyConfig) -> list[FuzzyDefer]:
    deferred: list[FuzzyDefer] = []
    ordered = sorted(clusters, key=_anchor)
    normalized: dict[str, str] = {
        member.source_ref: normalize_name(member.name)
        for cluster in ordered
        for member in cluster.members
    }

    for left_index, left in enumerate(ordered):
        for right in ordered[left_index + 1 :]:
            if left.refs & right.refs:
                continue
            best: FuzzyDefer | None = None
            for left_member in left.members:
                left_name = normalized[left_member.source_ref]
                if _alnum_count(left_name) < config.min_alnum:
                    continue
                for right_member in right.members:
                    right_name = normalized[right_member.source_ref]
                    if _alnum_count(right_name) < config.min_alnum:
                        continue
                    dist_m = haversine_m(
                        left_member.lat,
                        left_member.lon,
                        right_member.lat,
                        right_member.lon,
                    )
                    if dist_m > config.dist_defer_m:
                        continue
                    sim = difflib.SequenceMatcher(None, left_name, right_name).ratio()
                    if sim < config.sim_defer:
                        continue
                    candidate = FuzzyDefer(
                        anchor_a=_anchor(left),
                        anchor_b=_anchor(right),
                        sim=sim,
                        dist_m=dist_m,
                    )
                    if best is None or (candidate.sim, -candidate.dist_m) > (
                        best.sim,
                        -best.dist_m,
                    ):
                        best = candidate
            if best is not None:
                deferred.append(best)
    return deferred
