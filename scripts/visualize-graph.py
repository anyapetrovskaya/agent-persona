#!/usr/bin/env python3
"""Generate a standalone HTML visualization of the memory graph using D3.js."""

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
<title>Memory Graph</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
  background: #1a1a2e;
  color: #e0e0e0;
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  overflow: hidden;
  height: 100vh;
  width: 100vw;
}
#header {
  position: fixed; top: 0; left: 0; right: 0; z-index: 10;
  display: flex; align-items: baseline; gap: 1.2rem;
  padding: 14px 24px;
  background: linear-gradient(180deg, rgba(26,26,46,0.97) 80%, rgba(26,26,46,0));
  pointer-events: none;
}
#header h1 {
  font-size: 1.3rem; font-weight: 600; color: #fff;
  letter-spacing: 0.02em;
}
#header .meta {
  font-size: 0.82rem; color: #8888aa;
}
svg { display: block; width: 100%; height: 100%; }
.link { fill: none; }
.link-label {
  font-size: 9px; fill: #8888aa; pointer-events: none;
  text-anchor: middle; dominant-baseline: central;
}
.node-label {
  font-size: 11px; fill: #ddd; pointer-events: none;
  text-anchor: middle; dominant-baseline: central;
  text-shadow: 0 0 4px #1a1a2e, 0 0 8px #1a1a2e;
}
#detail {
  position: fixed; top: 60px; right: 20px; z-index: 20;
  width: 320px; max-height: calc(100vh - 80px);
  overflow-y: auto;
  background: #16213e; border: 1px solid #2a2a4a;
  border-radius: 10px; padding: 20px;
  display: none;
  box-shadow: 0 8px 32px rgba(0,0,0,0.45);
}
#detail h2 { font-size: 1.1rem; color: #fff; margin-bottom: 6px; }
#detail .type-badge {
  display: inline-block; padding: 2px 10px; border-radius: 10px;
  font-size: 0.75rem; font-weight: 600; margin-bottom: 10px;
}
#detail .summary { font-size: 0.85rem; color: #bbb; margin-bottom: 12px; line-height: 1.45; }
#detail .dates { font-size: 0.78rem; color: #777; margin-bottom: 14px; }
#detail h3 { font-size: 0.85rem; color: #aaa; margin: 10px 0 6px; }
#detail .edge-item {
  font-size: 0.8rem; color: #999; padding: 4px 0;
  border-bottom: 1px solid #2a2a4a;
}
#detail .edge-item:last-child { border-bottom: none; }
#detail .edge-type { color: #6ec; font-weight: 500; }
#detail .edge-target { color: #ccc; }
#detail .close-btn {
  position: absolute; top: 10px; right: 14px;
  background: none; border: none; color: #666; font-size: 1.2rem;
  cursor: pointer;
}
#detail .close-btn:hover { color: #fff; }
</style>
</head>
<body>
<div id="header">
  <h1>Memory Graph</h1>
  <span class="meta" id="meta"></span>
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
<svg id="graph"></svg>

<script src="https://d3js.org/d3.v7.min.js"></script>
<script>
const GRAPH_DATA = __GRAPH_JSON__;

const TYPE_COLORS = {
  person: "#4A90D9", component: "#50B86C", tool: "#E6A23C",
  concept: "#9B59B6", preference: "#E74C3C", decision: "#1ABC9C"
};
const DEFAULT_COLOR = "#95A5A6";
function nodeColor(type) { return TYPE_COLORS[type] || DEFAULT_COLOR; }

const nodes = GRAPH_DATA.nodes.map(d => ({...d}));
const edges = GRAPH_DATA.edges.map(d => ({...d}));

const degreeMap = {};
nodes.forEach(n => { degreeMap[n.id] = 0; });
edges.forEach(e => {
  degreeMap[e.source] = (degreeMap[e.source] || 0) + 1;
  degreeMap[e.target] = (degreeMap[e.target] || 0) + 1;
});
const maxDeg = Math.max(1, ...Object.values(degreeMap));
function nodeRadius(id) {
  return 8 + (degreeMap[id] || 0) / maxDeg * 22;
}

