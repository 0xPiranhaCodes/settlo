// No scroll handlers: native timelines, or a three-step observer fallback.
const directionMotion = matchMedia('(prefers-reduced-motion: no-preference)');
let directionObserver;
function enhanceDirection() {
  directionObserver?.disconnect();
  document.documentElement.classList.toggle('direction-enhanced', directionMotion.matches);
  const fallback = directionMotion.matches && !CSS.supports('animation-timeline: view()');
  document.documentElement.classList.toggle('direction-fallback', fallback);
  if (!fallback) return;
  const panels = [...document.querySelectorAll('.direction-panel')];
  panels[0]?.classList.add('is-active');
  directionObserver = new IntersectionObserver(entries => {
    for (const entry of entries) if (entry.isIntersecting) {
      const index = [...entry.target.parentElement.children].indexOf(entry.target);
      panels.forEach((panel, i) => panel.classList.toggle('is-active', i === index));
    }
  }, {rootMargin:'-45% 0px -45% 0px', threshold:0});
  document.querySelectorAll('.direction-markers i').forEach(marker => directionObserver.observe(marker));
}
enhanceDirection();
directionMotion.addEventListener('change', enhanceDirection);

// Time-based entrances once a block is in view; content stays visible without JS or with reduced motion.
const reveals = new IntersectionObserver(entries => {
  for (const entry of entries) if (entry.isIntersecting) {
    entry.target.classList.add('is-in');
    reveals.unobserve(entry.target);
  }
}, {rootMargin:'0px 0px -10% 0px'});
document.querySelectorAll('.reveal').forEach(element => reveals.observe(element));

// Native popover handles light dismissal and Escape; contain keyboard focus.
const menu = document.querySelector('#mobile-menu');
const menuButton = document.querySelector('.mobile-menu-button');
menu.addEventListener('toggle', event => {
  const open = event.newState === 'open';
  menuButton.setAttribute('aria-expanded', String(open));
  if (!open && matchMedia('(max-width:720px)').matches) menuButton.focus({preventScroll:true});
});
menu.addEventListener('click', event => {
  if (event.target.closest('a')) menu.hidePopover();
});
menu.addEventListener('keydown', event => {
  if (event.key !== 'Tab') return;
  const targets = [...menu.querySelectorAll('button, a[href]')];
  const first = targets[0], last = targets.at(-1);
  if (event.shiftKey && document.activeElement === first) {event.preventDefault();last.focus();}
  else if (!event.shiftKey && document.activeElement === last) {event.preventDefault();first.focus();}
});
matchMedia('(max-width:720px)').addEventListener('change', event => {
  if (!event.matches) menu.hidePopover();
});
// A one-pixel sentinel avoids a scroll handler in older browsers and reduced motion.
const headerSentinel = document.createElement('div');
headerSentinel.style.cssText = 'position:absolute;top:0;left:0;width:1px;height:1px;pointer-events:none';
document.body.prepend(headerSentinel);
new IntersectionObserver(([entry]) => {
  document.querySelector('header').classList.toggle('is-scrolled', !entry.isIntersecting);
}).observe(headerSentinel);
