# Performance Optimization & Lazy Loading Engineering Report

**Course**: Advanced Web Development Frameworks (ITUE301)  
**Practical**: Practical 8 — React Performance Optimization & Lazy Loading  
**Student**: Vishvam Patel (24IT110)  
**Institution**: CSPIT / DEPSTAR, Charotar University of Science and Technology (CHARUSAT)  
**Date**: October 2026  

---

## 1. Executive Summary

In modern Single Page Applications (SPAs) built with React, shipping a monolithic JavaScript bundle forces the browser to download, decompress, parse, and compile the entire application's source code before rendering even the first interactive pixel. For users who only need the home dashboard, downloading code for infrequently visited routes (such as *Projects* or *Contact*) or heavy data visualization libraries introduces unnecessary latency and degrades Core Web Vitals, specifically **Largest Contentful Paint (LCP)** and **Total Blocking Time (TBT)**.

In Practical 8, we optimized the full-stack Task Management application from Practical 7 by implementing:
1. **Route-based code splitting** using `React.lazy()` and dynamic `import()` for the `/projects` and `/contact` routes.
2. **Component-level lazy loading** for a heavy data visualization component (`ProjectAnalyticsChart`).
3. **Graceful loading fallback orchestration** using `<Suspense fallback={<LoadingFallback />}>`.
4. **Network resilience** via a chunk-level `<ErrorBoundary>` with automatic retry capability.
5. **Demonstration reliability** via a clean `lazyWithDelay` helper to prevent visual jitter on high-speed connections.
6. **Avoidable re-render elimination** verified with React DevTools Profiler using `React.memo` and `useCallback`.

---

## 2. Architecture Comparison

### 2.1 Baseline Architecture (Single Monolithic Bundle)

In the unoptimized Practical 7 baseline, all route components, forms, modals, and helper utilities were statically imported into `App.jsx`.

```text
Browser Navigation Request (GET /)
               │
               ▼
┌────────────────────────────────────────────────────────┐
│               index-BtVcVxlB.js (225.91 kB)            │
│  ┌──────────────┬──────────────┬────────────────────┐  │
│  │ App Core     │ Auth Pipeline│ Task Dashboard     │  │
│  ├──────────────┼──────────────┼────────────────────┤  │
│  │ Projects UI  │ Contact Form │ Analytics Charts   │  │
│  └──────────────┴──────────────┴────────────────────┘  │
└────────────────────────────────────────────────────────┘
```
- **Consequence**: The browser had to download all 225.91 kB raw (69.84 kB gzipped) upfront, even though the user had not navigated to Projects or Contact.

### 2.2 Optimized Architecture (Route & Component Code-Split)

With dynamic imports, Vite emits separate chunk files that are fetched only when their respective route or trigger is activated:

```text
First Visit (GET /)
        │
        ▼
┌──────────────────────────────────────────────┐
│  index-CzuTOBEH.js (Entry Bundle)            │ ──► Critical layout, React runtime,
│  index-CaBrKKEw.css (CSS Tokens)             │     TaskDashboard & Auth rendered immediately
└──────────────────────────────────────────────┘

Navigate to /projects
        │
        ▼  (HTTP GET Projects-D1QRbIZX.js)
┌──────────────────────────────────────────────┐
│  Projects-D1QRbIZX.js (6.59 kB)              │ ──► Downloaded on demand;
│  <Suspense> shows LoadingFallback during DL │     renders Projects page
└──────────────────────────────────────────────┘

User clicks "Load Workload Analytics"
        │
        ▼  (HTTP GET ProjectAnalyticsChart-seLfSKDH.js)
┌──────────────────────────────────────────────┐
│  ProjectAnalyticsChart-seLfSKDH.js (12.09 kB)│ ──► Component-level heavy chunk
│  <Suspense> renders nested chart skeleton    │     loaded only when needed
└──────────────────────────────────────────────┘

Navigate to /contact
        │
        ▼  (HTTP GET Contact-CK2eO3uX.js)
┌──────────────────────────────────────────────┐
│  Contact-CK2eO3uX.js (7.35 kB)               │ ──► Downloaded on demand only
│  Renders Contact form & student credentials  │     when visiting /contact
└──────────────────────────────────────────────┘
```

---

## 3. Implementation Details

### 3.1 Route-Based Lazy Loading

Dynamic imports were defined at the root routing boundary in `src/App.jsx`:

```javascript
import React, { lazy, Suspense } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';

// Eagerly loaded primary view
import Dashboard from './pages/Dashboard';

// Dynamically imported code-split routes
const Projects = lazy(() => import('./pages/Projects'));
const Contact = lazy(() => import('./pages/Contact'));
```

The route hierarchy was wrapped with a single `<Suspense>` boundary containing an accessible fallback:

```jsx
<ErrorBoundary>
  <Suspense fallback={<LoadingFallback message="Downloading route module chunk on demand..." />}>
    <Routes>
      <Route path="/" element={<Dashboard />} />
      <Route path="/projects" element={<Projects />} />
      <Route path="/contact" element={<Contact />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  </Suspense>
</ErrorBoundary>
```

### 3.2 Heavy Component Lazy Loading

Inside `src/pages/Projects.jsx`, the analytics visualizer is imported dynamically and rendered inside a nested `<Suspense>` boundary only when the user toggles the analytics view:

