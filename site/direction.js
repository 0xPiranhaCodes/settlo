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
