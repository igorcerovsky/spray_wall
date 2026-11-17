const SVG_NS = "http://www.w3.org/2000/svg";

const state = {
  wall: { widthCm: 360, mainWallHeightCm: 320, kickboardHeightCm: 40, totalHeightCm: 360 },
  availableGrades: [],
  holdsById: new Map(),
  holds: [],
  boulders: [],
  selectedBoulderId: null,
  statusFilter: "all",
  searchQuery: "",
  minGradeIndex: 0,
  maxGradeIndex: 0,
  showAllHolds: false,
  zoom: 1,
  panX: 0,
  panY: 0,
};

const els = {
  appShell: document.getElementById("app"),
  searchInput: document.getElementById("search-input"),
  minGrade: document.getElementById("min-grade"),
  maxGrade: document.getElementById("max-grade"),
  boulderList: document.getElementById("boulder-list"),
  backBtn: document.getElementById("back-btn"),
  activeMeta: document.getElementById("active-boulder-meta"),
  showAllHolds: document.getElementById("show-all-holds"),
  zoomOutBtn: document.getElementById("zoom-out-btn"),
  zoomResetBtn: document.getElementById("zoom-reset-btn"),
  zoomInBtn: document.getElementById("zoom-in-btn"),
  wallViewport: document.getElementById("wall-viewport"),
  wallStage: document.getElementById("wall-stage"),
  holdsOverlay: document.getElementById("holds-overlay"),
};

async function init() {
  try {
    const response = await fetch("./data/boulders.json", { cache: "no-cache" });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const data = await response.json();

    state.wall = data.wall || state.wall;
    state.availableGrades = Array.isArray(data.availableGrades) ? data.availableGrades : [];
    state.holds = Array.isArray(data.holds) ? data.holds : [];
    state.holdsById = new Map(state.holds.map((h) => [h.id, h]));
    state.boulders = Array.isArray(data.boulders) ? data.boulders : [];

    setupGradeFilters();
    bindEvents();

    // Pre-select the first established boulder, or the first available boulder
    const initial =
      state.boulders.find((b) => b.status === "established") || state.boulders[0] || null;
    if (initial) {
      state.selectedBoulderId = initial.id;
    }

    renderBoulderList();
    renderSelectedBoulder();
  } catch (err) {
    els.boulderList.replaceChildren(
      createEmptyState(`Could not load boulders: ${err.message}`)
    );
  }
}

function setupGradeFilters() {
  const grades = state.availableGrades;
  state.minGradeIndex = 0;
  state.maxGradeIndex = Math.max(0, grades.length - 1);

  els.minGrade.replaceChildren();
  els.maxGrade.replaceChildren();

  grades.forEach((grade, idx) => {
    const optMin = document.createElement("option");
    optMin.value = String(idx);
    optMin.textContent = grade;
    els.minGrade.appendChild(optMin);

    const optMax = document.createElement("option");
    optMax.value = String(idx);
    optMax.textContent = grade;
    els.maxGrade.appendChild(optMax);
  });

  els.minGrade.value = String(state.minGradeIndex);
  els.maxGrade.value = String(state.maxGradeIndex);
}

function bindEvents() {
  els.searchInput.addEventListener("input", (e) => {
    state.searchQuery = e.target.value.trim().toLowerCase();
    renderBoulderList();
  });

  document.querySelectorAll(".seg-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".seg-btn").forEach((b) => b.classList.remove("is-active"));
      btn.classList.add("is-active");
      state.statusFilter = btn.dataset.status || "all";
      renderBoulderList();
    });
  });

  els.minGrade.addEventListener("change", () => {
    const val = Number(els.minGrade.value);
    state.minGradeIndex = val;
    if (state.maxGradeIndex < val) {
      state.maxGradeIndex = val;
      els.maxGrade.value = String(val);
    }
    renderBoulderList();
  });

  els.maxGrade.addEventListener("change", () => {
    const val = Number(els.maxGrade.value);
    state.maxGradeIndex = val;
    if (state.minGradeIndex > val) {
      state.minGradeIndex = val;
      els.minGrade.value = String(val);
    }
    renderBoulderList();
  });

  els.showAllHolds.addEventListener("change", () => {
    state.showAllHolds = els.showAllHolds.checked;
    renderHoldsOverlay();
  });

  els.backBtn.addEventListener("click", () => {
    els.appShell.classList.remove("is-viewing-boulder");
  });

  els.zoomInBtn.addEventListener("click", () => setZoom(state.zoom * 1.35));
  els.zoomOutBtn.addEventListener("click", () => setZoom(state.zoom / 1.35));
  els.zoomResetBtn.addEventListener("click", resetZoom);

  setupPanAndZoomGestures();
}

