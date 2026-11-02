const views = {
  developer: {
    alt: 'NotchLab Dev page with Claude and Codex usage limits, CPU, memory, and GPU rings, and recent agent sessions',
    caption: 'Your limits, your Mac, and every agent session. One glance.',
    height: 692,
  },
  home: {
    alt: 'NotchLab Home page with a playing song, a running focus timer, a VPN switch, and a quick note field',
    caption: 'A soundtrack, a focus timer, and a place for that passing thought.',
    height: 472,
  },
  files: {
    alt: 'NotchLab Files page with files on the shelf next to an AirDrop drop zone',
    caption: 'Drop it here. Pick it up when you need it.',
    height: 428,
  },
  reminders: {
    alt: 'NotchLab Reminders page with Robotics, School, and Personal lists and upcoming reminders',
    caption: 'Your Apple Reminders. Checked off without leaving your work.',
    height: 620,
  },
};

const tabs = [...document.querySelectorAll('[role="tab"]')];
const panel = document.querySelector('#preview-panel');
const preview = document.querySelector('#preview-image');
const caption = document.querySelector('#preview-caption');

function selectTab(tab) {
  const name = tab.dataset.view;
  const view = views[name];
  for (const item of tabs) {
    const selected = item === tab;
    item.setAttribute('aria-selected', String(selected));
    item.tabIndex = selected ? 0 : -1;
  }
  preview.src = `assets/notch-${name}.png`;
  preview.alt = view.alt;
  preview.height = view.height;
  caption.textContent = view.caption;
  panel.setAttribute('aria-labelledby', tab.id);
}

tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', (event) => {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = tabs.length - 1;
    if (next === undefined) return;
    event.preventDefault();
    tabs[next].focus();
    selectTab(tabs[next]);
  });
});

const copyButton = document.querySelector('.copy-button');
const copyStatus = document.querySelector('.copy-status');
copyButton.addEventListener('click', async () => {
  const commands = document.querySelector('#install-commands');
  try {
    await navigator.clipboard.writeText(commands.textContent);
    copyStatus.textContent = 'Copied. Ready for Terminal.';
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(commands);
    selection.removeAllRanges();
    selection.addRange(range);
    copyStatus.textContent = 'Commands selected. Press ⌘C on your Mac to copy.';
  }
});

document.querySelector('a[href="#setup-note"]').addEventListener('click', () => {
  document.querySelector('#setup-note').open = true;
});