document.getElementById("meta").textContent =
  `Built ${GRAPH_DATA.last_built || "—"}  ·  ${nodes.length} nodes  ·  ${edges.length} edges`;

const svg = d3.select("#graph");
const width = window.innerWidth;
const height = window.innerHeight;

const defs = svg.append("defs");
defs.append("marker")
  .attr("id", "arrow")
  .attr("viewBox", "0 -4 8 8")
  .attr("refX", 20).attr("refY", 0)
  .attr("markerWidth", 6).attr("markerHeight", 6)
  .attr("orient", "auto")
  .append("path").attr("d", "M0,-3L7,0L0,3").attr("fill", "#556");

defs.append("marker")
  .attr("id", "arrow-hi")
  .attr("viewBox", "0 -4 8 8")
  .attr("refX", 20).attr("refY", 0)
  .attr("markerWidth", 6).attr("markerHeight", 6)
  .attr("orient", "auto")
  .append("path").attr("d", "M0,-3L7,0L0,3").attr("fill", "#8af");

const g = svg.append("g");

const zoom = d3.zoom()
  .scaleExtent([0.15, 5])
  .on("zoom", e => g.attr("transform", e.transform));
svg.call(zoom);

const linkDist = Math.max(80, Math.min(200, 1200 / Math.sqrt(nodes.length || 1)));
const chargeStr = Math.max(-400, Math.min(-80, -15000 / (nodes.length || 1)));

const simulation = d3.forceSimulation(nodes)
  .force("link", d3.forceLink(edges).id(d => d.id).distance(linkDist))
  .force("charge", d3.forceManyBody().strength(chargeStr))
  .force("center", d3.forceCenter(width / 2, height / 2))
  .force("collision", d3.forceCollide().radius(d => nodeRadius(d.id) + 4));

const linkG = g.append("g").attr("class", "links");
const linkLabelG = g.append("g").attr("class", "link-labels");
const nodeG = g.append("g").attr("class", "nodes");
const labelG = g.append("g").attr("class", "labels");

const link = linkG.selectAll("line").data(edges).join("line")
  .attr("class", "link")
  .attr("stroke", "#445")
  .attr("stroke-width", 1.2)
  .attr("stroke-opacity", d => 0.3 + (d.confidence || 0.5) * 0.7)
  .attr("marker-end", "url(#arrow)");

const linkLabel = linkLabelG.selectAll("text").data(edges).join("text")
  .attr("class", "link-label")
  .text(d => d.type || "");

const node = nodeG.selectAll("circle").data(nodes).join("circle")
  .attr("r", d => nodeRadius(d.id))
  .attr("fill", d => nodeColor(d.type))
  .attr("stroke", "#1a1a2e").attr("stroke-width", 1.5)
  .style("cursor", "pointer");

const label = labelG.selectAll("text").data(nodes).join("text")
  .attr("class", "node-label")
  .attr("dy", d => nodeRadius(d.id) + 14)
  .text(d => d.name);

node.call(d3.drag()
  .on("start", (e, d) => {
    if (!e.active) simulation.alphaTarget(0.3).restart();
    d.fx = d.x; d.fy = d.y;
  })
  .on("drag", (e, d) => { d.fx = e.x; d.fy = e.y; })
  .on("end", (e, d) => {
    if (!e.active) simulation.alphaTarget(0);
    d.fx = null; d.fy = null;
  })
);

const connectedSet = (nodeId) => {
  const s = new Set([nodeId]);
  edges.forEach(e => {
    const sid = typeof e.source === "object" ? e.source.id : e.source;
    const tid = typeof e.target === "object" ? e.target.id : e.target;
    if (sid === nodeId) s.add(tid);
    if (tid === nodeId) s.add(sid);
  });
  return s;
};

const edgeConnected = (e, nodeId) => {
  const sid = typeof e.source === "object" ? e.source.id : e.source;
  const tid = typeof e.target === "object" ? e.target.id : e.target;
  return sid === nodeId || tid === nodeId;
};