function getFilteredBoulders() {
  return state.boulders.filter((b) => {
    if (state.statusFilter === "established" && b.status !== "established") {
      return false;
    }

    if (state.searchQuery) {
      const haystack = `${b.name} ${b.setter} ${b.grade} ${b.tags}`.toLowerCase();
      if (!haystack.includes(state.searchQuery)) {
        return false;
      }
    }

    if (b.grade) {
      const idx = state.availableGrades.indexOf(b.grade);
      if (idx !== -1 && (idx < state.minGradeIndex || idx > state.maxGradeIndex)) {
        return false;
      }
    }

    return true;
  });
}

function renderBoulderList() {
  const filtered = getFilteredBoulders();
  if (filtered.length === 0) {
    els.boulderList.replaceChildren(createEmptyState("No boulders match your filters."));
    return;
  }

  const fragment = document.createDocumentFragment();

  for (const boulder of filtered) {
    const card = document.createElement("button");
    card.type = "button";
    card.className = "boulder-card";
    card.setAttribute("role", "listitem");
    if (boulder.id === state.selectedBoulderId) {
      card.classList.add("is-selected");
    }

    const top = document.createElement("div");
    top.className = "card-top";

    const title = document.createElement("span");
    title.className = "card-title";
    title.textContent = boulder.name;

    const gradePill = document.createElement("span");
    gradePill.className = "grade-pill";
    gradePill.textContent = boulder.grade || "—";

    top.append(title, gradePill);

    const meta = document.createElement("div");
    meta.className = "card-meta";

    if (boulder.setter) {
      const setter = document.createElement("span");
      setter.textContent = `by ${boulder.setter}`;
      meta.appendChild(setter);
    }

    if (boulder.rating > 0) {
      const stars = document.createElement("span");
      stars.className = "stars";
      const clamped = Math.max(0, Math.min(5, boulder.rating));
      stars.textContent = "★".repeat(clamped) + "☆".repeat(5 - clamped);
      meta.appendChild(stars);
    }

    if (boulder.status === "draft") {
      const badge = document.createElement("span");
      badge.className = "draft-badge";
      badge.textContent = "Draft";
      meta.appendChild(badge);
    }

    const counts = document.createElement("div");
    counts.className = "card-counts";
    const roleCounts = [
      ["dot-start", boulder.startHoldIDs.length, "start"],
      ["dot-hold", boulder.holdIDs.length, "hold"],
      ["dot-foot", boulder.footholdIDs.length, "foot"],
      ["dot-top", boulder.topHoldIDs.length, "top"],
    ];
    for (const [cls, count, label] of roleCounts) {
      if (count > 0) {
        const span = document.createElement("span");
        span.className = `dot-count ${cls}`;
        span.textContent = `${count} ${label}`;
        counts.appendChild(span);
      }
    }

    card.append(top, meta, counts);
    card.addEventListener("click", () => {
      state.selectedBoulderId = boulder.id;
      resetZoom();
      renderBoulderList();
      renderSelectedBoulder();
      els.appShell.classList.add("is-viewing-boulder");
    });

    fragment.appendChild(card);
  }

  els.boulderList.replaceChildren(fragment);
}

