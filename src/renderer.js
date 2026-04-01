// --- Initial Data --------------------------------------------------

const defaultAgents = [
  "Brimstone", "Phoenix", "Sage", "Sova",
  "Jett", "Reyna", "Omen", "Killjoy",
  "Cypher", "Raze", "Viper", "Yoru",
  "Skye", "Astra", "KAY/O", "Chamber",
  "Neon", "Fade", "Harbor", "Gekko",
  "Deadlock", "Iso", "Clove", "Vyse",
  "Tejo", "Waylay", "Veto", "Breach",
];

const defaultWeapons = [
  "Classic", "Shorty", "Frenzy", "Ghost", "Sheriff", "Bandit",
  "Stinger", "Spectre", "Bucky", "Judge",
  "Bulldog", "Guardian", "Phantom", "Vandal",
  "Marshal", "Operator", "Ares", "Odin"
];

const STORAGE_KEY = "valo_nuzlocke_state_v1";

let state = {
  agents: [],
  wins: 0,
  losses: 0,
  tokens: 0,
  weapons: defaultWeapons,
  ecoBans: [],
  weaponBans: [],
  history: [],
  notes: ""
};

let lastState = null; // For Undo function

// --- Helpers -------------------------------------------------------
function initState() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      state = JSON.parse(saved);
      // Data Cleanup: Fix persistent "Waylay:" typo in saved data
      state.agents.forEach(a => {
        if (a.name === "Waylay:") a.name = "Waylay";
      });
      return;
    }
  } catch (err) {
    console.error("Failed to load state:", err);
    alert("Saved data is corrupted. Starting new run.");
  }

  // FIRST TIME EVER → create fully randomized order
  let shuffled = shuffle([...defaultAgents]);  // Fisher-Yates shuffle

  state = {
    agents: shuffled.map((name, idx) => ({
      id: idx,
      name,
      unlocked: idx === 0,   // still unlock first one
      lives: idx === 0 ? 2 : 0,
      dead: false
    })),
    wins: 0,
    losses: 0,
    tokens: 0,
    weapons: defaultWeapons,
    ecoBans: [],
    weaponBans: [],
    history: []
  };

  saveState();
}
function shuffle(array) {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}

function render() {
  renderStats();
  renderAgents();
  renderBans();
  renderHistory();
  renderSelectors();

  // Sync scratchpad
  const scratchpad = document.getElementById("scratchpad");
  if (scratchpad) scratchpad.value = state.notes || "";
}

function renderStats() {
  document.getElementById("winsCount").textContent = state.wins;
  document.getElementById("lossesCount").textContent = state.losses;
  document.getElementById("tokensCount").textContent = state.tokens;

  const alive = state.agents.filter(a => a.unlocked && !a.dead && a.lives > 0).length;
  document.getElementById("aliveAgentsCount").textContent = alive;
}

