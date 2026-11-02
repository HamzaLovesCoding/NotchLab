// The hero's working notch: the app's four pages, clipboard, and settings rebuilt in HTML.
// Everything is made-up demo data, and nothing a visitor types or drops leaves the browser.
(() => {
  const stage = document.querySelector('.notch-stage');
  if (!stage) return;
  const caption = document.querySelector('#preview-caption');

  // ---- Icons (24×24, stroked unless marked solid) ----
  const ICONS = {
    home: '<path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10v10h4.5v-6h4v6h4.5V10"/>',
    tray: '<path d="M3 13.5h5l1.5 2.5h5l1.5-2.5h5"/><path d="M6 5h12l3 8.5V19H3v-5.5z"/>',
    checklist: '<path d="m3 6 2 2 3.5-3.5"/><circle cx="5.5" cy="17" r="2.5"/><path d="M12 6.5h9M12 17h9"/>',
    terminal: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="m7 9 3 3-3 3M12.5 15h4.5"/>',
    camera: '<circle cx="12" cy="10" r="6.5"/><circle cx="12" cy="10" r="2"/><path d="M12 16.5V21M8 21h8"/>',
    clipboard: '<rect x="8" y="3" width="12" height="14" rx="2"/><path d="M5 7.5V19a2 2 0 0 0 2 2h9"/>',
    gear: '<circle cx="12" cy="12" r="6.5"/><circle cx="12" cy="12" r="2.3"/><path stroke-width="3" d="M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8"/>',
    prev: '<path d="M11.5 6 3.5 12l8 6zM20.5 6l-8 6 8 6z"/>',
    next: '<path d="M12.5 6l8 6-8 6zM3.5 6l8 6-8 6z"/>',
    play: '<path d="M7 4.5v15l12.5-7.5z"/>',
    pause: '<rect x="6" y="4.5" width="4" height="15" rx="1"/><rect x="14" y="4.5" width="4" height="15" rx="1"/>',
    laptop: '<rect x="4.5" y="5" width="15" height="10.5" rx="1.5"/><path d="M2 19h20"/>',
    headphones: '<path d="M4 15.5V12a8 8 0 0 1 16 0v3.5"/><rect x="3" y="14" width="4.5" height="6.5" rx="1.5"/><rect x="16.5" y="14" width="4.5" height="6.5" rx="1.5"/>',
    shield: '<path d="M12 3 4.5 6v6c0 4.4 3.2 7.7 7.5 9 4.3-1.3 7.5-4.6 7.5-9V6z"/><rect x="9" y="11" width="6" height="4.5" rx="1"/><path d="M10.2 11V9.6a1.8 1.8 0 0 1 3.6 0V11"/>',
    pencil: '<path d="M20 13.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h5.5"/><path d="m17 3 4 4-8.5 8.5H8.5v-4z"/>',
    chevron: '<path d="m9 6 6 6-6 6"/>',
    reset: '<path d="M4.5 12a7.5 7.5 0 1 0 2.2-5.3"/><path d="M4.5 4.5v4h4"/>',
    cpu: '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5" rx=".5"/><path d="M9.5 2.5V6M14.5 2.5V6M9.5 18v3.5M14.5 18v3.5M2.5 9.5H6M2.5 14.5H6M18 9.5h3.5M18 14.5h3.5"/>',
    memory: '<rect x="3" y="7" width="18" height="10" rx="2"/><path d="M7.5 10.5v3M12 10.5v3M16.5 10.5v3M6 17v3M10 17v3M14 17v3M18 17v3"/>',
    display: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M12 16v4M8.5 20h7"/>',
    airdrop: '<circle cx="12" cy="13" r="1.8"/><path d="M8.6 16.5a4.8 4.8 0 1 1 6.8 0"/><path d="M6 19a8.4 8.4 0 1 1 12 0"/>',
    x: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
    trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9.5 7V4h5v3"/>',
    heart: '<path d="M12 20s-7.5-4.6-7.5-10.2A4.2 4.2 0 0 1 12 7.4a4.2 4.2 0 0 1 7.5 2.4C19.5 15.4 12 20 12 20z"/>',
    search: '<circle cx="11" cy="11" r="6"/><path d="m20 20-4.5-4.5"/>',
    doc: '<path d="M6.5 3h7.5l4.5 4.5V21h-12z"/><path d="M14 3v4.5h4.5M9.5 12.5h5M9.5 16h5"/>',
    link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    file: '<path d="M6.5 3h7.5l4.5 4.5V21h-12z"/><path d="M14 3v4.5h4.5"/>',
    clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
    flag: '<path d="M5.5 21V4h12l-2.5 4.5 2.5 4.5h-12"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    copy: '<rect x="8.5" y="8.5" width="12" height="12" rx="2"/><path d="M15.5 8.5V5.5a2 2 0 0 0-2-2h-8a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h3"/>',
    power: '<path d="M12 3v8.5"/><path d="M6.3 7a8 8 0 1 0 11.4 0"/>',
    sparkles: '<path d="M11 3.5l1.9 5.6 5.6 1.9-5.6 1.9-1.9 5.6-1.9-5.6-5.6-1.9 5.6-1.9z"/><path d="M18.5 16v5M16 18.5h5"/>',
    grid: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
    timer: '<circle cx="12" cy="13.5" r="7.5"/><path d="M12 13.5V9.5M9.5 2.5h5"/>',
    claude: '<path d="M12 4v16M4 12h16M6.3 6.3l11.4 11.4M17.7 6.3 6.3 17.7"/>',
    codex: '<path d="m9 7.5-4.5 4.5L9 16.5M15 7.5l4.5 4.5-4.5 4.5"/>',
    note: '<path d="M9.5 17.5V6l9.5-2v11.5"/><circle cx="7" cy="17.5" r="2.5"/><circle cx="16.5" cy="15.5" r="2.5"/>',
  };
  const SOLID = new Set(['prev', 'next', 'play', 'pause', 'flag']);
  const icon = (name) => `<svg class="${SOLID.has(name) ? 'solid' : ''}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name]}</svg>`;
  const esc = (text) => String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const agentBadge = (agent) => `<span class="nl-agent ${agent}">${icon(agent)}</span>`;

  // ---- Demo data ----
  const TABS = [
    { id: 'home', title: 'Home', icon: 'home', caption: 'A soundtrack, a focus timer, and a place for that passing thought.' },
    { id: 'shelf', title: 'Files', icon: 'tray', caption: 'Drop it here. Pick it up when you need it. Try dragging in a file.' },
    { id: 'reminders', title: 'Reminders', icon: 'checklist', caption: 'Your Apple Reminders. Checked off without leaving your work.' },
    { id: 'dev', title: 'Dev', icon: 'terminal', caption: 'Your limits, your Mac, and every agent session. One glance.' },
  ];
  // Page heights below the top bar, the same as the app's.
  const AREA = { home: 162, notes: 190, shelf: 140, reminders: 236, dev: 272, detail: 330, settings: 260, clipboard: 330 };
  const PRESETS = [
    { name: 'Focus', minutes: 25, color: '#f59a45', min: 5, max: 120, step: 5 },
    { name: 'Break', minutes: 5, color: '#66cc6b', min: 1, max: 30, step: 1 },
    { name: 'Deep', minutes: 50, color: '#c754ed', min: 10, max: 180, step: 5 },
  ];
  const TRACKS = [
    { title: 'Golden Hour Drive', artist: 'Neon Atlas', length: 213, sky: ['#f7a35c', '#e0457b'], hill: '#3a1f5c', sun: '#ffd27a' },
    { title: 'Paper Planes at Noon', artist: 'The Lowlights', length: 187, sky: ['#7dd3fc', '#3b82f6'], hill: '#1e3a5f', sun: '#fef3c7' },
    { title: 'Late Bus Home', artist: 'Mira Vale', length: 241, sky: ['#6d28d9', '#1e1b4b'], hill: '#0f0a24', sun: '#e0e7ff' },
  ];
  const LISTS = [{ name: 'Robotics', color: '#ff9f0a' }, { name: 'School', color: '#0a84ff' }, { name: 'Personal', color: '#30d158' }];
  const STATS = {
    cpu: { title: 'CPU', icon: 'cpu', color: '#0a84ff' },
    memory: { title: 'Memory', icon: 'memory', color: '#30d158' },
    gpu: { title: 'GPU', icon: 'display', color: '#bf5af2' },
  };
  const PROCESSES = [
    ['Xcode', '#1d8cf8'], ['Google Chrome', '#f4b400'], ['Visual Studio Code', '#2f80ed'],
    ['Claude', '#d97757'], ['Music', '#fa2d48'], ['Messages', '#34c759'],
  ];

  const now = Date.now();
  const s = {
    open: true,
    tab: 'dev',
    settings: false,
    section: 'General',
    clipOpen: false,
    notesOpen: false,
    detail: null,
    mirror: false,
    prefs: {
      openDelay: 100, closeDelay: 150, startTab: '', hidden: new Set(), mirrorButton: true,
      claude: true, codex: true, finishedAlert: true, launchAtLogin: true,
      minutes: {}, sound: true, celebration: true, clipLimit: 50, clipPaused: false,
    },
    music: { track: 0, playing: true, pos: 85, at: performance.now(), output: 'laptop' },
    timer: { preset: 'Focus', duration: 1500, endAt: now + 982_000, left: null, sessions: 2 },
    vpn: { on: true, since: now - 77 * 60_000, busy: false },
    notes: [
      'Email coach about Saturday’s tournament',
      'Debate prep\nRebuttal: cost of inaction, cite the 2025 study\nClosing: tie back to the resolution',
      'Robotics build list\nServo brackets, 2x 775 motors, zip ties',
    ],
    note: 0,
    list: 'All',
    rems: [
      { id: 1, title: 'Book the dentist appointment', when: 'Yesterday', late: true, list: 'Personal' },
      { id: 2, title: 'Order replacement servo motors', when: 'Today, 4:00 PM', late: true, list: 'Robotics', flag: true },
      { id: 3, title: 'Finish the chemistry lab report', when: 'Tomorrow', list: 'School' },
    ],
    files: [
      { name: 'Team Poster.pdf', art: 'poster' }, { name: 'Sunset.png', art: 'sunset' }, { name: 'App Icon.png', art: 'app' },
      { name: 'Robot Code.zip', art: 'zip' }, { name: 'Field Photos', art: 'folder' },
    ],
    clips: [
      { text: 'git push origin main', type: 'Text', at: now - 2 * 60_000 },
      { text: 'https://github.com/HamzaLovesCoding/NotchLab', type: 'URL', at: now - 15 * 60_000 },
      { text: 'Robotics meeting moved to 4:30 in room 204', type: 'Text', at: now - 3_600_000, fav: true },
      { text: 'Match Schedule.pdf', type: 'File', at: now - 3 * 3_600_000 },
      { text: 'Thesis: cities should fund public transit', type: 'Text', at: now - 86_400_000 },
    ],
    clipTab: 'history',
    clipQuery: '',
    stats: { cpu: 23, memory: 63, gpu: 18 },
    sessions: [
      { id: 'notchlab', agent: 'claude', status: 'working', msg: '' },
      { id: 'debate-site', agent: 'claude', status: 'done', msg: 'Deployed the preview; the link is in the PR.' },
      { id: 'robot-arm', agent: 'codex', status: 'done', msg: 'Tuned the arm PID loop and all tests pass.' },
    ],
    requests: [],
    finished: null,
    celebrating: false,
    toast: '',
  };

  // ---- Small helpers ----
  const preset = (name) => PRESETS.find((p) => p.name === name);
  const minutesFor = (p) => s.prefs.minutes[p.name] ?? p.minutes;
  const visibleTabs = () => TABS.filter((t) => !s.prefs.hidden.has(t.id) || (t.id === 'dev' && s.requests.length));
  const two = (n) => String(n).padStart(2, '0');
  const clock = (sec) => `${Math.floor(sec / 60)}:${two(Math.floor(sec % 60))}`;
  const musicPos = () => {
    const m = s.music;
    return Math.min(TRACKS[m.track].length, m.pos + (m.playing ? (performance.now() - m.at) / 1000 : 0));
  };
  const timerLeft = () => {
    const t = s.timer;
    if (t.endAt) return Math.max(0, (t.endAt - Date.now()) / 1000);
    return t.left ?? t.duration;
  };
  const ago = (time) => {
    const min = Math.round((Date.now() - time) / 60_000);
    if (min < 1) return 'now';
    if (min < 60) return `${min}m ago`;
    if (min < 1440) return `${Math.round(min / 60)}h ago`;
    return `${Math.round(min / 1440)}d ago`;
  };
  const isTouch = matchMedia('(hover: none)').matches;
  let toastTimer;
  const toast = (text) => {
    s.toast = text;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { s.toast = ''; render(); }, 1800);
    render();
  };

  // ---- Shell ----
  const el = document.createElement('div');
  el.className = 'nl';
  el.setAttribute('role', 'region');
  el.setAttribute('aria-label', 'NotchLab demo');
  el.innerHTML = `
    <button class="nl-pill" type="button" aria-label="Open the NotchLab demo" aria-expanded="false"></button>
    <div class="nl-wingbar"></div>
    <div class="nl-panel"><div class="nl-top"></div><div class="nl-body"></div></div>`;
  stage.append(el);
  stage.classList.add('live');
  document.querySelector('.camera-notch')?.remove();
  const pill = el.querySelector('.nl-pill');
  const wingbar = el.querySelector('.nl-wingbar');
  const panel = el.querySelector('.nl-panel');
  const top = el.querySelector('.nl-top');
  const body = el.querySelector('.nl-body');

  // Scale the 760px-wide stage to the screen it's on.
  new ResizeObserver(([entry]) => {
    stage.style.setProperty('--zoom', Math.min(1, entry.contentRect.width / 760).toFixed(4));
  }).observe(stage.parentElement);

  // ---- Rendering ----
  function alertInfo() {
    const request = s.requests[0];
    if (request) {
      const question = request.kind === 'question';
      return { agent: request.agent, text: question ? 'Question' : 'Approve?', color: question ? '#5a9eff' : '#ff9f0a', pulse: true };
    }
    if (s.finished && s.prefs.finishedAlert) return { agent: s.finished, text: 'Done', color: '#30d158' };
    return null;
  }

  function pageArea() {
    let area;
    if (s.settings) area = AREA.settings;
    else if (s.tab === 'home') area = s.notesOpen ? AREA.notes : AREA.home;
    else if (s.tab === 'dev' && s.detail && !s.requests.length) area = AREA.detail;
    else area = AREA[s.tab];
    return s.clipOpen ? Math.max(area, AREA.clipboard) : area;
  }

  let lastPage = '';
  function render() {
    const focusKey = document.activeElement?.closest?.('.nl [data-act], .nl [data-key]');
    const key = focusKey && (focusKey.dataset.key || `${focusKey.dataset.act}|${focusKey.dataset.arg ?? ''}`);

    const alert = !s.open && (s.celebrating && s.prefs.celebration ? 'celebrate' : alertInfo());
    const wing = alert === 'celebrate' ? 64 : alert ? 88 : 0;
    el.classList.toggle('open', s.open);
    el.classList.toggle('wings', !!alert);
    el.style.width = `${s.open ? 680 : 220 + wing * 2}px`;
    el.style.height = `${s.open ? 38 + pageArea() : 38}px`;
    pill.setAttribute('aria-expanded', String(s.open));
    panel.inert = !s.open;
    wingbar.innerHTML = alert ? renderWings(alert) : '';

    top.innerHTML = renderTop();
    body.style.height = `${pageArea()}px`;
    // Fade in only when the page itself changes, not on every click within it.
    const page = s.settings ? 'settings' : `${s.tab}:${s.notesOpen}:${s.detail}`;
    const entering = page !== lastPage;
    lastPage = page;
    body.innerHTML = (s.settings ? renderSettings() : PAGES[s.tab]())
      + (s.clipOpen ? `<div class="nl-scrim" data-act="clip"></div>${renderClipboard()}` : '')
      + (s.toast ? `<div class="nl-toast" role="status">${esc(s.toast)}</div>` : '');
    if (entering) body.querySelector('.nl-page')?.classList.add('enter');
    tick();
    updateCaption();

    if (key) {
      const [act, arg] = key.split('|');
      const target = el.querySelector(`[data-key="${CSS.escape(key)}"]`)
        || el.querySelector(`[data-act="${CSS.escape(act)}"][data-arg="${CSS.escape(arg ?? '')}"]`)
        || el.querySelector(`[data-act="${CSS.escape(act)}"]:not([data-arg])`);
      target?.focus();
    }
  }

  function renderWings(alert) {
    if (alert === 'celebrate') {
      const t = s.timer;
      const color = preset(t.finished)?.color ?? '#30d158';
      const right = t.finished === 'Break' ? `<b style="color:${color}">Break over</b>` : sessionDots(t.sessions);
      return `<span style="color:${color};font-size:15px">${icon('check')}</span><span>${right}</span>`;
    }
    return `<span>${agentBadge(alert.agent)}</span>
      <span class="${alert.pulse ? 'pulse' : ''}" style="color:${alert.color}"><i class="nl-dot"></i>${alert.text}</span>`;
  }

  function renderTop() {
    const tabs = visibleTabs().map((t) => `
      <button class="nl-icon ${s.tab === t.id && !s.settings ? 'active' : ''}" type="button" data-act="tab" data-arg="${t.id}"
        aria-label="${t.title}" title="${t.title}">${icon(t.icon)}${t.id === 'dev' && s.requests.length ? '<i class="nl-badge"></i>' : ''}</button>`).join('');
    const mirror = s.tab === 'home' && !s.settings && s.prefs.mirrorButton
      ? `<button class="nl-icon ${s.mirror ? 'active' : ''}" type="button" data-act="mirror" aria-label="Mirror" aria-pressed="${s.mirror}" title="Mirror">${icon('camera')}</button>` : '';
    return `<div>${tabs}</div><div>${mirror}
      <button class="nl-icon ${s.clipOpen ? 'active' : ''}" type="button" data-act="clip" aria-label="Clipboard history" aria-pressed="${s.clipOpen}" title="Clipboard history">${icon('clipboard')}</button>
      <button class="nl-icon ${s.settings ? 'active' : ''}" type="button" data-act="gear" aria-label="Settings" aria-pressed="${s.settings}" title="Settings">${icon('gear')}</button></div>`;
  }

  const sessionDots = (count) => `<span class="nl-sessions" aria-label="${count} focus sessions today">${
    [0, 1, 2, 3].map((i) => `<i style="${i < count ? `background:${PRESETS[0].color}` : ''}"></i>`).join('')
  }${count > 4 ? `<b style="font-size:9px;color:${PRESETS[0].color}">+${count - 4}</b>` : ''}</span>`;

  function artwork(track) {
    return `<svg viewBox="0 0 84 84" aria-hidden="true"><defs><linearGradient id="sky${track.title.length}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${track.sky[0]}"/><stop offset="1" stop-color="${track.sky[1]}"/></linearGradient></defs>
      <rect width="84" height="84" fill="url(#sky${track.title.length})"/><circle cx="42" cy="36" r="15" fill="${track.sun}"/>
      <path d="M0 58c18-9 34-9 50-2s26 6 34 2v26H0z" fill="${track.hill}"/></svg>`;
  }

  const PAGES = {
    home() {
      if (s.notesOpen) return renderNotes();
      const track = TRACKS[s.music.track];
      const t = s.timer;
      const running = !!t.endAt;
      const color = preset(t.preset)?.color ?? '#3d94ff';
      const vpnText = s.vpn.busy ? 'Connecting…' : s.vpn.on ? 'Connected' : 'Disconnected';
      return `<div class="nl-page shown">
        <div class="nl-music">
          <div class="nl-art">${artwork(track)}<span class="nl-appbadge">${icon('note')}</span></div>
          <div class="nl-track">
            <b>${esc(track.title)}</b><small class="nl-muted">${esc(track.artist)}</small>
            <span class="nl-seek" role="slider" tabindex="0" aria-label="Playback position" data-key="seek"><i></i></span>
            <div class="nl-times"><span data-tick="elapsed"></span><span data-tick="remaining"></span></div>
            <div class="nl-controls">
              <button type="button" data-act="prev" aria-label="Previous track">${icon('prev')}</button>
              <button class="nl-play" type="button" data-act="play" aria-label="${s.music.playing ? 'Pause' : 'Play'}">${icon(s.music.playing ? 'pause' : 'play')}</button>
              <button type="button" data-act="next" aria-label="Next track">${icon('next')}</button>
              <button class="nl-output" type="button" data-act="output" aria-label="Audio output" title="Audio output">${icon(s.music.output)}</button>
            </div>
          </div>
        </div>
        <div class="nl-side">
          <div class="nl-card nl-timer">
            <i class="nl-timer-fill" style="background:${color}"></i>
            <div>
              <div class="nl-digits" style="color:${running ? color : '#fff'}" data-tick="digits" aria-label="Time left"></div>
              <div class="nl-presets">${PRESETS.map((p) => {
                const on = t.preset === p.name;
                return `<button type="button" data-act="preset" data-arg="${p.name}" title="${p.name} · ${minutesFor(p)} min"
                  style="${on ? `color:${p.color};background:${p.color}38` : ''}" aria-pressed="${on}">${p.name}</button>`;
              }).join('')}</div>
            </div>
            <div class="nl-timer-right">
              <div class="nl-round">
                <button type="button" data-act="timer" aria-label="${running ? 'Pause timer' : 'Start timer'}" style="background:${running ? '#ff9f0a' : '#30d158'}">${icon(running ? 'pause' : 'play')}</button>
                <button type="button" data-act="reset" aria-label="Reset timer" style="background:#ffffff24">${icon('reset')}</button>
              </div>
              ${sessionDots(t.sessions)}
            </div>
          </div>
          <div class="nl-card nl-row">
            <span style="color:${s.vpn.on ? '#30d158' : '#ffffff73'}">${icon('shield')}</span>
            <span class="grow"><b>ProtonVPN</b><small class="nl-muted" data-tick="vpn">${vpnText}</small></span>
            <button class="nl-switch" type="button" role="switch" aria-checked="${s.vpn.on}" aria-label="VPN" data-act="vpn" ${s.vpn.busy ? 'disabled' : ''}></button>
          </div>
          <div class="nl-card nl-row">
            <span class="nl-faint">${icon('pencil')}</span>
            <input class="grow" data-key="quicknote" placeholder="Quick note" aria-label="Quick note" maxlength="300">
            <button class="nl-count" type="button" data-act="notes" aria-label="Open notes">${s.notes.length || ''}${icon('chevron')}</button>
          </div>
        </div>
        ${s.mirror ? '<div class="nl-mirror">The mirror uses your camera in the app. It stays off here.</div>' : ''}
      </div>`;
    },

    shelf() {
      return `<div class="nl-page shown">
        <div class="nl-drop nl-airdrop" data-drop="airdrop" role="button" tabindex="0" data-act="airdrop" aria-label="AirDrop">
          <span><i>${icon('airdrop')}</i></span>AirDrop</div>
        <div class="nl-drop nl-shelf" data-drop="shelf">
          ${s.files.length ? s.files.map((f, i) => `<div class="nl-file" title="${esc(f.name)}">${fileArt(f)}<span>${esc(f.name)}</span>
            <button type="button" data-act="unshelve" data-arg="${i}" aria-label="Remove ${esc(f.name)}">${icon('x')}</button></div>`).join('')
            : '<span class="empty nl-faint">Drop files here to keep them handy</span>'}
          ${s.files.length ? '<button class="clear" type="button" data-act="clearShelf">Clear</button>' : ''}
        </div>
      </div>`;
    },

    reminders() {
      const open = s.rems.filter((r) => !r.done || r.fading);
      const shown = s.list === 'All' ? open : open.filter((r) => r.list === s.list);
      const count = (name) => s.rems.filter((r) => !r.done && (name === 'All' || r.list === name)).length;
      const listColor = (name) => LISTS.find((l) => l.name === name)?.color ?? '#fff';
      return `<div class="nl-page shown">
        <div class="nl-lists">${[{ name: 'All', color: '#fff' }, ...LISTS].map((l) => `
          <button type="button" class="${s.list === l.name ? 'active' : ''}" data-act="list" data-arg="${l.name}">
            <i class="nl-dot" style="color:${l.color}"></i>${l.name}<em>${count(l.name)}</em></button>`).join('')}
        </div>
        <div class="nl-card nl-remcard">
          <header><b>${s.list === 'All' ? 'All Reminders' : s.list}</b><small class="nl-faint">${count(s.list)} left</small></header>
          <div class="nl-rems">${shown.length ? shown.map((r) => `
            <div class="nl-rem ${r.done ? 'done' : ''}">
              <button class="nl-check" type="button" style="color:${listColor(r.list)}" data-act="remind" data-arg="${r.id}"
                role="checkbox" aria-checked="${!!r.done}" aria-label="Complete ${esc(r.title)}">${r.done ? icon('check') : ''}</button>
              <span><b>${esc(r.title)}</b><small style="color:${r.late ? '#ff453a' : '#ffffff73'}">${esc(r.when)} · ${r.list}</small></span>
              ${r.flag ? `<span class="flag">${icon('flag')}</span>` : ''}
            </div>`).join('') : '<p class="nl-faint" style="font-size:11px;margin:20px 0">All done. Nice.</p>'}
          </div>
          <label class="nl-newrem"><span>${icon('plus')}</span>
            <input data-key="newrem" placeholder="New reminder" aria-label="New reminder" maxlength="120"></label>
        </div>
      </div>`;
    },

    dev() {
      if (s.detail && !s.requests.length) return renderDetail();
      const request = s.requests[0];
      const usage = (name, plan, session, week, resets, today, week7) => `
        <div class="nl-card nl-usage">
          <header><b>${name}</b><span class="nl-tag">${plan}</span></header>
          ${[['Session', session, resets[0]], ['Week', week, resets[1]]].map(([title, used, reset]) => `
            <div class="nl-limit"><div><span>${title}</span><span>resets in ${reset}</span></div>
              <div class="nl-bar"><i style="width:${used}%"></i></div>
              <div><span>${used}% used</span><span class="nl-faint">${100 - used}% left</span></div></div>`).join('')}
          <div class="nl-tokens"><span class="nl-muted">Today</span><b>${today[0]}</b><span class="nl-faint">${today[1]}</span>
            <span class="nl-muted" style="margin-left:10px">7 days</span><b>${week7[0]}</b><span class="nl-faint">${week7[1]}</span></div>
        </div>`;
      const topRow = request ? renderRequest(request)
        : usage('Claude', 'Pro', 38, 46, ['2h 13m', '3d 3h'], ['21.4M', '$11.82'], ['96.3M', '$54.10'])
          + usage('Codex', 'Plus', 12, 27, ['4h 29m', '5d 1h'], ['3.2M', '$2.10'], ['18.5M', '$12.40']);
      return `<div class="nl-page shown nl-dev">
        <div>${topRow}</div>
        <div>
          <div class="nl-card nl-stats">${Object.entries(STATS).map(([id, info]) => `
            <button type="button" data-act="stat" data-arg="${id}" aria-label="${info.title} details">${ring(id, 46)}<span data-tick="stat-${id}">${s.stats[id]}%</span></button>`).join('')}
          </div>
          <div class="nl-card nl-sessionlist">${s.sessions.map(renderSession).join('')}</div>
        </div>
      </div>`;
    },
  };

  function ring(id, size) {
    const r = size === 46 ? 20 : 41;
    const c = 2 * Math.PI * r;
    const color = STATS[id].color;
    return `<span class="nl-ring" style="--accent:${color}"><svg viewBox="0 0 ${size} ${size}">
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="${color}" stroke-opacity=".25"/>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="${color}" stroke-dasharray="${c}" data-ring="${id}" data-c="${c}"
        stroke-dashoffset="${c * (1 - s.stats[id] / 100)}"/></svg>${size === 46 ? icon(STATS[id].icon) : `<span data-tick="big-${id}">${s.stats[id]}%</span>`}</span>`;
  }

  function renderDetail() {
    const id = s.detail;
    const info = STATS[id];
    const rows = {
      cpu: [['User', '14%'], ['System', '9%'], ['Idle', '77%'], ['Cores', '10'], ['Uptime', '3d 4h']],
      memory: [['App', '7.00 GB · 44%'], ['Wired', '2.00 GB · 12%'], ['Compressed', '1.00 GB · 6%'], ['Cached', '3.00 GB · 19%'], ['Swap used', '512 MB']],
      gpu: [['Renderer', '12%'], ['Tiler', '6%'], ['VRAM in use', '1.4 GB'], ['Cores', '16'], ['Displays', '2']],
    }[id];
    const usage = { cpu: ['%', [14.4, 10.0, 6.9, 5.1, 1.9, 1.1]], memory: [' GB', ['2.30', '1.60', '1.10', '0.84', '0.32', '0.18']], gpu: ['%', [8.2, 4.1, 2.6, 1.7, 0.9, 0.4]] }[id];
    return `<div class="nl-page shown nl-detail" style="--accent:${info.color}">
      <div class="nl-card" style="width:270px;flex:none">
        <h4>${info.title} Overview</h4>
        <div class="nl-bigring">${ring(id, 92)}<div style="flex:1">${rows.slice(0, 3).map(([k, v]) => `<div class="nl-kv"><i class="nl-dot"></i><span>${k}</span><span>${v}</span></div>`).join('')}</div></div>
        ${rows.slice(3).map(([k, v]) => `<div class="nl-kv"><i class="nl-dot"></i><span>${k}</span><span>${v}</span></div>`).join('')}
      </div>
      <div class="nl-card" style="flex:1">
        <h4>Top Processes</h4>
        <button class="close" type="button" data-act="stat" data-arg="" aria-label="Close details">${icon('x')}</button>
        ${PROCESSES.map(([name, color], i) => `<div class="nl-proc"><i style="background:${color}"></i>
          <span><b>${name}</b><small>${id === 'memory' ? `${usage[1][i]} GB` : `${(usage[1][i] * 0.8).toFixed(1)}% avg`}</small></span>
          <span>${id === 'memory' ? `${(usage[1][i] / 16 * 100).toFixed(1)}%` : `${usage[1][i]}%`}</span></div>`).join('')}
      </div>
    </div>`;
  }

  function renderSession(session) {
    const request = s.requests.find((r) => r.project === session.id);
    const status = request ? (request.kind === 'question' ? 'Asked a question' : 'Needs approval')
      : session.status === 'working' ? 'Working…' : session.msg || 'Done';
    const color = request ? '#ff9f0a' : session.status === 'working' ? '#5a9eff' : '#30d158';
    return `<div class="nl-session">${agentBadge(session.agent)}<span>${session.id}</span>
      <i class="nl-dot" style="color:${color};width:5px;height:5px"></i><small>${esc(status)}</small><time>now</time></div>`;
  }

  function renderRequest(request) {
    const question = request.kind === 'question';
    const accent = question ? '#5a9eff80' : '#ff9f0a80';
    const head = `<header>${agentBadge(request.agent)}<b>${request.agent === 'claude' ? 'Claude' : 'Codex'}</b>
      <span class="nl-muted" style="font-size:11px">· ${request.project}</span>
      <span style="font-size:11px;font-weight:600;color:#ffffffbf">${question ? 'asks' : `wants to use ${request.tool}`}</span>
      <button class="terminal" type="button" data-act="terminal" title="Answer in the terminal instead">Terminal</button>
      ${question
        ? `<button type="button" data-act="send" ${request.pick == null ? 'disabled' : ''} style="background:${request.pick == null ? '#ffffff1a' : '#5a9eff'}">Send</button>`
        : '<button type="button" data-act="deny" style="background:#ffffff24">Deny</button><button type="button" data-act="allow" style="background:#30d158">Allow</button>'}
    </header>`;
    const content = question
      ? `<h4>${request.text}</h4><div class="nl-options" role="radiogroup" aria-label="${request.text}">${request.options.map(([label, detail], i) => `
          <button type="button" role="radio" aria-checked="${request.pick === i}" data-act="pick" data-arg="${i}">
            <i class="radio"></i><span><b>${label}</b><small>${detail}</small></span></button>`).join('')}</div>`
      : `<h4>${request.summary}</h4><pre>${request.command}</pre>`;
    return `<div class="nl-card nl-request" style="--accent:${accent};flex:1">${head}${content}</div>`;
  }

  function renderNotes() {
    const note = s.notes[s.note] ?? '';
    return `<div class="nl-page shown nl-notes">
      <header><b>Notes</b>
        <button type="button" data-act="copyNote" aria-label="Copy note" title="Copy note">${icon('copy')}</button>
        <button type="button" data-act="newNote" aria-label="New note" title="New note">${icon('plus')}</button>
        <button class="done" type="button" data-act="notesDone">Done</button></header>
      <div>
        <div class="nl-notelist">${s.notes.map((text, i) => {
          const [title, ...rest] = text.split('\n');
          return `<button type="button" class="${i === s.note ? 'active' : ''}" data-act="pickNote" data-arg="${i}">
            <b>${esc(title || 'New note')}</b><small>now&nbsp; ${esc(rest.join(' '))}</small></button>`;
        }).join('')}</div>
        <textarea data-key="noteText" aria-label="Note" placeholder="Start typing">${esc(note)}</textarea>
      </div>
    </div>`;
  }

  function renderClipboard() {
    const query = s.clipQuery.toLowerCase();
    const items = s.clips.map((c, i) => ({ ...c, i }))
      .filter((c) => (s.clipTab === 'history' || c.fav) && c.text.toLowerCase().includes(query));
    const iconFor = { Text: 'doc', URL: 'link', File: 'file' };
    return `<div class="nl-clip" role="dialog" aria-label="Clipboard history">
      <header>
        <button type="button" class="${s.clipTab === 'history' ? 'active' : ''}" data-act="clipTab" data-arg="history">${icon('clock')}History <em>${s.clips.length}</em></button>
        <button type="button" class="${s.clipTab === 'favorites' ? 'active' : ''}" data-act="clipTab" data-arg="favorites">${icon('heart')}Favorites</button>
        <button class="trash" type="button" data-act="clearClips" aria-label="Clear history (keeps favorites)" title="Clear history (keeps favorites)">${icon('trash')}</button>
        <button class="x" type="button" data-act="clip" aria-label="Close clipboard">${icon('x')}</button>
      </header>
      <label class="nl-search">${icon('search')}<input data-key="clipSearch" placeholder="Search clipboard…" aria-label="Search clipboard" value="${esc(s.clipQuery)}"></label>
      <div class="nl-clips">${items.length ? items.map((c) => `
        <div class="nl-clipitem">${icon(iconFor[c.type])}
          <button type="button" data-act="copyClip" data-arg="${c.i}" style="flex:1;min-width:0;text-align:left" title="Copy">
            <b>${esc(c.text)}</b><small><span>${c.type}</span><span>${ago(c.at)}</span></small></button>
          <button class="nl-fav" type="button" data-act="fav" data-arg="${c.i}" aria-pressed="${!!c.fav}" aria-label="Favorite">${icon('heart')}</button>
        </div>`).join('') : `<p class="empty nl-faint">${s.clipTab === 'favorites' ? 'Heart an item to keep it here' : 'Copy something on this page'}</p>`}
      </div>
    </div>`;
  }

  // ---- Settings page ----
  const SECTIONS = [['General', 'gear'], ['Agents', 'sparkles'], ['Pages', 'grid'], ['Focus Timer', 'timer'], ['Clipboard & Files', 'clipboard']];
  const toggle = (pref, label) => `<button class="nl-switch" type="button" role="switch" aria-checked="${!!s.prefs[pref]}" aria-label="${label}" data-act="pref" data-arg="${pref}"></button>`;
  const seg = (pref, label, options) => `<span class="nl-seg" role="radiogroup" aria-label="${label}">${options.map(([text, value]) => `
    <button type="button" role="radio" aria-checked="${s.prefs[pref] === value}" data-act="seg" data-arg="${pref}:${value}">${text}</button>`).join('')}</span>`;
  const row = (title, detail, control, badge = '') => `<div class="nl-pref">${badge}<span><b>${title}</b>${detail ? `<small>${detail}</small>` : ''}</span>${control}</div>`;

  function renderSettings() {
    const p = s.prefs;
    const sections = {
      General: () => row('Launch at login', 'Open NotchLab when you log in', toggle('launchAtLogin', 'Launch at login'))
        + row('Open after hovering', 'How long to rest on the notch', seg('openDelay', 'Open delay', [['Instant', 100], ['Short', 300], ['Long', 600]]))
        + row('Close after leaving', 'How long the panel waits for you', seg('closeDelay', 'Close delay', [['Instant', 150], ['Short', 500], ['Long', 1000]]))
        + row('Open to', 'The page you see when the notch opens', `<select class="nl-select" data-key="startTab" aria-label="Open to">
            <option value="">Last page used</option>${visibleTabs().map((t) => `<option value="${t.id}" ${p.startTab === t.id ? 'selected' : ''}>${t.title}</option>`).join('')}</select>`),
      Agents: () => row('Claude Code', p.claude ? 'Questions and approvals come to the notch' : 'Not connected', toggle('claude', 'Connect Claude Code'), agentBadge('claude'))
        + row('Codex', p.codex ? 'Run /hooks in Codex once to trust it' : 'Not connected', toggle('codex', 'Connect Codex'), agentBadge('codex'))
        + row('Flash when an agent finishes', 'A green Done beside the closed notch', toggle('finishedAlert', 'Flash when an agent finishes'))
        + '<p class="nl-note">In the app, connecting adds NotchLab’s helper to the agent’s hook settings.</p>',
      Pages: () => [['shelf', 'A file shelf with AirDrop. Dragged files open it.'], ['reminders', 'Your Apple Reminders lists'], ['dev', 'Usage and sessions. Shows up anyway when an agent asks.']]
        .map(([id, detail]) => row(TABS.find((t) => t.id === id).title, detail,
          `<button class="nl-switch" type="button" role="switch" aria-checked="${!p.hidden.has(id)}" aria-label="Show ${id}" data-act="page" data-arg="${id}"></button>`)).join('')
        + row('Mirror button', 'The camera button on Home', toggle('mirrorButton', 'Mirror button')),
      'Focus Timer': () => PRESETS.map((pr) => row(pr.name, pr.name === 'Break' ? 'Short rest between sessions' : '', `
          <span class="nl-stepper"><button type="button" data-act="step" data-arg="${pr.name}:-1" aria-label="Shorter ${pr.name}" ${minutesFor(pr) <= pr.min ? 'disabled' : ''}>${icon('minus')}</button>
          <span>${minutesFor(pr)} min</span><button type="button" data-act="step" data-arg="${pr.name}:1" aria-label="Longer ${pr.name}" ${minutesFor(pr) >= pr.max ? 'disabled' : ''}>${icon('plus')}</button></span>`)).join('')
        + row('Sound when done', 'A chime when a countdown ends', toggle('sound', 'Sound when done'))
        + row('Celebration', 'Confetti and a check beside the notch', toggle('celebration', 'Celebration')),
      'Clipboard & Files': () => {
        const clips = s.clips.filter((c) => !c.fav).length;
        return row('Keep in history', 'Favorites are always kept', seg('clipLimit', 'History size', [['25', 25], ['50', 50], ['100', 100], ['200', 200]]))
          + row('Pause history', 'Nothing you copy is saved while paused', toggle('clipPaused', 'Pause history'))
          + row('Clear clipboard history', `${clips} ${clips === 1 ? 'item' : 'items'} · favorites stay`, `<button class="nl-pillbtn" type="button" data-act="clearClips" ${clips ? '' : 'disabled'}>Clear</button>`)
          + row('Clear file shelf', `${s.files.length} ${s.files.length === 1 ? 'file' : 'files'} on the shelf`, `<button class="nl-pillbtn" type="button" data-act="clearShelf" ${s.files.length ? '' : 'disabled'}>Clear</button>`);
      },
    };
    return `<div class="nl-page shown nl-settings">
      <div class="nl-sidebar">${SECTIONS.map(([name, ic]) => `
        <button type="button" class="${s.section === name ? 'active' : ''}" data-act="section" data-arg="${name}">${icon(ic)}${name}</button>`).join('')}
        <button class="quit" type="button" data-act="quit">${icon('power')}Quit NotchLab</button>
        <small>Version 1.0</small>
      </div>
      <div class="nl-card nl-prefs">${sections[s.section]()}</div>
    </div>`;
  }

  function fileArt(file) {
    if (file.url) return `<img src="${file.url}" alt="">`;
    const art = {
      poster: '<rect x="12" y="4" width="40" height="56" fill="#2152d9"/><circle cx="32" cy="22" r="9" fill="#ffc94d"/><rect x="18" y="42" width="28" height="3" fill="#fff"/><rect x="18" y="48" width="18" height="2.5" fill="#fff"/>',
      sunset: '<defs><linearGradient id="ss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f7a35c"/><stop offset="1" stop-color="#e0457b"/></linearGradient></defs><rect x="2" y="8" width="60" height="48" fill="url(#ss)"/><circle cx="32" cy="30" r="10" fill="#ffd27a"/><path d="M2 44c14-6 26-6 38-1s18 4 22 1v12H2z" fill="#3a1f5c"/>',
      app: '<rect x="6" y="6" width="52" height="52" rx="12" fill="#1c1d22"/><path d="M14 28h8c2 0 3 6 6 6h8c3 0 4-6 6-6h8" stroke="#fff" stroke-width="2.5" fill="none"/><path d="m26 24 3 2-3 2M31 28h4" stroke="#5ac8fa" stroke-width="1.6" fill="none"/>',
      zip: '<path d="M14 4h26l12 12v44H14z" fill="#f2f2f7"/><path d="M40 4v12h12" fill="#d1d1d6"/><path d="M30 6v4h4v4h-4v4h4v4h-4v4h4" stroke="#8e8e93" stroke-width="2" fill="none"/><text x="33" y="52" font-size="8" fill="#8e8e93" text-anchor="middle" font-family="sans-serif">ZIP</text>',
      folder: '<path d="M4 16a3 3 0 0 1 3-3h16l5 5h29a3 3 0 0 1 3 3v29a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3z" fill="#1a9fe0"/><path d="M4 22h56v28a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3z" fill="#4cc2f5"/>',
      doc: '<path d="M14 4h26l12 12v44H14z" fill="#f2f2f7"/><path d="M40 4v12h12" fill="#d1d1d6"/>',
    }[file.art] ?? '';
    return `<svg viewBox="0 0 64 64" aria-hidden="true">${art}</svg>`;
  }

  // ---- Live values, updated in place so hovers and focus survive ----
  function tick() {
    if (!s.open) return;
    const q = (sel) => body.querySelector(sel);
    if (s.tab === 'home' && !s.settings && !s.notesOpen) {
      const track = TRACKS[s.music.track];
      const pos = musicPos();
      const bar = q('.nl-seek i');
      if (bar) bar.style.width = `${(pos / track.length) * 100}%`;
      const seek = q('.nl-seek');
      seek?.setAttribute('aria-valuetext', `${clock(pos)} of ${clock(track.length)}`);
      if (q('[data-tick=elapsed]')) {
        q('[data-tick=elapsed]').textContent = clock(pos);
        q('[data-tick=remaining]').textContent = `-${clock(track.length - pos)}`;
      }
      const left = Math.ceil(timerLeft());
      const digits = q('[data-tick=digits]');
      if (digits) {
        digits.innerHTML = `<span>${two(Math.floor(left / 3600))}</span><em>:</em><span>${two(Math.floor(left / 60) % 60)}</span><em>:</em><span>${two(left % 60)}</span>`;
        const idle = !s.timer.endAt && s.timer.left == null;
        q('.nl-timer-fill').style.width = `${idle ? 0 : (1 - left / s.timer.duration) * 100}%`;
      }
      const vpn = q('[data-tick=vpn]');
      if (vpn && s.vpn.on && !s.vpn.busy) {
        const min = Math.floor((Date.now() - s.vpn.since) / 60_000);
        vpn.textContent = `Connected · ${min >= 60 ? `${Math.floor(min / 60)}h ${min % 60}m` : `${min}m`}`;
      }
    }
    for (const id of Object.keys(STATS)) {
      el.querySelectorAll(`[data-ring="${id}"]`).forEach((circle) => {
        circle.setAttribute('stroke-dashoffset', circle.dataset.c * (1 - s.stats[id] / 100));
      });
      const small = q(`[data-tick="stat-${id}"]`);
      if (small) small.textContent = `${s.stats[id]}%`;
      const big = q(`[data-tick="big-${id}"]`);
      if (big) big.textContent = `${s.stats[id]}%`;
    }
  }

  setInterval(() => {
    const track = TRACKS[s.music.track];
    if (s.music.playing && musicPos() >= track.length) changeTrack(1);
    if (s.timer.endAt && Date.now() >= s.timer.endAt) finishTimer();
    tick();
  }, 250);

  setInterval(() => {
    // A gentle random walk, like a Mac that's doing a little work.
    const drift = (value, low, high) => Math.round(Math.min(high, Math.max(low, value + (Math.random() - 0.5) * 8)));
    s.stats = { cpu: drift(s.stats.cpu, 8, 60), memory: drift(s.stats.memory, 55, 72), gpu: drift(s.stats.gpu, 4, 45) };
    tick();
  }, 2000);

  function updateCaption() {
    const request = s.requests[0];
    let text;
    if (request && s.open) text = request.kind === 'question' ? 'Claude has a question. Pick an answer and hit Send.' : 'Codex wants to run a command. Allow it, deny it, or send it back to the terminal.';
    else if (!s.open) text = request ? `An agent needs you. ${isTouch ? 'Tap' : 'Hover over'} the notch.` : `${isTouch ? 'Tap' : 'Hover over'} the notch to open it.`;
    else if (s.settings) text = 'Settings work here too. Hide pages, change the timer, slow down the hover.';
    else if (s.clipOpen) text = 'Click an item to copy it. Things you copy on this page show up here too.';
    else text = TABS.find((t) => t.id === s.tab).caption;
    if (caption.textContent !== text) caption.textContent = text;
  }

  // ---- Behavior ----
  function openNotch(tab) {
    clearTimeout(closeTimer);
    if (tab) s.tab = tab;
    if (s.open && !tab) return;
    s.open = true;
    render();
  }

  function closeNotch() {
    clearTimeout(closeTimer);
    if (!s.open) return;
    s.open = false;
    s.settings = false;
    s.clipOpen = false;
    s.detail = null;
    saveQuickNote();
    s.notesOpen = false;
    s.notes = s.notes.filter((n) => n.trim());
    if (s.prefs.startTab) s.tab = s.prefs.startTab;
    if (!visibleTabs().some((t) => t.id === s.tab)) s.tab = 'home';
    render();
  }

  /** Esc steps back one level, then closes. Returns false when nothing was open. */
  function back() {
    if (s.clipOpen) s.clipOpen = false;
    else if (s.settings) s.settings = false;
    else if (s.notesOpen) s.notesOpen = false;
    else if (s.detail) s.detail = null;
    else return false;
    render();
    return true;
  }

  function changeTrack(step) {
    const m = s.music;
    m.track = (m.track + step + TRACKS.length) % TRACKS.length;
    m.pos = 0;
    m.at = performance.now();
    render();
  }

  function startTimer() {
    const t = s.timer;
    t.endAt = Date.now() + timerLeft() * 1000;
    t.left = null;
  }

  function selectPreset(name) {
    const t = s.timer;
    t.preset = name;
    t.duration = minutesFor(preset(name)) * 60;
    t.endAt = null;
    t.left = null;
  }

  function finishTimer() {
    const t = s.timer;
    t.finished = t.preset;
    t.endAt = null;
    t.left = null;
    if (t.preset !== 'Break') t.sessions += 1;
    // Pomodoro rhythm, as in the app: Focus queues a Break, and a Break queues Focus.
    if (t.preset === 'Focus') selectPreset('Break');
    else if (t.preset === 'Break') selectPreset('Focus');
    if (s.prefs.sound) chime();
    if (s.prefs.celebration) {
      s.celebrating = true;
      confetti();
      setTimeout(() => { s.celebrating = false; render(); }, 3500);
    }
    render();
  }

  function chime() {
    try {
      const audio = new AudioContext();
      [880, 1320].forEach((freq, i) => {
        const osc = audio.createOscillator();
        const gain = audio.createGain();
        osc.frequency.value = freq;
        gain.gain.setValueAtTime(0.12, audio.currentTime + i * 0.12);
        gain.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + i * 0.12 + 0.6);
        osc.connect(gain).connect(audio.destination);
        osc.start(audio.currentTime + i * 0.12);
        osc.stop(audio.currentTime + i * 0.12 + 0.6);
      });
    } catch {
      // No audio is fine.
    }
  }

  function confetti() {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const colors = [...PRESETS.map((p) => p.color), '#3d94ff', '#ffd60a', '#fff'];
    for (let i = 0; i < 40; i += 1) {
      const piece = document.createElement('i');
      piece.className = 'nl-confetti';
      piece.style.background = colors[i % colors.length];
      piece.style.setProperty('--x', `${(Math.random() - 0.5) * 360}px`);
      piece.style.setProperty('--y', `${40 + Math.random() * 160}px`);
      piece.style.setProperty('--r', `${Math.random() * 720}deg`);
      stage.append(piece);
      setTimeout(() => piece.remove(), 2100);
    }
  }

  function saveQuickNote() {
    const input = body.querySelector('[data-key=quicknote]');
    const text = input?.value.trim();
    if (!text) return;
    s.notes.unshift(text);
    input.value = '';
  }

  function addClip(text, type = 'Text') {
    if (s.prefs.clipPaused || !text.trim()) return;
    const clean = text.trim().slice(0, 500);
    s.clips = s.clips.filter((c) => c.text !== clean);
    s.clips.unshift({ text: clean, type: /^https?:\/\/\S+$/.test(clean) ? 'URL' : type, at: Date.now() });
    applyClipLimit();
  }

  function applyClipLimit() {
    let kept = 0;
    s.clips = s.clips.filter((c) => c.fav || (kept += 1) <= s.prefs.clipLimit);
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      toast('Copied');
    } catch {
      toast('Your browser blocked copying');
    }
  }

  function settle(request, status, message, delay = 2600) {
    s.requests = s.requests.filter((r) => r !== request);
    const session = s.sessions.find((x) => x.id === request.project);
    session.status = 'working';
    render();
    setTimeout(() => {
      session.status = 'done';
      session.msg = message;
      s.finished = request.agent;
      render();
      setTimeout(() => { s.finished = null; render(); }, 4000);
      request.then?.();
    }, delay);
  }

  const ACTIONS = {
    tab(id) { s.settings = false; s.detail = null; s.notesOpen = false; s.tab = id; },
    mirror() { s.mirror = !s.mirror; },
    clip() { s.clipOpen = !s.clipOpen; },
    gear() { s.settings = !s.settings; },
    play() {
      const m = s.music;
      m.pos = musicPos();
      m.at = performance.now();
      m.playing = !m.playing;
    },
    prev() { if (musicPos() > 3) { s.music.pos = 0; s.music.at = performance.now(); } else changeTrack(-1); },
    next() { changeTrack(1); },
    output() {
      s.music.output = s.music.output === 'laptop' ? 'headphones' : 'laptop';
      toast(`Playing on ${s.music.output === 'laptop' ? 'MacBook Pro Speakers' : 'AirPods Pro'}`);
    },
    preset(name) { selectPreset(name); },
    timer() {
      const t = s.timer;
      if (t.endAt) { t.left = timerLeft(); t.endAt = null; } else startTimer();
    },
    reset() { s.timer.endAt = null; s.timer.left = null; },
    vpn() {
      if (s.vpn.on) { s.vpn.on = false; return; }
      s.vpn.busy = true;
      setTimeout(() => { s.vpn = { on: true, since: Date.now(), busy: false }; render(); }, 900);
    },
    notes() { saveQuickNote(); s.notesOpen = true; s.note = 0; },
    notesDone() { s.notesOpen = false; s.notes = s.notes.filter((n) => n.trim()); s.note = 0; },
    newNote() {
      s.notes = s.notes.filter((n) => n.trim());
      s.notes.unshift('');
      s.note = 0;
      render();
      body.querySelector('[data-key=noteText]')?.focus();
      return true;
    },
    pickNote(i) { s.notes = s.notes.filter((n, j) => n.trim() || j === Number(i)); s.note = Math.min(Number(i), s.notes.length - 1); },
    copyNote() { copyText(s.notes[s.note] ?? ''); return true; },
    list(name) { s.list = name; },
    remind(id) {
      const reminder = s.rems.find((r) => r.id === Number(id));
      reminder.done = !reminder.done;
      // Like Reminders, a checked item lingers a moment before it leaves the list.
      reminder.fading = reminder.done;
      if (reminder.done) setTimeout(() => { reminder.fading = false; render(); }, 1200);
    },
    unshelve(i) {
      const [file] = s.files.splice(Number(i), 1);
      if (file?.url) URL.revokeObjectURL(file.url);
    },
    clearShelf() { s.files.forEach((f) => f.url && URL.revokeObjectURL(f.url)); s.files = []; },
    airdrop() { toast('On your Mac, this opens AirDrop'); return true; },
    stat(id) { s.detail = id || null; },
    pick(i) { s.requests[0].pick = Number(i); },
    send() {
      const request = s.requests[0];
      const [label] = request.options[request.pick];
      settle(request, 'working', `Switched the stats page to a ${label.toLowerCase()}.`);
      return true;
    },
    allow() { settle(s.requests[0], 'working', 'All 48 tests pass.'); return true; },
    deny() { settle(s.requests[0], 'done', 'Stopped. You denied swift test.', 600); return true; },
    terminal() { settle(s.requests[0], 'working', 'Answered in the terminal.'); toast('On your Mac, this brings your terminal forward'); return true; },
    clipTab(tab) { s.clipTab = tab; },
    copyClip(i) {
      const clip = s.clips[Number(i)];
      copyText(clip.text);
      clip.at = Date.now();
      return true;
    },
    fav(i) { s.clips[Number(i)].fav = !s.clips[Number(i)].fav; },
    clearClips() { s.clips = s.clips.filter((c) => c.fav); },
    section(name) { s.section = name; },
    pref(key) {
      s.prefs[key] = !s.prefs[key];
      if (key === 'mirrorButton' && !s.prefs.mirrorButton) s.mirror = false;
    },
    seg(arg) {
      const [key, value] = arg.split(':');
      s.prefs[key] = Number(value);
      if (key === 'clipLimit') applyClipLimit();
    },
    page(id) {
      const hidden = s.prefs.hidden;
      if (hidden.has(id)) hidden.delete(id);
      else {
        hidden.add(id);
        if (s.prefs.startTab === id) s.prefs.startTab = '';
        if (s.tab === id) s.tab = 'home';
      }
    },
    step(arg) {
      const [name, dir] = arg.split(':');
      const p = preset(name);
      s.prefs.minutes[name] = Math.min(p.max, Math.max(p.min, minutesFor(p) + Number(dir) * p.step));
      const t = s.timer;
      if (t.preset === name && !t.endAt && t.left == null) selectPreset(name);
    },
    quit() { closeNotch(); toast('Quit. Hover the notch to bring it back.'); return true; },
  };

  el.addEventListener('click', (event) => {
    const target = event.target.closest('[data-act]');
    if (!target || !el.contains(target) || target.disabled) return;
    const handled = ACTIONS[target.dataset.act]?.(target.dataset.arg);
    if (!handled) render();
  });

  pill.addEventListener('click', () => openNotch());

  el.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      if (!back()) { closeNotch(); pill.focus(); }
      return;
    }
    const target = event.target;
    if (event.key === 'Enter' && target.matches('[data-key=quicknote]')) {
      saveQuickNote();
      target.closest('.nl-row').querySelector('.nl-count').firstChild.textContent = s.notes.length;
      toast('Saved to Notes');
    }
    if (event.key === 'Enter' && target.matches('[data-key=newrem]') && target.value.trim()) {
      s.rems.push({ id: Date.now(), title: target.value.trim(), when: 'Today', list: s.list === 'All' ? 'Personal' : s.list });
      render();
    }
    if (target.matches('[data-act=airdrop]') && (event.key === 'Enter' || event.key === ' ')) {
      event.preventDefault();
      ACTIONS.airdrop();
    }
    if (target.matches('.nl-seek') && (event.key === 'ArrowLeft' || event.key === 'ArrowRight')) {
      event.preventDefault();
      seekTo(musicPos() + (event.key === 'ArrowRight' ? 5 : -5));
    }
  });

  el.addEventListener('input', (event) => {
    const target = event.target;
    if (target.matches('[data-key=noteText]')) {
      s.notes[s.note] = target.value;
      const [title, ...rest] = target.value.split('\n');
      const item = body.querySelector('.nl-notelist .active');
      if (item) {
        item.querySelector('b').textContent = title || 'New note';
        item.querySelector('small').textContent = `now  ${rest.join(' ')}`;
      }
    }
    if (target.matches('[data-key=clipSearch]')) {
      s.clipQuery = target.value;
      const list = body.querySelector('.nl-clips');
      const fresh = document.createElement('div');
      fresh.innerHTML = renderClipboard();
      list.replaceWith(fresh.querySelector('.nl-clips'));
    }
  });

  el.addEventListener('change', (event) => {
    if (event.target.matches('[data-key=startTab]')) s.prefs.startTab = event.target.value;
  });

  // Seeking: click or drag along the bar.
  function seekTo(seconds) {
    const m = s.music;
    m.pos = Math.max(0, Math.min(TRACKS[m.track].length - 1, seconds));
    m.at = performance.now();
    tick();
  }
  el.addEventListener('pointerdown', (event) => {
    const bar = event.target.closest('.nl-seek');
    if (!bar) return;
    const move = (e) => {
      const rect = bar.getBoundingClientRect();
      seekTo(((e.clientX - rect.left) / rect.width) * TRACKS[s.music.track].length);
    };
    bar.setPointerCapture(event.pointerId);
    move(event);
    bar.onpointermove = move;
    bar.onpointerup = () => { bar.onpointermove = null; };
  });

  // Copies made anywhere on the page land in the demo's clipboard history.
  document.addEventListener('copy', () => {
    const text = String(getSelection() ?? '');
    if (text && !el.contains(document.activeElement)) { addClip(text); if (s.clipOpen) render(); }
  });

  // ---- Hover to open, leave to close (mouse); tap to open, tap elsewhere to close (touch) ----
  let openTimer;
  let closeTimer;
  let inside = false;
  const editing = () => el.contains(document.activeElement) && document.activeElement.matches('input, textarea, select');

  el.addEventListener('pointerenter', (event) => {
    if (event.pointerType !== 'mouse') return;
    inside = true;
    clearTimeout(closeTimer);
    if (!s.open) openTimer = setTimeout(() => openNotch(), s.prefs.openDelay);
  });
  el.addEventListener('pointerleave', (event) => {
    if (event.pointerType !== 'mouse') return;
    inside = false;
    clearTimeout(openTimer);
    // Typing keeps the notch open even if the pointer drifts away, like the app.
    if (s.open && !editing()) closeTimer = setTimeout(closeNotch, s.prefs.closeDelay);
  });
  el.addEventListener('focusout', () => {
    setTimeout(() => {
      if (s.open && !inside && !el.contains(document.activeElement) && !isTouch) closeTimer = setTimeout(closeNotch, s.prefs.closeDelay);
    });
  });
  document.addEventListener('pointerdown', (event) => {
    if (s.open && !el.contains(event.target)) closeNotch();
  });

  // ---- Dropping real files from the visitor's computer (they stay in the browser) ----
  const hasFiles = (event) => [...(event.dataTransfer?.types ?? [])].includes('Files');
  stage.addEventListener('dragover', (event) => {
    if (!hasFiles(event) || !visibleTabs().some((t) => t.id === 'shelf')) return;
    event.preventDefault();
    if (!s.open || s.tab !== 'shelf' || s.settings) {
      s.settings = false;
      s.clipOpen = false;
      openNotch('shelf');
      render();
    }
    const zone = event.target.closest?.('[data-drop]');
    body.querySelectorAll('[data-drop]').forEach((z) => z.classList.toggle('over', z === zone || (!zone && z.dataset.drop === 'shelf')));
  });
  stage.addEventListener('dragleave', (event) => {
    if (!stage.contains(event.relatedTarget)) body.querySelectorAll('[data-drop]').forEach((z) => z.classList.remove('over'));
  });
  stage.addEventListener('drop', (event) => {
    if (!hasFiles(event)) return;
    event.preventDefault();
    const files = [...event.dataTransfer.files];
    if (event.target.closest?.('[data-drop=airdrop]')) {
      toast(`On your Mac, AirDrop would send ${files.length === 1 ? files[0].name : `${files.length} files`}`);
      return;
    }
    for (const file of files.slice(0, 12)) {
      if (s.files.some((f) => f.name === file.name)) continue;
      s.files.push({ name: file.name, art: 'doc', url: file.type.startsWith('image/') ? URL.createObjectURL(file) : null });
    }
    render();
  });

  // ---- The agent demo: a question, then an approval, once the hero is on screen ----
  function ask(request) {
    s.requests.push(request);
    const session = s.sessions.find((x) => x.id === request.project);
    s.sessions = [session, ...s.sessions.filter((x) => x !== session)];
    // Like the app: arriving while closed, the next hover lands on the request.
    if (!s.open) { s.tab = 'dev'; s.settings = false; s.detail = null; }
    render();
  }

  const askCodex = () => ask({
    agent: 'codex', kind: 'permission', project: 'robot-arm', tool: 'Bash',
    summary: 'Run the test suite', command: 'swift test --parallel',
  });

  const askClaude = () => ask({
    agent: 'claude', kind: 'question', project: 'notchlab', pick: null,
    text: 'Which chart should the stats page use?',
    options: [['Line chart', 'Best for trends over time'], ['Bar chart', 'Compare a few categories'], ['Sparklines', 'Tiny inline trends'], ['Table', 'When exact numbers matter']],
    then: () => setTimeout(() => {
      s.sessions.find((x) => x.id === 'robot-arm').status = 'working';
      render();
      setTimeout(askCodex, 2500);
    }, 3000),
  });

  new IntersectionObserver((entries, observer) => {
    if (!entries[0].isIntersecting) return;
    observer.disconnect();
    setTimeout(askClaude, 2500);
  }, { threshold: 0.5 }).observe(stage);

  render();
})();