function renderSelectedBoulder() {
  const boulder = state.boulders.find((b) => b.id === state.selectedBoulderId) || null;
  els.activeMeta.replaceChildren();

  if (!boulder) {
    const nameEl = document.createElement("span");
    nameEl.className = "meta-name";
    nameEl.textContent = "Select a boulder";
    els.activeMeta.appendChild(nameEl);
    renderHoldsOverlay();
    return;
  }

  const nameEl = document.createElement("span");
  nameEl.className = "meta-name";
  nameEl.textContent = boulder.name;
  els.activeMeta.appendChild(nameEl);

  if (boulder.grade) {
    const gradeEl = document.createElement("span");
    gradeEl.className = "meta-grade";
    gradeEl.textContent = boulder.grade;
    els.activeMeta.appendChild(gradeEl);
  }

  if (boulder.setter) {
    const setterEl = document.createElement("span");
    setterEl.className = "meta-setter";
    setterEl.textContent = `by ${boulder.setter}`;
    els.activeMeta.appendChild(setterEl);
  }

  if (boulder.rating > 0) {
    const starsEl = document.createElement("span");
    starsEl.className = "stars";
    const clamped = Math.max(0, Math.min(5, boulder.rating));
    starsEl.textContent = "★".repeat(clamped);
    els.activeMeta.appendChild(starsEl);
  }

  renderHoldsOverlay();
}

function getHoldRole(boulder, holdId) {
  if (!boulder) return null;
  if (boulder.startHoldIDs.includes(holdId)) return "start";
  if (boulder.topHoldIDs.includes(holdId)) return "top";
  if (boulder.holdIDs.includes(holdId)) return "hold";
  if (boulder.footholdIDs.includes(holdId)) return "foothold";
  return null;
}

function renderHoldsOverlay() {
  const boulder = state.boulders.find((b) => b.id === state.selectedBoulderId) || null;
  const totalH = state.wall.totalHeightCm || 360;
  const fragment = document.createDocumentFragment();

  const roleStyles = {
    start: { stroke: "#22c55e", fill: "rgba(34, 197, 94, 0.25)", width: 2.2 },
    top: { stroke: "#ef4444", fill: "rgba(239, 68, 68, 0.25)", width: 2.2 },
    hold: { stroke: "#3b82f6", fill: "rgba(59, 130, 246, 0.25)", width: 2.2 },
    foothold: { stroke: "#eab308", fill: "rgba(234, 179, 8, 0.25)", width: 2.2 },
    none: { stroke: "rgba(255, 255, 255, 0.45)", fill: "rgba(255, 255, 255, 0.06)", width: 1.2 },
  };

  // Draw unselected holds first (if enabled), then selected holds on top
  const orderedHolds = [...state.holds].sort((a, b) => {
    const ra = getHoldRole(boulder, a.id) ? 1 : 0;
    const rb = getHoldRole(boulder, b.id) ? 1 : 0;
    return ra - rb;
  });

  for (const hold of orderedHolds) {
    const role = getHoldRole(boulder, hold.id);
    if (!role && !state.showAllHolds) {
      continue;
    }

    const style = roleStyles[role || "none"];
    const cx = hold.xCm;
    const cy = totalH - hold.yCm;
    const w = Math.max(4, hold.majorCm || 8);
    const h = Math.max(4, hold.minorCm || 8);
    const rot = -(hold.rotationDeg || 0);

    let shape;
    if (role === "start" || role === "top") {
      shape = document.createElementNS(SVG_NS, "rect");
      const rx = Math.max(1.2, Math.min(w, h) * 0.15);
      shape.setAttribute("x", String(cx - w / 2));
      shape.setAttribute("y", String(cy - h / 2));
      shape.setAttribute("width", String(w));
      shape.setAttribute("height", String(h));
      shape.setAttribute("rx", String(rx));
      shape.setAttribute("ry", String(rx));
    } else if (role === "foothold") {
      shape = document.createElementNS(SVG_NS, "polygon");
      const pts = [
        `${cx},${cy - h / 2}`,
        `${cx + w / 2},${cy}`,
        `${cx},${cy + h / 2}`,
        `${cx - w / 2},${cy}`,
      ].join(" ");
      shape.setAttribute("points", pts);
    } else {
      shape = document.createElementNS(SVG_NS, "ellipse");
      shape.setAttribute("cx", String(cx));
      shape.setAttribute("cy", String(cy));
      shape.setAttribute("rx", String(w / 2));
      shape.setAttribute("ry", String(h / 2));
    }

    shape.setAttribute("fill", style.fill);
    shape.setAttribute("stroke", style.stroke);
    shape.setAttribute("stroke-width", String(style.width));
    shape.setAttribute("vector-effect", "non-scaling-stroke");
    if (rot !== 0) {
      shape.setAttribute("transform", `rotate(${rot} ${cx} ${cy})`);
    }

    fragment.appendChild(shape);
  }

  els.holdsOverlay.replaceChildren(fragment);
}

