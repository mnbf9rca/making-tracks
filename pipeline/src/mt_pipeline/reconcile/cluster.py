"""Candidate-place clustering over shared canonical refs."""

from __future__ import annotations

from dataclasses import dataclass, field


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
