# Practical 10: Asynchronous Processing with Event-Driven Architecture

**Course**: Advanced Web Development Frameworks (ITUE301)  
**Student Name**: Vishvam Patel  
**Student ID**: 24IT110  
**Department**: Information Technology / Computer Science / AIML  
**Institution**: CSPIT / DEPSTAR, Charotar University of Science and Technology (CHARUSAT)  

---

## 1. Practical Title & Subject Code

- **Practical Title**: Asynchronous Processing with Event-Driven Architecture (EDA) in Node.js & Express
- **Subject Code**: ITUE301 (Advanced Web Development Frameworks)
- **Course Outcomes (COs)**: CO2 (Develop scalable server-side applications), CO4 (Optimize web performance, asynchronous workflows, and decoupled services) / PO3, PO5

---

## 2. Aim & Objectives

### Aim
To architect and implement an Asynchronous Event-Driven Architecture (EDA) in a Node.js/Express REST application using `EventEmitter`, decoupling background side effects (Audit Logging, Email Notifications, Analytics Calculations) and long-running batch jobs from the synchronous client HTTP request-response pipeline.

### Key Objectives
1. **Event-Driven Decoupling**: Build a centralized singleton `AppEventBus` extending Node.js `EventEmitter` to publish domain events (`task:created`, `task:updated`, `task:completed`, `task:deleted`) without blocking HTTP clients.
2. **Decoupled Background Workers**: Implement three independent background listener workers:
   - **Audit Logger**: Appends immutable, structured security audit trails.
   - **Notification Dispatcher**: Simulates external transactional email/webhook alerts with simulated network delays.
   - **Analytics Aggregator**: Calculates real-time task velocities and completion ratios asynchronously.
3. **Long-Running Job Queue (HTTP 202 Accepted)**: Design an asynchronous job processing system returning `HTTP 202 Accepted` immediately with a unique `jobId`, allowing clients to poll status (`GET /tasks/events/jobs/:id`) while stages execute in the background (0% -> 100%).
4. **Quantitative Benchmark**: Measure and compare client response latency between synchronous blocking execution and asynchronous event dispatching.
5. **Interactive Frontend Dashboard**: Provide a comprehensive "Event Hub" modal with live event telemetry, worker status monitoring, job queue submission/polling, and benchmark execution.
6. **Automated Verification**: Build an end-to-end automated test script (`npm run test:p10`) verifying all EDA capabilities and error isolation.

---

## 3. Technologies & Tools

- **Event System**: Node.js Native `EventEmitter` (`events` module)
- **Backend Framework**: Express.js (v4.19.2), Node.js (v18+)
- **Security & Pipeline**: JWT (`jsonwebtoken`), `bcryptjs`, Express Middleware
- **Frontend SPA**: React 19, Vite v8, Lucide React Icons, Vanilla CSS Glassmorphism
- **Automated Testing**: Node.js `test_practical10_eda.js` with ANSI reporting and Performance Timing API

---

## 4. Architecture & Workflow Diagrams

### 4.1 Synchronous Blocking vs. Event-Driven Asynchronous Pipeline

```text
SYNCHRONOUS BLOCKING PIPELINE (Traditional Monolith - Slow):
Client Request
      │
      ▼
┌───────────────┐
│ DB Write      │ (~30 ms)
└───────┬───────┘
        ▼
┌───────────────┐
│ Audit Log I/O │ (~45 ms)
└───────┬───────┘
        ▼
┌───────────────┐
│ SMTP / Email  │ (~280 ms)   [CLIENT WAITING BLOCKED: Total ~459 ms]
└───────┬───────┘
        ▼
┌───────────────┐
│ Aggregations  │ (~100 ms)
└───────┬───────┘
        ▼
HTTP 201 Created Response


EVENT-DRIVEN ASYNCHRONOUS PIPELINE (Decoupled EDA - Fast):
Client Request
      │
      ▼
┌───────────────┐
│ DB Write      │ (~30 ms)
└───────┬───────┘
        │
        ├────────────────────────────────────────┐
        ▼                                        ▼
HTTP 201 Response Sent (~33 ms)          eventBus.publish('task:created')
[Client unblocked & instant]                     │
                                                 ├──► [Worker 1: Audit Logger] (~45 ms)
                                                 ├──► [Worker 2: Email Notifier] (~280 ms)
                                                 └──► [Worker 3: Analytics] (~100 ms)
                                                 (Execute concurrently in background event loop)
```

### 4.2 Asynchronous Job Queue Lifecycle (HTTP 202 Accepted Pattern)

```text
Client                              Express Server                       Background Worker
  │                                       │                                     │
  │── POST /tasks/events/jobs ───────────►│                                     │
  │   { type: 'PROJECT_ANALYTICS_REPORT' }│                                     │
  │                                       │── createJob() ─────────────────────►│
  │                                       │   status: 'pending', progress: 0%   │
  │◄── HTTP 202 Accepted ─────────────────│                                     │
  │   { jobId: 'job-mvqs3dnl-xfg3' }      │                                     │
  │                                       │                                     │
  │                                       │                                     │── Stage 1: Data Gathering (25%)
  │── GET /tasks/events/jobs/:id ────────►│                                     │── Stage 2: Metric Computation (50%)
  │◄── status: 'processing', 25% ─────────│                                     │── Stage 3: Statistical Synthesis (80%)
  │                                       │                                     │── Stage 4: Artifact Rendered (100%)
  │                                       │                                     │   status: 'completed'
  │── GET /tasks/events/jobs/:id ────────►│                                     │
  │◄── status: 'completed', 100% ─────────│◄── Return Generated Artifact ───────│
  │   { reportTitle, metrics, download }  │
```

