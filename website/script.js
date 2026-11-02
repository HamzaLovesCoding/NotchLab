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