// MARK: - Pan & Pinch-to-Zoom

function setZoom(nextZoom, focalClientX = null, focalClientY = null) {
  const clamped = Math.max(1, Math.min(6, nextZoom));
  if (clamped === 1) {
    state.zoom = 1;
    state.panX = 0;
    state.panY = 0;
  } else {
    if (focalClientX !== null && focalClientY !== null) {
      const rect = els.wallViewport.getBoundingClientRect();
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      const dx = focalClientX - centerX;
      const dy = focalClientY - centerY;
      const ratio = clamped / state.zoom;
      state.panX = dx - (dx - state.panX) * ratio;
      state.panY = dy - (dy - state.panY) * ratio;
    }
    state.zoom = clamped;
    clampPan();
  }
  applyStageTransform();
}

function resetZoom() {
  state.zoom = 1;
  state.panX = 0;
  state.panY = 0;
  applyStageTransform();
}

function clampPan() {
  const stageRect = els.wallStage.getBoundingClientRect();
  const baseW = stageRect.width / state.zoom;
  const baseH = stageRect.height / state.zoom;
  const maxPanX = Math.max(0, (baseW * state.zoom - baseW * 0.4) / 2);
  const maxPanY = Math.max(0, (baseH * state.zoom - baseH * 0.4) / 2);
  state.panX = Math.max(-maxPanX, Math.min(maxPanX, state.panX));
  state.panY = Math.max(-maxPanY, Math.min(maxPanY, state.panY));
}

function applyStageTransform() {
  els.wallStage.style.transform = `translate3d(${state.panX}px, ${state.panY}px, 0) scale(${state.zoom})`;
  els.zoomResetBtn.textContent = `${Math.round(state.zoom * 100)}%`;
}

function setupPanAndZoomGestures() {
  const activePointers = new Map();
  let lastPinchDist = null;
  let lastTapTime = 0;

  els.wallViewport.addEventListener("pointerdown", (e) => {
    activePointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    els.wallViewport.setPointerCapture(e.pointerId);
    els.wallViewport.classList.add("is-dragging");

    if (activePointers.size === 2) {
      const pts = [...activePointers.values()];
      lastPinchDist = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
    } else if (activePointers.size === 1) {
      const now = Date.now();
      if (now - lastTapTime < 280) {
        if (state.zoom > 1.05) {
          resetZoom();
        } else {
          setZoom(2.2, e.clientX, e.clientY);
        }
        lastTapTime = 0;
      } else {
        lastTapTime = now;
      }
    }
  });

  els.wallViewport.addEventListener("pointermove", (e) => {
    if (!activePointers.has(e.pointerId)) return;
    const prev = activePointers.get(e.pointerId);
    activePointers.set(e.pointerId, { x: e.clientX, y: e.clientY });

    if (activePointers.size === 2) {
      const pts = [...activePointers.values()];
      const dist = Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
      const midX = (pts[0].x + pts[1].x) / 2;
      const midY = (pts[0].y + pts[1].y) / 2;
      if (lastPinchDist && lastPinchDist > 0) {
        setZoom(state.zoom * (dist / lastPinchDist), midX, midY);
      }
      lastPinchDist = dist;
    } else if (activePointers.size === 1 && state.zoom > 1) {
      state.panX += e.clientX - prev.x;
      state.panY += e.clientY - prev.y;
      clampPan();
      applyStageTransform();
    }
  });

  const endPointer = (e) => {
    activePointers.delete(e.pointerId);
    if (activePointers.size < 2) {
      lastPinchDist = null;
    }
    if (activePointers.size === 0) {
      els.wallViewport.classList.remove("is-dragging");
    }
  };

  els.wallViewport.addEventListener("pointerup", endPointer);
  els.wallViewport.addEventListener("pointercancel", endPointer);

  els.wallViewport.addEventListener(
    "wheel",
    (e) => {
      e.preventDefault();
      const factor = e.deltaY < 0 ? 1.12 : 1 / 1.12;
      setZoom(state.zoom * factor, e.clientX, e.clientY);
    },
    { passive: false }
  );
}

function createEmptyState(text) {
  const div = document.createElement("div");
  div.className = "empty-state";
  div.textContent = text;
  return div;
}

init();