---

## 5. Implementation Highlights

### 5.1 Centralized EventBus (`backend/src/utils/eventBus.js`)

The `AppEventBus` class wraps Node.js `EventEmitter` to provide:
1. **Isolated Asynchronous Invocation**: Uses `setImmediate()` or `process.nextTick()` so listener errors cannot crash the main HTTP handler.
2. **Telemetry Tracking**: Records total emitted events, event counts by category, and accumulated non-blocking execution time saved.
3. **Circular Event Buffer**: Retains the last 50 processed domain events for live streaming inspection.
4. **Managed Job Queue**: Handles asynchronous batch workloads with progress tracking and report artifact generation.

```javascript
class AppEventBus extends EventEmitter {
  constructor() {
    super();
    this.setMaxListeners(30);
    this.telemetry = {
      totalEmitted: 0,
      byEvent: {},
      totalAsyncTimeSavedMs: 0
    };
    this.eventLog = [];
    this.jobQueue = new Map();
  }

  publish(eventName, payload = {}) {
    this.telemetry.totalEmitted++;
    this.telemetry.byEvent[eventName] = (this.telemetry.byEvent[eventName] || 0) + 1;

    // Asynchronously dispatch on next turn of the Node event loop
    setImmediate(() => {
      try {
        this.emit(eventName, {
          event: eventName,
          payload,
          timestamp: new Date().toISOString()
        });
      } catch (err) {
        console.error(`[EventBus] Error in event '${eventName}':`, err.message);
      }
    });
  }
}
```

### 5.2 Decoupled Background Workers

Three autonomous workers subscribe to domain events upon system startup:
- **Audit Logger**: Listens to `*` (all events) and logs actor, entity ID, action, and timestamp.
- **Notification Dispatcher**: Listens to `task:created` and `task:completed`, simulating external dispatch to SMTP/Push endpoints without delaying client requests.
- **Analytics Aggregator**: Recomputes velocity and priority distribution upon `task:completed` and `task:deleted`.

### 5.3 Non-Blocking Controller Integration (`backend/src/controllers/taskController.js`)

When a user creates a task, the DB write executes, the HTTP response is returned immediately, and the event is dispatched asynchronously:

```javascript
// Database write
const task = await Task.create({ ... });

// Fire and forget asynchronous event dispatch
eventBus.publish('task:created', {
  taskId: task._id,
  title: task.title,
  priority: task.priority,
  userId: req.user._id
});

// Client receives instantaneous HTTP 201 response (~30ms)
return res.status(201).json({
  success: true,
  message: 'Task created successfully',
  data: task,
  asyncEventDispatched: 'task:created'
});
```

---

## 6. Empirical Benchmarks & Quantitative Evaluation

Testing was executed using the automated performance benchmark endpoint (`POST /tasks/benchmark/sync-vs-async`) and verified via `npm run test:p10`.

### 6.1 Benchmark Comparison Table

| Metric | Synchronous (Blocking Side-Effects) | Asynchronous (Event-Driven Pipeline) | Quantitative Improvement |
| :--- | :--- | :--- | :--- |
| **HTTP Response Latency** | **459.82 ms** | **33.21 ms** | **92.8% Reduction (13.8x Faster)** |
| **Client Blocking Time** | 459.82 ms | 33.21 ms | 426.61 ms saved per write |
| **Side Effects Execution** | In-band (Blocking) | Out-of-band (Worker Thread/Loop) | Decoupled & Isolated |
| **Error Blast Radius** | Listener error fails HTTP request | Listener error isolated to worker | Zero client disruption |
| **Throughput Capacity (req/s)**| ~2.1 req/sec per single worker | ~30.1 req/sec per single worker | **~14.3x Higher Throughput** |

### 6.2 Key Findings
1. **Client Responsiveness**: In the synchronous architecture, client response time was dominated by side-effects (~280ms email + ~45ms audit + ~100ms analytics = ~425ms overhead). In the EDA model, client latency dropped to only **33.21 ms** (a **92.8% speedup**).
2. **Decoupled Failure**: When an external notification service times out or fails, the user's task creation still succeeds flawlessly, preserving ACID integrity at the application boundary.
3. **Queue Scalability**: Long-running analytics reports that take 2-4 seconds no longer timeout browser connections, operating smoothly under HTTP 202 semantics.

---

## 7. Viva Voce Questions & Model Answers

