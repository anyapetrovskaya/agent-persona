#!/usr/bin/env python3
"""Generate a standalone 3D HTML visualization of the memory graph using 3d-force-graph."""

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Memory Graph (3D)</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
  background: #0a0a1a;
  color: #e0e0e0;
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  overflow: hidden;
  height: 100vh;
  width: 100vw;
}
#graph { width: 100%; height: 100%; }

#header {
  position: fixed; top: 0; left: 0; z-index: 10;
  padding: 18px 24px;
  pointer-events: none;
  max-width: 480px;
}
#header h1 {
  font-size: 1.35rem; font-weight: 600; color: #fff;
  letter-spacing: 0.03em;
  text-shadow: 0 0 20px rgba(74, 144, 217, 0.4);
  margin-bottom: 4px;
}
#header .meta {
  font-size: 0.8rem; color: #6a6a8a;
  line-height: 1.4;
}

#legend {
  position: fixed; top: 18px; right: 20px; z-index: 10;
  background: rgba(10, 10, 26, 0.85);
  border: 1px solid #1e1e3a;
  border-radius: 10px;
  padding: 14px 18px;
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
}
#legend h3 {
  font-size: 0.75rem; color: #666; text-transform: uppercase;
  letter-spacing: 0.08em; margin-bottom: 8px;
}
.legend-item {
  display: flex; align-items: center; gap: 8px;
  font-size: 0.8rem; color: #aaa; padding: 2px 0;
}
.legend-dot {
  width: 10px; height: 10px; border-radius: 50%;
  flex-shrink: 0;
}

#detail {
  position: fixed; bottom: 20px; left: 20px; z-index: 20;
  width: 360px; max-height: calc(100vh - 60px);
  overflow-y: auto;
  background: rgba(14, 14, 36, 0.92);
  border: 1px solid #2a2a4a;
  border-radius: 12px;
  padding: 22px;
  display: none;
  box-shadow: 0 12px 48px rgba(0, 0, 0, 0.6);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
}
#detail::-webkit-scrollbar { width: 4px; }
#detail::-webkit-scrollbar-thumb { background: #333; border-radius: 2px; }
#detail h2 {
  font-size: 1.1rem; color: #fff; margin-bottom: 6px;
  text-shadow: 0 0 12px rgba(255,255,255,0.1);
}
#detail .type-badge {
  display: inline-block; padding: 3px 12px; border-radius: 12px;
  font-size: 0.73rem; font-weight: 600; margin-bottom: 12px;
  letter-spacing: 0.02em;
}
#detail .summary {
  font-size: 0.84rem; color: #b0b0c8; margin-bottom: 14px;
  line-height: 1.5;
}
#detail .dates { font-size: 0.76rem; color: #5a5a7a; margin-bottom: 16px; }
#detail h3 {
  font-size: 0.8rem; color: #7a7a9a; margin: 12px 0 8px;
  text-transform: uppercase; letter-spacing: 0.06em;
}
#detail .edge-item {
  font-size: 0.8rem; color: #8888a8; padding: 6px 0;
  border-bottom: 1px solid #1a1a3a;
}
#detail .edge-item:last-child { border-bottom: none; }
#detail .edge-type { color: #6ee8c0; font-weight: 500; }
#detail .edge-target { color: #ccccdd; }
#detail .close-btn {
  position: absolute; top: 12px; right: 16px;
  background: none; border: none; color: #555; font-size: 1.3rem;
  cursor: pointer; transition: color 0.2s;
}
#detail .close-btn:hover { color: #fff; }
</style>
</head>
<body>
<div id="graph"></div>

<div id="header">
  <h1>Memory Graph (3D)</h1>
  <span class="meta" id="meta"></span>
</div>

<div id="legend">
  <h3>Node Types</h3>
  <div class="legend-item"><span class="legend-dot" style="background:#4A90D9"></span>Person</div>
  <div class="legend-item"><span class="legend-dot" style="background:#50B86C"></span>Component</div>
  <div class="legend-item"><span class="legend-dot" style="background:#E6A23C"></span>Tool</div>
  <div class="legend-item"><span class="legend-dot" style="background:#9B59B6"></span>Concept</div>
  <div class="legend-item"><span class="legend-dot" style="background:#E74C3C"></span>Preference</div>
  <div class="legend-item"><span class="legend-dot" style="background:#1ABC9C"></span>Decision</div>
  <div class="legend-item"><span class="legend-dot" style="background:#95A5A6"></span>Other</div>
</div>

<div id="detail">
  <button class="close-btn" onclick="closeDetail()">&times;</button>
  <h2 id="d-name"></h2>
  <span class="type-badge" id="d-type"></span>
  <div class="summary" id="d-summary"></div>
  <div class="dates" id="d-dates"></div>
  <h3>Connections</h3>
  <div id="d-edges"></div>