function renderAgents() {
  const tbody = document.getElementById("agentsTableBody");
  tbody.innerHTML = "";

  state.agents.forEach(agent => {
    if (!agent.unlocked && agent.lives === 0) {
      // Hide fully locked (future) agents from table to reduce noise
      return;
    }

    const tr = document.createElement("tr");

    // Name
    const tdName = document.createElement("td");
    tdName.textContent = agent.name + (agent.unlocked ? "" : " (locked)");
    tr.appendChild(tdName);

    // Lives
    const tdLives = document.createElement("td");
    let hearts = "";
    if (agent.unlocked) {
      for (let i = 0; i < agent.lives; i++) hearts += "❤️";
      for (let i = agent.lives; i < 2; i++) hearts += "🤍";
    } else {
      hearts = "—";
    }
    const spanLives = document.createElement("span");
    spanLives.className = "lives";
    spanLives.textContent = hearts;
    tdLives.appendChild(spanLives);
    tr.appendChild(tdLives);

    // Status
    const tdStatus = document.createElement("td");
    const spanStatus = document.createElement("span");
    spanStatus.className = "badge";
    if (!agent.unlocked) {
      spanStatus.textContent = "Locked";
    } else if (agent.dead || agent.lives <= 0) {
      spanStatus.textContent = "Dead";
      spanStatus.classList.add("dead");
    } else {
      spanStatus.textContent = "Alive";
      spanStatus.classList.add("alive");
    }
    tdStatus.appendChild(spanStatus);
    tr.appendChild(tdStatus);

    // Action (save with token)
    const tdAction = document.createElement("td");
    if ((agent.dead || agent.lives <= 0) && state.tokens > 0 && agent.unlocked) {
      const btn = document.createElement("button");
      btn.className = "small";
      btn.textContent = "Save with Token";
      btn.addEventListener("click", () => {
        if (state.tokens <= 0) return;
        state.tokens -= 1;
        agent.lives = 1;
        agent.dead = false;
        addHistoryEntry(`Saved ${agent.name} with a token (revived to 1 life).`);
        saveState();
        render();
      });
      tdAction.appendChild(btn);
    } else {
      tdAction.innerHTML = "<span class='muted'>—</span>";
    }

    tr.appendChild(tdAction);
    tbody.appendChild(tr);
  });
}

function renderBans() {
  const ecoContainer = document.getElementById("ecoBansContainer");
  const weaponContainer = document.getElementById("weaponBansContainer");

  ecoContainer.innerHTML = "";
  weaponContainer.innerHTML = "";

  if (state.ecoBans.length === 0) {
    ecoContainer.innerHTML = "<p class='muted'>No eco weapons banned yet.</p>";
  } else {
    const div = document.createElement("div");
    div.className = "chips";
    state.ecoBans.forEach(w => {
      const chip = document.createElement("span");
      chip.className = "chip banned";
      chip.textContent = w;
      div.appendChild(chip);
    });
    ecoContainer.appendChild(div);
  }

  if (state.weaponBans.length === 0) {
    weaponContainer.innerHTML = "<p class='muted'>No weapons banned from bot frags yet.</p>";
  } else {
    const div = document.createElement("div");
    div.className = "chips";
    state.weaponBans.forEach(w => {
      const chip = document.createElement("span");
      chip.className = "chip banned";
      chip.textContent = w;
      div.appendChild(chip);
    });
    weaponContainer.appendChild(div);
  }
}

function renderHistory() {
  const historyDiv = document.getElementById("historyList");
  historyDiv.innerHTML = "";

  if (state.history.length === 0) {
    historyDiv.innerHTML = "<p class='muted'>No matches logged yet.</p>";
    return;
  }

  // Show latest first
  const recent = [...state.history].slice(-30).reverse();
  recent.forEach(entry => {
    const div = document.createElement("div");
    div.className = "history-item";
    div.innerHTML = `
      <div>${entry.summary}</div>
      <div class="muted">${entry.time}</div>
    `;
    historyDiv.appendChild(div);
  });
}

function renderSelectors() {
  const agentSelect = document.getElementById("agentSelect");
  const ecoWeaponSelect = document.getElementById("ecoWeaponSelect");

  agentSelect.innerHTML = "";
  const playableAgents = state.agents.filter(a => a.unlocked && !a.dead && a.lives > 0);
  if (playableAgents.length === 0) {
    const opt = document.createElement("option");
    opt.value = "";
    opt.textContent = "No living agents (run is over)";
    agentSelect.appendChild(opt);
    agentSelect.disabled = true;
  } else {
    playableAgents.forEach(agent => {
      const opt = document.createElement("option");
      opt.value = agent.id;
      opt.textContent = agent.name;
      agentSelect.appendChild(opt);
    });
    agentSelect.disabled = false;
  }

  ecoWeaponSelect.innerHTML = "";
  state.weapons.forEach(w => {
    const opt = document.createElement("option");
    opt.value = w;
    opt.textContent = w;
    ecoWeaponSelect.appendChild(opt);
  });
}

function addHistoryEntry(text) {
  const now = new Date();
  const timeStr = now.toLocaleString();
  state.history.push({
    summary: text,
    time: timeStr
  });
}

