"""Render an idempotent catalog seed after its media objects are available."""

import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
catalog = json.loads((root / "Assets/Content/catalog.json").read_text())


def sql_json(value):
    return "'" + json.dumps(value, ensure_ascii=False, separators=(",", ":")).replace("'", "''") + "'::jsonb"


print("begin;")
for kind in ("shorts", "courses", "replays"):
    for position, source in enumerate(catalog[kind]):
        row = dict(source)
        key = row["id"]
        assert key.replace("-", "").isalnum() and key.isascii()
        steps = row.pop("steps", None)
        print("insert into app_private.catalog (id, kind, position, data) values "
              f"('{key}', '{kind}', {position}, {sql_json(row)}) "
              "on conflict (id) do update set kind = excluded.kind, position = excluded.position, data = excluded.data;")
        if steps is not None:
            print("insert into app_private.course_content (course, steps) values "
                  f"('{key}', {sql_json(steps)}) on conflict (course) do update set steps = excluded.steps;")
print("commit;")