</div>

<script src="https://unpkg.com/3d-force-graph"></script>
<script>
const GRAPH_DATA = __GRAPH_JSON__;

const TYPE_COLORS = {
  person: '#4A90D9', component: '#50B86C', tool: '#E6A23C',
  concept: '#9B59B6', preference: '#E74C3C', decision: '#1ABC9C'
};
const DEFAULT_COLOR = '#95A5A6';
function nodeColor(type) { return TYPE_COLORS[type] || DEFAULT_COLOR; }

const nodes = GRAPH_DATA.nodes.map(d => ({...d}));
const links = GRAPH_DATA.edges.map(d => ({...d}));

const degreeMap = {};
nodes.forEach(n => { degreeMap[n.id] = 0; });
links.forEach(e => {
  degreeMap[e.source] = (degreeMap[e.source] || 0) + 1;
  degreeMap[e.target] = (degreeMap[e.target] || 0) + 1;
});

nodes.forEach(n => {
  n.val = 2 + (degreeMap[n.id] || 0) * 0.8;
  n.color = nodeColor(n.type);
});

document.getElementById('meta').textContent =
  `Built ${GRAPH_DATA.last_built || '\u2014'}  \u00b7  ${nodes.length} nodes  \u00b7  ${links.length} edges`;

let hoveredNode = null;
let selectedNode = null;

const graph = ForceGraph3D()(document.getElementById('graph'))
  .graphData({ nodes, links })
  .backgroundColor('#0a0a1a')
  .nodeColor(node => {
    if (!hoveredNode) return node.color;
    return isNeighbor(node, hoveredNode) ? node.color : 'rgba(60,60,80,0.3)';
  })
  .nodeVal(node => node.val)
  .nodeLabel(node => `<div style="color:white;background:rgba(0,0,0,0.8);padding:8px;border-radius:4px;font-size:13px"><b>${node.name || node.id}</b><br/><span style="color:${node.color}">${node.type}</span></div>`)
  .nodeOpacity(0.9)
  .nodeResolution(16)
  .linkColor(() => 'rgba(120, 130, 160, 0.25)')
  .linkOpacity(0.6)
  .linkWidth(link => 0.3 + (link.confidence || 0.5) * 0.6)
  .linkDirectionalArrowLength(3.5)
  .linkDirectionalArrowRelPos(1)
  .linkDirectionalArrowColor(() => 'rgba(160, 170, 200, 0.5)')
  .linkLabel(link => `<span style="color:#ccc;background:rgba(10,10,26,0.85);padding:4px 10px;border-radius:6px;font-size:13px;">${link.type || ''}</span>`)
  .onNodeHover(node => {
    document.body.style.cursor = node ? 'pointer' : 'default';
    hoveredNode = node || null;
    updateHighlight();
  })
  .onNodeClick(node => {
    if (node) {
      if (selectedNode && selectedNode.id === node.id) {
        selectedNode = null;
        closeDetail();
        updateHighlight();
        return;
      }
      selectedNode = node;
      showDetail(node);
      updateHighlight();
    }
  })
  .onBackgroundClick(() => {
    selectedNode = null;
    closeDetail();
    updateHighlight();
  });

graph.d3Force('charge').strength(-60);
graph.d3Force('link').distance(40);

const neighborMap = {};
function buildNeighborMap() {
  const data = graph.graphData();
  data.nodes.forEach(n => { neighborMap[n.id] = new Set(); });
  data.links.forEach(l => {
    const sid = typeof l.source === 'object' ? l.source.id : l.source;
    const tid = typeof l.target === 'object' ? l.target.id : l.target;
    if (neighborMap[sid]) neighborMap[sid].add(tid);
    if (neighborMap[tid]) neighborMap[tid].add(sid);
  });
}
setTimeout(buildNeighborMap, 500);

function isNeighbor(nodeA, nodeB) {
  if (!nodeB) return true;
  if (nodeA.id === nodeB.id) return true;
  const neighbors = neighborMap[nodeB.id];
  return neighbors ? neighbors.has(nodeA.id) : false;
}

