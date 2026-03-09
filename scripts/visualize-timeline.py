#!/usr/bin/env python3
"""Generate an interactive HTML timeline from memory system data."""

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Memory Timeline</title>
<script src="https://d3js.org/d3.v7.min.js"></script>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0d1117; color: #c9d1d9; }
#header { padding: 16px 24px; border-bottom: 1px solid #30363d; display: flex; justify-content: space-between; align-items: center; }
#header h1 { font-size: 18px; font-weight: 600; }
#stats { font-size: 13px; color: #8b949e; }
#filters { padding: 10px 24px; border-bottom: 1px solid #30363d; display: flex; gap: 8px; flex-wrap: wrap; }
.filter-btn { padding: 4px 12px; border-radius: 12px; border: 1px solid #30363d; background: transparent; color: #8b949e; cursor: pointer; font-size: 12px; transition: all 0.15s; }
.filter-btn.active { border-color: #58a6ff; color: #58a6ff; background: rgba(88,166,255,0.1); }
.filter-btn:hover { border-color: #58a6ff; }
#timeline { padding: 24px; overflow-y: auto; height: calc(100vh - 100px); }
.day-group { margin-bottom: 24px; }
.day-label { font-size: 14px; font-weight: 600; color: #58a6ff; margin-bottom: 8px; padding-left: 20px; border-left: 2px solid #30363d; }
.event-card { margin-left: 20px; padding: 8px 12px; border-left: 3px solid #30363d; margin-bottom: 4px; cursor: pointer; transition: background 0.15s; border-radius: 0 4px 4px 0; }
.event-card:hover { background: rgba(255,255,255,0.04); }
.event-title { font-size: 13px; font-weight: 500; }
.event-detail { font-size: 12px; color: #8b949e; margin-top: 2px; display: none; }
.event-card.expanded .event-detail { display: block; }
.event-meta { font-size: 11px; color: #6e7681; margin-top: 2px; }
.cat-decision .event-title { color: #d2a8ff; }
.cat-correction .event-title { color: #f85149; }
.cat-knowledge .event-title { color: #3fb950; }
.cat-behavioral .event-title { color: #d29922; }
.cat-milestone .event-title { color: #58a6ff; }
.cat-reflection .event-title { color: #79c0ff; }
.cat-positive .event-title { color: #56d364; }
.cat-break .event-title { color: #6e7681; }
.event-card.cat-decision { border-left-color: #d2a8ff; }
.event-card.cat-correction { border-left-color: #f85149; }
.event-card.cat-knowledge { border-left-color: #3fb950; }
.event-card.cat-behavioral { border-left-color: #d29922; }
.event-card.cat-milestone { border-left-color: #58a6ff; }
.event-card.cat-reflection { border-left-color: #79c0ff; }
.event-card.cat-positive { border-left-color: #56d364; }
.event-card.cat-break { border-left-color: #6e7681; }
#detail-panel { position: fixed; bottom: 0; left: 0; right: 0; background: #161b22; border-top: 1px solid #30363d; padding: 16px 24px; display: none; max-height: 30vh; overflow-y: auto; }
#detail-panel.visible { display: block; }
#detail-panel h3 { font-size: 14px; margin-bottom: 8px; }
#detail-panel p { font-size: 13px; color: #8b949e; line-height: 1.5; }
.legend { display: flex; gap: 16px; font-size: 12px; color: #8b949e; padding: 8px 24px; }
.legend-item { display: flex; align-items: center; gap: 4px; }
.legend-dot { width: 8px; height: 8px; border-radius: 50%; }
</style>
</head>
<body>
<div id="header">
  <h1>Memory Timeline</h1>
  <div id="stats"></div>
</div>
<div class="legend">
  <div class="legend-item"><span class="legend-dot" style="background:#d2a8ff"></span>Decision</div>
  <div class="legend-item"><span class="legend-dot" style="background:#f85149"></span>Correction</div>
  <div class="legend-item"><span class="legend-dot" style="background:#3fb950"></span>Knowledge</div>
  <div class="legend-item"><span class="legend-dot" style="background:#d29922"></span>Behavioral</div>
  <div class="legend-item"><span class="legend-dot" style="background:#58a6ff"></span>Milestone</div>
  <div class="legend-item"><span class="legend-dot" style="background:#79c0ff"></span>Reflection</div>
  <div class="legend-item"><span class="legend-dot" style="background:#56d364"></span>Positive</div>
</div>
<div id="filters"></div>
<div id="timeline"></div>
<div id="detail-panel"><h3 id="detail-title"></h3><p id="detail-body"></p></div>
<script>
const DATA = __TIMELINE_JSON__;
const categories = [...new Set(DATA.events.map(e => e.category))].sort();

const statsEl = document.getElementById('stats');
statsEl.textContent = `${DATA.summary.total_sessions} sessions | ${DATA.summary.date_range} | ${DATA.summary.knowledge_items} knowledge items | ${DATA.summary.graph_nodes} graph nodes`;

const filtersEl = document.getElementById('filters');
const activeFilters = new Set(categories);
const allBtn = document.createElement('button');
allBtn.className = 'filter-btn active';
allBtn.textContent = 'All';
allBtn.onclick = () => { categories.forEach(c => activeFilters.add(c)); render(); updateFilterBtns(); };
filtersEl.appendChild(allBtn);
categories.forEach(cat => {
  const btn = document.createElement('button');
  btn.className = 'filter-btn active';
  btn.textContent = cat;
  btn.dataset.cat = cat;
  btn.onclick = () => {
    if (activeFilters.has(cat)) activeFilters.delete(cat); else activeFilters.add(cat);
    render(); updateFilterBtns();
  };
  filtersEl.appendChild(btn);
});

function updateFilterBtns() {
  filtersEl.querySelectorAll('.filter-btn').forEach(btn => {
    if (btn.dataset.cat) btn.classList.toggle('active', activeFilters.has(btn.dataset.cat));
    else btn.classList.toggle('active', activeFilters.size === categories.length);
  });
}

function render() {
  const timeline = document.getElementById('timeline');
  timeline.innerHTML = '';
  const filtered = DATA.events.filter(e => activeFilters.has(e.category));
  const grouped = {};
  filtered.forEach(e => { (grouped[e.date] = grouped[e.date] || []).push(e); });
  const dates = Object.keys(grouped).sort().reverse();
  dates.forEach(date => {
    const group = document.createElement('div');
    group.className = 'day-group';
    const label = document.createElement('div');
    label.className = 'day-label';
    const d = new Date(date + 'T12:00:00');
    label.textContent = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
    group.appendChild(label);
    grouped[date].forEach(evt => {
      const card = document.createElement('div');
      card.className = `event-card cat-${evt.category}`;
      card.innerHTML = `<div class="event-title">${evt.title}</div><div class="event-detail">${evt.detail || ''}</div><div class="event-meta">${evt.category}${evt.source_episode ? ' · ' + evt.source_episode : ''}</div>`;
      card.onclick = () => {
        card.classList.toggle('expanded');
        const panel = document.getElementById('detail-panel');
        document.getElementById('detail-title').textContent = evt.title;
        document.getElementById('detail-body').textContent = evt.detail || 'No additional detail.';
        panel.classList.add('visible');
      };
      group.appendChild(card);
    });
    timeline.appendChild(group);
  });
}
render();
document.addEventListener('keydown', e => { if (e.key === 'Escape') document.getElementById('detail-panel').classList.remove('visible'); });
</script>
</body>
</html>
"""


def extract_events(repo_root: Path) -> dict:
    """Extract timeline events from all memory data sources."""
    events = []
    data_dir = repo_root / "agent-persona" / "data"

    # --- Episodic records (archived + active) ---
    for ep_dir in [data_dir / "episodic" / "archived", data_dir / "episodic"]:
        if not ep_dir.exists():
            continue
        for ep_file in sorted(ep_dir.glob("episode_*.json")):
            try:
                ep = json.loads(ep_file.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                continue
            session_id = ep.get("session", ep_file.stem)
            date_part = session_id.replace("episode_", "")[:10]
            for rec in ep.get("records", []):
                rtype = rec.get("type", "event")
                content = rec.get("content", "")
                ev = rec.get("emotional_value", 0) or 0
                ts = rec.get("ts", "")
                rec_date = ts[:10] if ts else date_part

                if "inferred break" in content.lower():
                    cat = "break"
                elif rtype == "decision":
                    cat = "decision"
                elif rtype == "correction":
                    cat = "correction"
                elif rtype == "entity":
                    cat = "milestone"
                elif ev >= 2:
                    cat = "positive"
                elif ev <= -1:
                    cat = "correction"
                else:
                    continue  # skip mundane events

                title = content[:120] + ("..." if len(content) > 120 else "")
                events.append({
                    "date": rec_date,
                    "category": cat,
                    "title": title,
                    "detail": content,
                    "source_episode": session_id,
                    "emotional_value": ev,
                })

    # --- Knowledge milestones (high-strength items) ---
    kj_path = data_dir / "knowledge" / "knowledge.json"
    knowledge_items = 0
    if kj_path.exists():
        try:
            kj = json.loads(kj_path.read_text(encoding="utf-8"))
            items = kj.get("items", [])
            knowledge_items = len(items)
            for item in items:
                if item.get("strength", 1) >= 3:
                    source = item.get("source", "")
                    first_ep = source.split(",")[0].strip() if source else ""
                    date = first_ep.replace("episode_", "")[:10] if first_ep.startswith("episode_") else ""
                    if date:
                        events.append({
                            "date": date,
                            "category": "knowledge",
                            "title": f"[{item.get('type', '?')}] {item.get('content', '')[:100]}",
                            "detail": f"Strength {item.get('strength', 1)}. {item.get('content', '')}",
                            "source_episode": first_ep,
                        })
        except (json.JSONDecodeError, OSError):
            pass

    # --- Learned triggers ---
    lt_path = data_dir / "learned_triggers.json"
    if lt_path.exists():
        try:
            lt = json.loads(lt_path.read_text(encoding="utf-8"))
            for trig in lt.get("triggers", []):
                eps = trig.get("source_episodes", [])
                date = eps[0].replace("episode_", "")[:10] if eps else ""
                if date and trig.get("approved"):
                    events.append({
                        "date": date,
                        "category": "behavioral",
                        "title": f"Trigger: {trig.get('id', '?')}",
                        "detail": f"{trig.get('condition', '')} → {trig.get('action', '')}",
                        "source_episode": eps[0] if eps else "",
                    })
        except (json.JSONDecodeError, OSError):
            pass

    # --- Procedural notes ---
    pn_path = data_dir / "procedural_notes.json"
    if pn_path.exists():
        try:
            pn = json.loads(pn_path.read_text(encoding="utf-8"))
            for note in pn.get("notes", []):
                date = note.get("created", "")
                if date:
                    events.append({
                        "date": date,
                        "category": "behavioral",
                        "title": f"Note: {note.get('content', '')[:80]}",
                        "detail": f"[{note.get('status', '?')}] {note.get('content', '')}",
                        "source_episode": note.get("source_reflection", ""),
                    })
        except (json.JSONDecodeError, OSError):
            pass

    # --- Reflections ---
    ref_path = data_dir / "eval" / "reflections.json"
    if ref_path.exists():
        try:
            rf = json.loads(ref_path.read_text(encoding="utf-8"))
            for refl in rf.get("reflections", []):
                date = refl.get("date", "")
                obs_count = len(refl.get("observations", []))
                adj_count = len(refl.get("adjustments", []))
                ver_count = len(refl.get("verifications", []))
                if date:
                    events.append({
                        "date": date,
                        "category": "reflection",
                        "title": f"Reflection: {obs_count} observations, {adj_count} adjustments",
                        "detail": f"Observations: {obs_count}, Adjustments: {adj_count}, Verifications: {ver_count}",
                        "source_episode": "",
                    })
        except (json.JSONDecodeError, OSError):
            pass

    # --- Graph stats for summary ---
    graph_nodes = 0
    mg_path = data_dir / "knowledge" / "memory_graph.json"
    if mg_path.exists():
        try:
            mg = json.loads(mg_path.read_text(encoding="utf-8"))
            graph_nodes = len(mg.get("nodes", []))
        except (json.JSONDecodeError, OSError):
            pass

    # Sort events by date descending, then by category
    events.sort(key=lambda e: (e["date"], e["category"]))

    # Build summary
    all_dates = [e["date"] for e in events if e["date"]]
    ep_dates = set()
    for ep_dir in [data_dir / "episodic" / "archived", data_dir / "episodic"]:
        if ep_dir.exists():
            for f in ep_dir.glob("episode_*.json"):
                ep_dates.add(f.stem.replace("episode_", "")[:10])

    summary = {
        "total_sessions": len(ep_dates),
        "date_range": f"{min(all_dates)} to {max(all_dates)}" if all_dates else "no data",
        "knowledge_items": knowledge_items,
        "graph_nodes": graph_nodes,
        "total_events": len(events),
    }

    return {"events": events, "summary": summary}


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Generate memory timeline HTML")
    parser.add_argument("--input-dir", type=Path, default=REPO_ROOT / "agent-persona" / "data",
                        help="Path to agent-persona/data directory")
    parser.add_argument("--output", type=Path,
                        default=REPO_ROOT / "agent-persona" / "data" / "knowledge" / "memory_timeline.html",
                        help="Output HTML file path")
    args = parser.parse_args()

    print(f"Reading data from {args.input_dir}...")
    timeline_data = extract_events(args.input_dir.parent.parent)

    print(f"Extracted {timeline_data['summary']['total_events']} events from "
          f"{timeline_data['summary']['total_sessions']} sessions")

    json_str = json.dumps(timeline_data, ensure_ascii=False)
    html = HTML_TEMPLATE.replace("__TIMELINE_JSON__", json_str)

    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(html, encoding="utf-8")
        print(f"Timeline written to {args.output}")
    except OSError as exc:
        print(f"Error writing output: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
