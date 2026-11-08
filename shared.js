/* White Lion SME OS — shared helpers used across modules.
   Loaded first (not deferred) so window.esc exists before any other script runs. */
window.esc = function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
};