function updateHighlight() {
  const active = hoveredNode || selectedNode;

  if (active) {
    graph.graphData().links.forEach(l => {
      const sid = typeof l.source === 'object' ? l.source.id : l.source;
      const tid = typeof l.target === 'object' ? l.target.id : l.target;
      l.__lineOpacity = (sid === active.id || tid === active.id) ? 0.9 : 0.04;
    });
  }

  graph
    .nodeColor(node => {
      if (!active) return node.color;
      if (selectedNode && !hoveredNode && node.id === selectedNode.id) return '#fff';
      return isNeighbor(node, active) ? node.color : 'rgba(60,60,80,0.3)';
    })
    .linkWidth(link => {
      const base = 0.3 + (link.confidence || 0.5) * 0.6;
      if (!active) return base;
      const sid = typeof link.source === 'object' ? link.source.id : link.source;
      const tid = typeof link.target === 'object' ? link.target.id : link.target;
      return (sid === active.id || tid === active.id) ? base + 1.5 : base;
    })
    .linkOpacity(l => active ? (l.__lineOpacity || 0.04) : 0.6)
    .linkColor(l => {
      if (!active) return 'rgba(120, 130, 160, 0.25)';
      const sid = typeof l.source === 'object' ? l.source.id : l.source;
      const tid = typeof l.target === 'object' ? l.target.id : l.target;
      return (sid === active.id || tid === active.id)
        ? 'rgba(138, 170, 255, 0.8)' : 'rgba(60, 60, 80, 0.08)';
    });
}

function edgeConnected(e, nodeId) {
  const sid = typeof e.source === 'object' ? e.source.id : e.source;
  const tid = typeof e.target === 'object' ? e.target.id : e.target;
  return sid === nodeId || tid === nodeId;
}

function showDetail(d) {
  const panel = document.getElementById('detail');
  document.getElementById('d-name').textContent = d.name || d.id;
  const badge = document.getElementById('d-type');
  badge.textContent = d.type;
  badge.style.background = nodeColor(d.type) + '22';
  badge.style.color = nodeColor(d.type);
  badge.style.border = '1px solid ' + nodeColor(d.type) + '44';
  document.getElementById('d-summary').textContent = d.summary || '';
  document.getElementById('d-dates').textContent =
    `First seen: ${d.first_seen || '\u2014'}  \u00b7  Last seen: ${d.last_seen || '\u2014'}`;
  const edgesDiv = document.getElementById('d-edges');
  const allLinks = graph.graphData().links;
  const connected = allLinks.filter(e => edgeConnected(e, d.id));
  if (connected.length === 0) {
    edgesDiv.innerHTML = '<div class="edge-item" style="color:#444">No connections</div>';
  } else {
    edgesDiv.innerHTML = connected.map(e => {
      const sid = typeof e.source === 'object' ? e.source.id : e.source;
      const tid = typeof e.target === 'object' ? e.target.id : e.target;
      const other = sid === d.id ? tid : sid;
      const otherNode = nodes.find(n => n.id === other);
      const dir = sid === d.id ? '\u2192' : '\u2190';
      return `<div class="edge-item">
        <span class="edge-type">${e.type || ''}</span> ${dir}
        <span class="edge-target">${otherNode ? (otherNode.name || otherNode.id) : other}</span>
        <div style="color:#5a5a7a;font-size:0.74rem;margin-top:3px">${e.fact || ''}</div>
      </div>`;
    }).join('');
  }
  panel.style.display = 'block';
}

function closeDetail() {
  document.getElementById('detail').style.display = 'none';
  if (selectedNode) {
    selectedNode = null;
    updateHighlight();
  }
}

setTimeout(() => {
  const n = nodes.length;
  const dist = Math.max(200, n * 6);
  graph.cameraPosition({ x: dist * 0.7, y: dist * 0.5, z: dist * 0.7 });
}, 800);
</script>
</body>
</html>"""


def main():
    parser = argparse.ArgumentParser(description="Visualize memory graph as interactive 3D HTML")
    parser.add_argument(
        "--input",
        default=str(REPO_ROOT / "agent-persona" / "data" / "knowledge" / "memory_graph.json"),
        help="Path to memory_graph.json",
    )
    parser.add_argument(
        "--output",
        default=str(REPO_ROOT / "agent-persona" / "data" / "knowledge" / "memory_graph_3d.html"),
        help="Path for output HTML file",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.exists():
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    try:
        graph_data = json.loads(input_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        print(f"Error reading input: {exc}", file=sys.stderr)
        sys.exit(1)

    for key in ("nodes", "edges"):
        if key not in graph_data:
            print(f"Error: missing '{key}' in graph data", file=sys.stderr)
            sys.exit(1)

    graph_json_str = json.dumps(graph_data, ensure_ascii=False)
    html = HTML_TEMPLATE.replace("__GRAPH_JSON__", graph_json_str)

    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(html, encoding="utf-8")
    except OSError as exc:
        print(f"Error writing output: {exc}", file=sys.stderr)
        sys.exit(1)

    print(str(output_path))


if __name__ == "__main__":
    main()