function unlockNextAgent() {
  // Pick a random locked agent to unlock (instead of the first)
  const locked = state.agents.filter(a => !a.unlocked);
  if (!locked || locked.length === 0) return;
  const idx = Math.floor(Math.random() * locked.length);
  const next = locked[idx];
  next.unlocked = true;
  next.lives = 2;
  next.dead = false;
  addHistoryEntry(`Unlocked new agent: ${next.name} (2 lives).`);
}

function banRandomWeaponFromBotFrag() {
  const candidates = state.weapons.filter(w => !state.weaponBans.includes(w));
  if (candidates.length === 0) {
    addHistoryEntry("Bot frag occurred but all weapons are already banned.");
    return;
  }
  const idx = Math.floor(Math.random() * candidates.length);
  const chosen = candidates[idx];
  state.weaponBans.push(chosen);
  addHistoryEntry(`Bot frag: ${chosen} has been banned for this session.`);
}

function saveState(isMajorChange = false) {
  try {
    if (isMajorChange) {
      lastState = JSON.stringify(state);
    }
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch (err) {
    console.error("Failed to save state:", err);
    alert("Storage full or inaccessible. Progress might not be saved.");
  }
}

function undoLastMatch() {
  if (!lastState) {
    alert("Nothing to undo!");
    return;
  }
  if (!confirm("Undo last match? This will revert your state to before the last submission.")) {
    return;
  }
  state = JSON.parse(lastState);
  lastState = null;
  addHistoryEntry("Action: Undid last match.");
  saveState();
  render();
  alert("Last match reverted.");
}

function exportData() {
  try {
    const dataStr = JSON.stringify(state, null, 2);
    const blob = new Blob([dataStr], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `nuztrack_backup_${new Date().toISOString().split('T')[0]}.json`;
    a.click();
    URL.revokeObjectURL(url);
    addHistoryEntry("Action: Exported run data.");
  } catch (err) {
    console.error("Export failed:", err);
    alert("Failed to export data.");
  }
}

function importData(e) {
  const file = e.target.files[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = (event) => {
    try {
      const imported = JSON.parse(event.target.result);
      // Basic validation
      if (!imported.agents || !Array.isArray(imported.agents)) {
        throw new Error("Invalid save format: missing agents array.");
      }
      
      if (!confirm("Importing data will OVERWRITE your current run. Continue?")) {
        return;
      }

      state = imported;
      saveState(true); // Save for undo just in case
      render();
      addHistoryEntry("Action: Imported run data from file.");
      alert("Import successful!");
    } catch (err) {
      console.error("Import failed:", err);
      alert("Failed to import: " + err.message);
    }
    // Reset input
    e.target.value = "";
  };
  reader.readAsText(file);
}

// --- Event Handlers -----------------------------------------------

document.getElementById("matchForm").addEventListener("submit", (e) => {
  e.preventDefault();
  const agentSelect = document.getElementById("agentSelect");
  const result = document.getElementById("resultSelect").value;
  const aces = parseInt(document.getElementById("acesInput").value || "0", 10);
  const botFrag = document.getElementById("botFragSelect").value === "yes";
  const ecoRound = document.getElementById("ecoRoundCheck").checked;
  const ecoWeapon = document.getElementById("ecoWeaponSelect").value;
  const ecoKills = parseInt(document.getElementById("ecoKillsInput").value || "0", 10);
  const friendshipKept = document.getElementById("friendshipCheck").checked;

  if (agentSelect.disabled || !agentSelect.value) {
    alert("No living agents left. Reset the run to start again.");
    return;
  }

  const agentId = parseInt(agentSelect.value, 10);
  const agent = state.agents.find(a => a.id === agentId);
  if (!agent) return;

  // Update result
  if (result === "win") {
    state.wins += 1;
    unlockNextAgent();
  } else {
    state.losses += 1;
    if (agent.unlocked && !agent.dead && agent.lives > 0) {
      agent.lives -= 1;
      if (agent.lives <= 0) {
        agent.lives = 0;
        agent.dead = true;
        addHistoryEntry(`${agent.name} has fallen (0 lives).`);
      }
    }
  }

  // Tokens from aces
  if (aces > 0) {
    state.tokens += aces;
    addHistoryEntry(`Earned ${aces} token(s) from aces this match.`);
  }

  // Bot frag rule
  if (botFrag) {
    banRandomWeaponFromBotFrag();
  }

  // Eco rule
  if (ecoRound && ecoWeapon) {
    if (ecoKills === 0 && !state.ecoBans.includes(ecoWeapon)) {
      state.ecoBans.push(ecoWeapon);
      addHistoryEntry(`Eco Rule: Banned ${ecoWeapon} for this session (died with 0 kills).`);
    } else {
      addHistoryEntry(`Eco round logged with ${ecoKills} kill(s) on ${ecoWeapon}. No ban triggered.`);
    }
  }

  // Friendship rule – just log if broken, you can decide how harsh to be
  if (!friendshipKept) {
    addHistoryEntry(`Friendship Rule broken: you did NOT equip an accessory for ${agent.name}. (Apply any penalty you want.)`);
  }

  // Summary for this match
  const summaryParts = [];
  summaryParts.push(`${result.toUpperCase()} as ${agent.name}`);
  if (aces > 0) summaryParts.push(`${aces} ace(s)`);
  if (botFrag) summaryParts.push("Bot frag ➜ random weapon banned");
  if (ecoRound) {
    summaryParts.push(`Eco: ${ecoWeapon} (${ecoKills} kill(s))`);
  }
  if (!friendshipKept) summaryParts.push("Friendship broken");

  addHistoryEntry(summaryParts.join(" · "));

  saveState(true); // Save state for Undo before rendering
  render();

  // Reset per-match controls (but keep last selections for convenience)
  document.getElementById("acesInput").value = "0";
  document.getElementById("botFragSelect").value = "no";
  document.getElementById("ecoRoundCheck").checked = false;
  document.getElementById("ecoDetails").classList.add("hidden");
  document.getElementById("ecoKillsInput").value = "0";
  document.getElementById("friendshipCheck").checked = false;
});

document.getElementById("ecoRoundCheck").addEventListener("change", (e) => {
  const details = document.getElementById("ecoDetails");
  if (e.target.checked) {
    details.classList.remove("hidden");
  } else {
    details.classList.add("hidden");
  }
});

document.getElementById("newSessionBtn").addEventListener("click", () => {
  if (!confirm("Start a new SESSION? This clears eco bans but keeps weapon bans, agents, lives & tokens.")) {
    return;
  }
  // Only clear eco bans for a new session — keep bot-frag weapon bans across sessions.
  state.ecoBans = [];
  addHistoryEntry("Started a new session: cleared eco bans.");
  saveState();
  render();
});

document.getElementById("resetRunBtn").addEventListener("click", () => {
  if (!confirm("Reset FULL RUN? This wipes EVERYTHING (agents, lives, tokens, bans, history).")) {
    return;
  }
  localStorage.removeItem(STORAGE_KEY);
  state = {
    agents: [],
    wins: 0,
    losses: 0,
    tokens: 0,
    weapons: defaultWeapons,
    ecoBans: [],
    weaponBans: [],
    history: [],
    notes: ""
  };
  initState();
  addHistoryEntry("Full run reset. Back to day one.");
  saveState();
  render();
});

// --- Edit Mode (toggle + save) ------------------------------------
const editPanel = document.getElementById("editPanel");
const toggleEditBtn = document.getElementById("toggleEditBtn");
const editAgentsDiv = document.getElementById("editAgents");
const editTokensInput = document.getElementById("editTokens");
const editWinsInput = document.getElementById("editWins");
const editLossesInput = document.getElementById("editLosses");
const editWeaponBansDiv = document.getElementById("editWeaponBans");
const editEcoBansDiv = document.getElementById("editEcoBans");
const saveEditsBtn = document.getElementById("saveEditsBtn");

function renderEditPanel() {
  // Agents
  editAgentsDiv.innerHTML = "";
  state.agents.forEach((a, idx) => {
    const row = document.createElement("div");
    row.style.display = "flex";
    row.style.gap = "0.5rem";
    row.style.alignItems = "center";
    row.style.marginBottom = "0.35rem";

    const chk = document.createElement("input");
    chk.type = "checkbox";
    chk.checked = !!a.unlocked;
    chk.dataset.idx = idx;

    const label = document.createElement("label");
    label.textContent = a.name;
    label.style.flex = "1";

    const lives = document.createElement("input");
    lives.type = "number";
    lives.min = "0";
    lives.max = "2";
    lives.value = a.lives || 0;
    lives.style.width = "64px";
    lives.dataset.idx = idx;

    row.appendChild(chk);
    row.appendChild(label);
    row.appendChild(lives);
    editAgentsDiv.appendChild(row);
  });

  // Tokens / wins / losses
  editTokensInput.value = state.tokens;
  editWinsInput.value = state.wins;
  editLossesInput.value = state.losses;

  // Weapon bans
  editWeaponBansDiv.innerHTML = "";
  state.weapons.forEach(w => {
    const row = document.createElement("div");
    row.style.display = "flex";
    row.style.alignItems = "center";
    row.style.gap = "0.5rem";
    row.style.marginBottom = "0.25rem";

    const chk = document.createElement("input");
    chk.type = "checkbox";
    chk.checked = state.weaponBans.includes(w);
    chk.value = w;

    const lbl = document.createElement("label");
    lbl.textContent = w;

    row.appendChild(chk);
    row.appendChild(lbl);
    editWeaponBansDiv.appendChild(row);
  });

  // Eco bans
  editEcoBansDiv.innerHTML = "";
  state.weapons.forEach(w => {
    const row = document.createElement("div");
    row.style.display = "flex";
    row.style.alignItems = "center";
    row.style.gap = "0.5rem";
    row.style.marginBottom = "0.25rem";

    const chk = document.createElement("input");
    chk.type = "checkbox";
    chk.checked = state.ecoBans.includes(w);
    chk.value = w;

    const lbl = document.createElement("label");
    lbl.textContent = w;

    row.appendChild(chk);
    row.appendChild(lbl);
    editEcoBansDiv.appendChild(row);
  });
}

toggleEditBtn.addEventListener("click", () => {
  const open = editPanel.classList.toggle("hidden");
  if (!open) {
    // panel now shown -> populate
    renderEditPanel();
    toggleEditBtn.textContent = "Close Edit";
  } else {
    toggleEditBtn.textContent = "Edit Mode";
  }
});

saveEditsBtn.addEventListener("click", () => {
  // Agents
  const agentChkList = editAgentsDiv.querySelectorAll("input[type='checkbox'][data-idx]");
  const agentLivesList = editAgentsDiv.querySelectorAll("input[type='number'][data-idx]");
  agentChkList.forEach(chk => {
    const idx = parseInt(chk.dataset.idx, 10);
    const livesInput = Array.from(agentLivesList).find(i => parseInt(i.dataset.idx, 10) === idx);
    const lives = Math.max(0, Math.min(2, parseInt(livesInput.value || "0", 10)));
    state.agents[idx].unlocked = chk.checked;
    state.agents[idx].lives = lives;
    state.agents[idx].dead = lives <= 0;
  });

  // Tokens / wins / losses
  state.tokens = Math.max(0, parseInt(editTokensInput.value || "0", 10));
  state.wins = Math.max(0, parseInt(editWinsInput.value || "0", 10));
  state.losses = Math.max(0, parseInt(editLossesInput.value || "0", 10));

  // Weapon bans
  const weaponChecks = editWeaponBansDiv.querySelectorAll("input[type='checkbox']");
  state.weaponBans = Array.from(weaponChecks).filter(c => c.checked).map(c => c.value);

  // Eco bans
  const ecoChecks = editEcoBansDiv.querySelectorAll("input[type='checkbox']");
  state.ecoBans = Array.from(ecoChecks).filter(c => c.checked).map(c => c.value);

  addHistoryEntry("Admin: Saved edits to run state.");
  saveState();
  render();
  alert("Edits saved.");
});

// Dynamic Agent Addition
document.getElementById("addAgentBtn").addEventListener("click", () => {
  const nameInput = document.getElementById("newAgentName");
  const name = nameInput.value.trim();
  if (!name) return;

  if (state.agents.find(a => a.name.toLowerCase() === name.toLowerCase())) {
    alert("Agent already exists.");
    return;
  }

  const newId = state.agents.length > 0 ? Math.max(...state.agents.map(a => a.id)) + 1 : 0;
  state.agents.push({
    id: newId,
    name,
    unlocked: false,
    lives: 0,
    dead: false
  });

  addHistoryEntry(`Admin: Added new agent to pool: ${name}`);
  saveState();
  renderEditPanel();
  renderSelectors();
  nameInput.value = "";
  alert(`Added ${name} to the pool.`);
});

// Dynamic Weapon Addition
document.getElementById("addWeaponBtn").addEventListener("click", () => {
  const nameInput = document.getElementById("newWeaponName");
  const name = nameInput.value.trim();
  if (!name) return;

  if (state.weapons.find(w => w.toLowerCase() === name.toLowerCase())) {
    alert("Weapon already exists.");
    return;
  }

  state.weapons.push(name);
  addHistoryEntry(`Admin: Added new weapon to pool: ${name}`);
  saveState();
  renderEditPanel();
  renderSelectors();
  nameInput.value = "";
  alert(`Added ${name} to the pool.`);
});

const sidebar = document.getElementById("themeSidebar");
const openThemeBtn = document.getElementById("openThemeBtn");
const accentPicker = document.getElementById("accentColorPicker");
const accentHex = document.getElementById("accentHexInput");
const cardPicker = document.getElementById("cardColorPicker");
const cardHex = document.getElementById("cardHexInput");
const bgPicker = document.getElementById("bgColorPicker");
const bgHex = document.getElementById("bgHexInput");
const resetColorsBtn = document.getElementById("resetColorsBtn");

const THEME_STORAGE = "valo_nuzlocke_theme_v1";
const DEFAULT_COLORS = { accent: "#f97316", card: "#0f172a", bg: "#050816" };
const root = document.documentElement;

function hexToHexAlpha(hex, alpha = 1) {
  // Accepts #rrggbb or #rgb
  let h = hex.replace("#", "");
  if (h.length === 3) {
    h = h.split("").map(c => c + c).join("");
  }
  const a = Math.round(alpha * 255).toString(16).padStart(2, "0");
  return `#${h}${a}`;
}

function applyTheme(theme) {
  if (!theme) return;
  root.style.setProperty("--accent", theme.accent);
  root.style.setProperty("--card", theme.card);
  root.style.setProperty("--bg", theme.bg);
  root.style.setProperty("--accent-soft", hexToHexAlpha(theme.accent, 0.1));
  // sync pickers
  if (accentPicker) accentPicker.value = theme.accent;
  if (accentHex) accentHex.value = theme.accent.toUpperCase();
  if (cardPicker) cardPicker.value = theme.card;
  if (cardHex) cardHex.value = theme.card.toUpperCase();
  if (bgPicker) bgPicker.value = theme.bg;
  if (bgHex) bgHex.value = theme.bg.toUpperCase();
}

function saveTheme(theme) {
  try {
    localStorage.setItem(THEME_STORAGE, JSON.stringify(theme));
  } catch (e) {
    console.error("Failed to save theme:", e);
  }
}

function loadTheme() {
  try {
    const saved = localStorage.getItem(THEME_STORAGE);
    if (saved) {
      const t = JSON.parse(saved);
      applyTheme(t);
      return;
    }
  } catch (e) {
    console.error("Failed to load theme:", e);
  }
  applyTheme(DEFAULT_COLORS);
}

// initialize pickers and listeners
if (openThemeBtn) {
  openThemeBtn.addEventListener("click", () => {
    sidebar.classList.toggle("show");
  });
}

document.addEventListener("click", (e) => {
  if (!sidebar.contains(e.target) && e.target !== openThemeBtn) {
    sidebar.classList.remove("show");
  }
});

const isValidHex = (hex) => /^#[0-9A-Fa-f]{6}$/.test(hex);

if (accentPicker) {
  accentPicker.addEventListener("input", (e) => {
    const v = e.target.value;
    root.style.setProperty("--accent", v);
    root.style.setProperty("--accent-soft", hexToHexAlpha(v, 0.1));
    if (accentHex) accentHex.value = v.toUpperCase();
    saveTheme({ accent: v, card: cardPicker.value, bg: bgPicker.value });
  });
}
if (accentHex) {
  accentHex.addEventListener("input", (e) => {
    let v = e.target.value.trim();
    if (!v.startsWith('#')) v = '#' + v;
    if (isValidHex(v)) {
      root.style.setProperty("--accent", v);
      root.style.setProperty("--accent-soft", hexToHexAlpha(v, 0.1));
      if (accentPicker) accentPicker.value = v;
      saveTheme({ accent: v, card: cardPicker.value, bg: bgPicker.value });
    }
  });
}

if (cardPicker) {
  cardPicker.addEventListener("input", (e) => {
    const v = e.target.value;
    root.style.setProperty("--card", v);
    if (cardHex) cardHex.value = v.toUpperCase();
    saveTheme({ accent: accentPicker.value, card: v, bg: bgPicker.value });
  });
}
if (cardHex) {
  cardHex.addEventListener("input", (e) => {
    let v = e.target.value.trim();
    if (!v.startsWith('#')) v = '#' + v;
    if (isValidHex(v)) {
      root.style.setProperty("--card", v);
      if (cardPicker) cardPicker.value = v;
      saveTheme({ accent: accentPicker.value, card: v, bg: bgPicker.value });
    }
  });
}

if (bgPicker) {
  bgPicker.addEventListener("input", (e) => {
    const v = e.target.value;
    root.style.setProperty("--bg", v);
    if (bgHex) bgHex.value = v.toUpperCase();
    saveTheme({ accent: accentPicker.value, card: cardPicker.value, bg: v });
  });
}
if (bgHex) {
  bgHex.addEventListener("input", (e) => {
    let v = e.target.value.trim();
    if (!v.startsWith('#')) v = '#' + v;
    if (isValidHex(v)) {
      root.style.setProperty("--bg", v);
      if (bgPicker) bgPicker.value = v;
      saveTheme({ accent: accentPicker.value, card: cardPicker.value, bg: v });
    }
  });
}

if (resetColorsBtn) {
  resetColorsBtn.addEventListener("click", () => {
    applyTheme(DEFAULT_COLORS);
    saveTheme(DEFAULT_COLORS);
  });
}

// Initialize Undo, Export, Import
const undoBtn = document.getElementById("undoBtn");
if (undoBtn) {
  undoBtn.addEventListener("click", undoLastMatch);
}

const exportBtn = document.getElementById("exportBtn");
if (exportBtn) {
  exportBtn.addEventListener("click", exportData);
}

const importBtn = document.getElementById("importBtn");
const importFile = document.getElementById("importFile");
if (importBtn && importFile) {
  importBtn.addEventListener("click", () => importFile.click());
  importFile.addEventListener("change", importData);
}

// Initialize Scratchpad auto-save
const scratchpad = document.getElementById("scratchpad");
if (scratchpad) {
  scratchpad.addEventListener("input", (e) => {
    state.notes = e.target.value;
    saveState();
  });
}

// load stored theme (or defaults) on boot
loadTheme();

// --- Boot ---------------------------------------------------------
initState();
render();
