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

// Story captures wait for the hero's LCP entry (or 3s, or load where LCP isn't reported), keeping them out of its LCP window (direction.css).
const storyReady = () => document.documentElement.classList.add('story-ready');
if (PerformanceObserver.supportedEntryTypes?.includes('largest-contentful-paint')) {
  new PerformanceObserver((list, observer) => {
    if (list.getEntries().some(entry => entry.element?.closest('.direction-product'))) {observer.disconnect();storyReady();}
  }).observe({type:'largest-contentful-paint', buffered:true});
  setTimeout(storyReady, 3000);
} else addEventListener('load', storyReady, {once:true});

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
// A sentinel above the fold marks the scrolled header without a scroll handler (older browsers and reduced motion).
const header = document.querySelector('header');
const headerSentinel = document.createElement('div');
headerSentinel.style.cssText = 'position:absolute;top:0;left:0;width:1px;height:48px;pointer-events:none';
document.body.prepend(headerSentinel);
new IntersectionObserver(([entry]) => {
  header.classList.toggle('is-scrolled', !entry.isIntersecting);
}).observe(headerSentinel);

// One pill follows the hovered or focused link and otherwise rests on the current section.
const siteNav = header.querySelector('nav');
const indicator = document.createElement('span');
indicator.className = 'nav-indicator';
indicator.setAttribute('aria-hidden', 'true');
siteNav.prepend(indicator);
const moveIndicator = link => {
  indicator.classList.toggle('is-on', Boolean(link));
  if (link) indicator.style.cssText = `--x:${link.offsetLeft}px;--w:${link.offsetWidth}px`;
};
const currentLink = () => siteNav.querySelector('[aria-current]');
siteNav.addEventListener('pointerover', event => event.target.closest('a') && moveIndicator(event.target.closest('a')));
siteNav.addEventListener('focusin', event => moveIndicator(event.target));
siteNav.addEventListener('pointerleave', () => moveIndicator(currentLink()));
siteNav.addEventListener('focusout', () => moveIndicator(currentLink()));

// Scroll-spy: a section belongs to the nearest earlier section with a header link (Free under Why, FAQ under Trust).
const spyLinks = new Map([...siteNav.querySelectorAll('a[href^="#"]')].map(link => [link.hash.slice(1), link]));
const sections = [...document.querySelectorAll('main > section')];
const owner = section => {
  for (let i = sections.indexOf(section); i >= 0; i--) if (spyLinks.has(sections[i].id)) return spyLinks.get(sections[i].id);
};
if (spyLinks.size) {
  const spy = new IntersectionObserver(entries => {
    const entry = entries.find(entry => entry.isIntersecting);
    if (!entry) return;
    const link = owner(entry.target);
    spyLinks.forEach(other => other === link ? other.setAttribute('aria-current', 'location') : other.removeAttribute('aria-current'));
    if (!siteNav.matches(':hover, :focus-within')) moveIndicator(link);
  }, {rootMargin:'-30% 0px -69% 0px'});
  sections.forEach(section => spy.observe(section));
}