```javascript
const ProjectAnalyticsChart = lazy(() => import('../components/ProjectAnalyticsChart'));

// Inside component JSX:
{showAnalytics && (
  <Suspense fallback={<LoadingFallback message="Downloading ProjectAnalyticsChart heavy chunk on demand..." />}>
    <ProjectAnalyticsChart />
  </Suspense>
)}
```

### 3.3 Network Throttling & Minimum Delay Simulation

On local networks or fast campus Wi-Fi, chunk requests typically resolve in &lt; 15 ms, causing the `<Suspense>` fallback UI to flash imperceptibly. For academic demonstration and faculty viva assessment:
- Chrome DevTools Network throttling should be set to **Slow 3G** (simulates 400 ms RTT and 400 kbps bandwidth).
- We implemented `src/utils/lazyWithDelay.js` which combines the real dynamic import Promise with a minimum delay timer via `Promise.all`:

```javascript
export function lazyWithDelay(importFactory, minDelayMs = 0) {
  return lazy(() => {
    if (!minDelayMs || minDelayMs <= 0) return importFactory();
    return Promise.all([
      importFactory(),
      new Promise((resolve) => setTimeout(resolve, minDelayMs))
    ]).then(([moduleExports]) => moduleExports);
  });
}
```

---

## 4. Production Build Verification & Chunk Analysis

Running `npm run build` in `frontend/` produces the following real output:

```text
vite v8.2.1 building client environment for production...
✓ 1819 modules transformed.
rendering chunks (1)...rendering chunks (2)...rendering chunks (3)...rendering chunks (4)...computing gzip size...
dist/index.html                                  0.75 kB │ gzip:  0.43 kB
dist/assets/index-CaBrKKEw.css                   5.33 kB │ gzip:  1.70 kB
dist/assets/Projects-D1QRbIZX.js                 6.59 kB │ gzip:  2.30 kB
dist/assets/Contact-CK2eO3uX.js                  7.35 kB │ gzip:  2.18 kB
dist/assets/ProjectAnalyticsChart-seLfSKDH.js   12.09 kB │ gzip:  3.04 kB
dist/assets/index-CzuTOBEH.js                  288.83 kB │ gzip: 88.19 kB
✓ built in 595ms
```

### Analysis of Chunks:
1. **Entry Chunk (`index-CzuTOBEH.js`)**: Contains React 19, React DOM, React Router 7, core Lucide icons, Auth Context, and the default Dashboard view.
2. **Projects Route Chunk (`Projects-D1QRbIZX.js`)**: Exactly 6.59 kB (2.30 kB gzip). Downloaded only when user navigates to `/projects`.
3. **Contact Route Chunk (`Contact-CK2eO3uX.js`)**: Exactly 7.35 kB (2.18 kB gzip). Downloaded only when user navigates to `/contact`.
4. **Heavy Component Chunk (`ProjectAnalyticsChart-seLfSKDH.js`)**: Exactly 12.09 kB (3.04 kB gzip). Downloaded only when the analytics view is requested.
5. **Total Deferred JavaScript**: `6.59 + 7.35 + 12.09 = 26.03 kB` raw (7.52 kB gzipped) deferred from initial payload.

---

## 5. React DevTools Profiler Investigation: Avoidable Re-render

### 5.1 The Identified Issue
In `TaskDashboard.jsx`, the component maintains local form state (`title`, `description`, `priority`) for adding new tasks.
- **Before Optimization**: Whenever a user typed a character into the task title input field, `setTitle` triggered a re-render of `TaskDashboard`. Because task items were mapped inline as JSX elements, every existing task card in the list re-rendered on every keystroke.
- In a list of 20 tasks, typing a 15-character title caused `20 * 15 = 300` unnecessary component re-renders!

### 5.2 The Optimization Applied
1. Extracted individual task rendering into a standalone `TaskItem` component.
2. Wrapped `TaskItem` in `React.memo`:
   ```javascript
   const TaskItem = memo(function TaskItem({ task, onToggle, onDelete }) { ... });
   ```
3. Stabilized the `onToggle` and `onDelete` handler references in the parent component using `useCallback`:
   ```javascript
   const handleToggleTask = useCallback(async (task) => { ... }, [showToast]);
   const handleDeleteTask = useCallback(async (id) => { ... }, [showToast]);
   ```

### 5.3 Profiler Verification
- **Test Interaction**: Record a 5-second profiling session while typing "Deploy Performance Fix" into the title input field.
- **Before**: DevTools Profiler Flamegraph displays all `TaskItem` bars colored yellow/green with reason: *"Parent component rendered"*.
- **After**: All `TaskItem` components are grayed out with note: *"Did not render (props did not change)"*.

---

## 6. Conclusion & Viva Takeaways

1. `React.lazy()` enables dynamic loading of JavaScript bundles at the component boundary, fundamentally decoupling initial page weight from total application size.
2. `Suspense` acts as a declarative concurrency boundary, coordinating loading fallbacks without requiring imperative boolean loading flags scattered across components.
3. Code splitting improves **perceived performance** and **LCP/FID** by prioritizing the critical path, even though total transferred bytes across a full multi-page session remains roughly constant.
4. Profiling before optimizing prevents premature memoization. Only components with expensive subtrees or frequent parent re-renders benefit measurably from `React.memo`.