node.on("mouseover", (ev, d) => {
  const cs = connectedSet(d.id);
  node.attr("opacity", n => cs.has(n.id) ? 1 : 0.12);
  label.attr("opacity", n => cs.has(n.id) ? 1 : 0.08);
  link.attr("stroke", e => edgeConnected(e, d.id) ? "#8af" : "#445")
      .attr("stroke-opacity", e => edgeConnected(e, d.id) ? 0.9 : 0.05)
      .attr("marker-end", e => edgeConnected(e, d.id) ? "url(#arrow-hi)" : "url(#arrow)");
  linkLabel.attr("opacity", e => edgeConnected(e, d.id) ? 1 : 0.05);
}).on("mouseout", () => {
  node.attr("opacity", 1);
  label.attr("opacity", 1);
  link.attr("stroke", "#445")
      .attr("stroke-opacity", d => 0.3 + (d.confidence || 0.5) * 0.7)
      .attr("marker-end", "url(#arrow)");
  linkLabel.attr("opacity", 1);
});

node.on("click", (ev, d) => {
  ev.stopPropagation();
  showDetail(d);
});
svg.on("click", () => closeDetail());

function showDetail(d) {
  const panel = document.getElementById("detail");
  document.getElementById("d-name").textContent = d.name;
  const badge = document.getElementById("d-type");
  badge.textContent = d.type;
  badge.style.background = nodeColor(d.type) + "33";
  badge.style.color = nodeColor(d.type);
  document.getElementById("d-summary").textContent = d.summary || "";
  document.getElementById("d-dates").textContent =
    `First seen: ${d.first_seen || "—"}  ·  Last seen: ${d.last_seen || "—"}`;
  const edgesDiv = document.getElementById("d-edges");
  const connected = edges.filter(e => edgeConnected(e, d.id));
  if (connected.length === 0) {
    edgesDiv.innerHTML = '<div class="edge-item" style="color:#666">No connections</div>';
  } else {
    edgesDiv.innerHTML = connected.map(e => {
      const sid = typeof e.source === "object" ? e.source.id : e.source;
      const tid = typeof e.target === "object" ? e.target.id : e.target;
      const other = sid === d.id ? tid : sid;
      const otherNode = nodes.find(n => n.id === other);
      const dir = sid === d.id ? "→" : "←";
      return `<div class="edge-item">
        <span class="edge-type">${e.type}</span> ${dir}
        <span class="edge-target">${otherNode ? otherNode.name : other}</span>
        <div style="color:#777;font-size:0.75rem;margin-top:2px">${e.fact || ""}</div>
      </div>`;
    }).join("");
  }
  panel.style.display = "block";
}
function closeDetail() { document.getElementById("detail").style.display = "none"; }

simulation.on("tick", () => {
  link.attr("x1", d => d.source.x).attr("y1", d => d.source.y)
      .attr("x2", d => d.target.x).attr("y2", d => d.target.y);
  linkLabel
    .attr("x", d => (d.source.x + d.target.x) / 2)
    .attr("y", d => (d.source.y + d.target.y) / 2);
  node.attr("cx", d => d.x).attr("cy", d => d.y);
  label.attr("x", d => d.x).attr("y", d => d.y);
});

window.addEventListener("resize", () => {
  simulation.force("center", d3.forceCenter(window.innerWidth / 2, window.innerHeight / 2));
  simulation.alpha(0.1).restart();
});
</script>
</body>
</html>"""


def main():
    parser = argparse.ArgumentParser(description="Visualize memory graph as interactive HTML")
    parser.add_argument(
        "--input",
        default=str(REPO_ROOT / "agent-persona" / "data" / "knowledge" / "memory_graph.json"),
        help="Path to memory_graph.json",
    )
    parser.add_argument(
        "--output",
        default=str(REPO_ROOT / "agent-persona" / "data" / "knowledge" / "memory_graph.html"),
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