### Question 1: What is Event-Driven Architecture (EDA) and why is it essential in modern web frameworks?
**Answer**:  
Event-Driven Architecture (EDA) is a software design pattern where application components communicate by emitting and reacting to state changes called "events" rather than invoking direct, tightly-coupled function calls. It is essential in modern web development because it decouples the core synchronous HTTP request-response cycle from auxiliary side-effects (such as audit logging, transaction notifications, search indexing, and real-time aggregations). This prevents slow external I/O from degrading client latency, enhances modularity, and facilitates horizontal scalability.

---

### Question 2: How does Node.js `EventEmitter` work internally, and is it synchronous or asynchronous by default?
**Answer**:  
Internally, Node.js `EventEmitter` maintains an internal hash map dictionary of event names mapped to arrays of callback listener functions. When `emit(eventName, data)` is called, `EventEmitter` iterates through the registered callback array **synchronously** in the order they were registered.  
To achieve true asynchronous, non-blocking execution, listeners must either wrap their execution inside `setImmediate()`, `process.nextTick()`, or `setTimeout()`, or return asynchronous promises. In our implementation, `eventBus.publish()` wraps emission in `setImmediate()` to ensure listeners run on the next turn of the Node.js event loop, preventing any listener from blocking the Express response thread.

---

### Question 3: What is the HTTP 202 Accepted status code and how does it implement the Asynchronous Request-Reply pattern?
**Answer**:  
`HTTP 202 Accepted` indicates that the client request has been accepted for processing, but processing has not yet completed and cannot be completed synchronously within the request lifespan.  
In the Asynchronous Request-Reply pattern:
1. The client sends a `POST` request to start a heavy job (e.g. data export).
2. The server creates an internal job entity, pushes it into a background processing queue, and immediately returns `HTTP 202 Accepted` containing a unique `jobId` and a polling status URI.
3. The client periodically polls (`GET /jobs/:id`) or listens via WebSockets/SSE to inspect progress (e.g., 0% -> 50% -> 100%) and retrieve the final artifact once the job transitions to `completed`.

---

### Question 4: How is error isolation maintained so that asynchronous listener crashes do not tear down the Node.js process?
**Answer**:  
By default in Node.js, if an `EventEmitter` instance emits an `'error'` event without at least one registered `'error'` listener, Node.js will throw an unhandled exception and crash the entire process. Furthermore, unhandled promise rejections inside async listeners can cause process termination.  
To isolate errors:
1. A dedicated `eventBus.on('error', (err) => ...)` listener is registered at initialization.
2. Each asynchronous listener wraps its internal logic in `try/catch` blocks.
3. Heavy background tasks log exceptions into a persistent error log or dead-letter queue without affecting other concurrent listeners or active HTTP transactions.

---

### Question 5: How does an in-process `EventEmitter` differ from distributed message brokers like RabbitMQ, Apache Kafka, or Redis Pub/Sub?
**Answer**:  
- **In-Process `EventEmitter`**: Operates entirely within the memory space of a single Node.js process. It has zero network latency, requires no external infrastructure, and is ideal for monolithic apps. However, events are lost if the process restarts (no persistence), and events cannot be shared across multiple horizontal cluster instances.
- **Distributed Message Brokers (RabbitMQ / Kafka / Redis Pub/Sub)**: External standalone message transport services. They support cross-service communication (microservices), message durability/persistence to disk, delivery acknowledgments (at-least-once, exactly-once), consumer groups, and horizontal load balancing across multiple server instances.

---

## 8. Verification & Test Output

The automated test script `node test_practical10_eda.js` verifies all functional requirements:

```text
=================================================================
🧪 Running Practical 10 Verification: Event-Driven Architecture
👤 Student: Vishvam Patel (ID: 24IT110) | CHARUSAT
=================================================================

  ✅ PASS: Registered & authenticated test user via JWT
  ✅ PASS: Reset EventBus logs for clean evaluation baseline
  ✅ PASS: Published 'task:created' event with non-blocking HTTP response (0.9 ms)
  ✅ PASS: Published 'task:completed' event to Notification & Metrics workers
  ✅ PASS: Decoupled EventBus recorded 3 emitted events across 3 active background workers
  ✅ PASS: Workers triggered: Audit Logger, Notification Dispatcher, Analytics Aggregator
  ✅ PASS: Asynchronous background job enqueued successfully with HTTP 202 Accepted (job-mvqs3dnl-xfg3)
  ✅ PASS: Job 'job-mvqs3dnl-xfg3' finished background execution (Progress: 100%, Artifact: ITUE301 Project & Telemetry Report)
  ✅ PASS: Sync vs. Async Benchmark: Synchronous=459.82ms vs. Asynchronous=33.21ms (92.8% faster response)

=================================================================
🎉 All Practical 10 Event-Driven Architecture Tests Passed!
=================================================================
```

---

## 9. Conclusion

Practical 10 successfully implemented an Event-Driven Architecture (EDA) in Node.js, fulfilling all educational course outcomes of ITUE301. By decoupling secondary side-effects (auditing, notification, metrics) from the main request loop, write latency was reduced from **459.82 ms** to **33.21 ms** (a **92.8% latency reduction**). The system demonstrates production-grade error isolation, asynchronous job queue processing with HTTP 202 Accepted semantics, and rich interactive UI monitoring.
