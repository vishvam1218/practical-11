# Practical 11: Containerization with Docker and Docker Compose

**Course**: Advanced Web Development Frameworks (ITUE301)  
**Student Name**: Vishvam Patel  
**Student ID**: 24IT110  
**Department**: Information Technology / Computer Science / AIML  
**Institution**: CSPIT / DEPSTAR, Charotar University of Science and Technology (CHARUSAT)  

---

## 1. Practical Title & Subject Code

- **Practical Title**: Full-Stack Multi-Container Application Orchestration using Docker and Docker Compose
- **Subject Code**: ITUE301 (Advanced Web Development Frameworks)
- **Course Outcomes (COs)**: CO2 (Develop scalable and deployable server-side architectures), CO4 (Implement DevOps containerization and microservice orchestration) / PO3, PO5

---

## 2. Aim & Objectives

### Aim
To containerize a full-stack modern web application (React 19 SPA, Node.js/Express REST API, and MongoDB 7.0 database) using production-optimized multi-stage Dockerfiles and orchestrate multi-service networking and volume persistence using Docker Compose.

### Key Objectives
1. **Multi-Stage Build Optimization**:
   - Architect a multi-stage `backend/Dockerfile` that separates the dependency build toolchain (`make`, `g++`, `python3`) from the minimal production execution image (`node:20-alpine`).
   - Architect a multi-stage `frontend/Dockerfile` compiling the React 19 application via Vite and serving production static assets via an ultra-lightweight Nginx container (`nginx:1.27-alpine`).
2. **Container Security & Reliability**:
   - Enforce non-root execution (`USER node`) in the Node.js backend to prevent container escape vulnerabilities.
   - Integrate `dumb-init` as PID 1 to properly handle signal forwarding (`SIGTERM`, `SIGINT`) and reap zombie child processes.
   - Configure container `HEALTHCHECK` directives across all services.
3. **Multi-Container Orchestration (`docker-compose.yml`)**:
   - Declare a 3-tier topology: `frontend` (Nginx), `backend` (Express REST API), and `mongo` (MongoDB 7.0).
   - Configure container startup dependencies using `depends_on` with `condition: service_healthy` to prevent race conditions during database initialization.
4. **Isolated Bridge Networking & Service Discovery**:
   - Create a dedicated user-defined bridge network (`awdf-network`) enabling inter-container DNS name resolution without hardcoding IP addresses.
5. **Persistent Data Storage**:
   - Provision a Docker named volume (`mongo-data`) mapped to `/data/db` ensuring database records persist across container restarts, teardowns, and image updates.
6. **Reverse Proxy Configuration**:
   - Write custom `nginx.conf` providing reverse proxy routing for `/api/`, `/tasks/`, `/auth/`, and `/container/` while supporting React Router SPA fallback (`try_files $uri $uri/ /index.html;`).
7. **Automated Verification**:
   - Build an automated test suite (`npm run test:p11`) auditing Dockerfile layers, compose specifications, and container telemetry endpoints.

---

## 3. Technologies & Tools

- **Containerization Engine**: Docker Engine (OCI compliant)
- **Orchestration Tool**: Docker Compose v2 (Compose Specification v3.8)
- **Base Images**:
  - `node:20-alpine` (Node.js LTS runtime on Alpine Linux)
  - `nginx:1.27-alpine` (Lightweight HTTP & Reverse Proxy Server)
  - `mongo:7.0-jammy` (Official MongoDB NoSQL Database)
- **Security & Process Management**: `dumb-init` (PID 1 supervisor), Linux user namespaces
- **Reverse Proxy**: Nginx with Gzip compression and security headers
- **Full Stack Web Application**:
  - React 19, Vite v8, Vanilla CSS Glassmorphism
  - Node.js, Express.js (v4.19.2), Mongoose (v8.24.2), JWT, node-cache, EventEmitter
- **Verification Runner**: Node.js `test_practical11_docker.js`

---

## 4. Multi-Container Architecture & Network Topology

```text
                                  CLIENT WEB BROWSER
                                          │
                                          │ HTTP (Port 5174:80)
                                          ▼
                      ┌───────────────────────────────────────┐
                      │             awdf-frontend             │
                      │          (nginx:1.27-alpine)          │
                      │  - Serves compiled React 19 SPA       │
                      │  - Gzip compression & security headers│
                      │  - Reverse proxy /api & /tasks routes │
                      └───────────────────┬───────────────────┘
                                          │
                         awdf-bridge-network (Internal Docker DNS)
                         http://backend:5001/
                                          │
                                          ▼
                      ┌───────────────────────────────────────┐
                      │             awdf-backend              │
                      │           (node:20-alpine)            │
                      │  - Express.js REST API Pipeline       │
                      │  - Non-root user: node                │
                      │  - Signal supervisor: dumb-init       │
                      │  - In-Memory Cache + EDA EventBus     │
                      └───────────────────┬───────────────────┘
                                          │
                         awdf-bridge-network (Internal Docker DNS)
                         mongodb://mongo:27017/taskmanager
                                          │
                                          ▼
                      ┌───────────────────────────────────────┐
                      │             awdf-mongodb              │
                      │          (mongo:7.0-jammy)            │
                      │  - NoSQL Document Store               │
                      │  - Healthcheck via mongosh ping       │
                      └───────────────────┬───────────────────┘
                                          │
                                   Volume Mount
                                          │
                                          ▼
                      ┌───────────────────────────────────────┐
                      │          awdf-mongo-storage           │
                      │        (Docker Named Volume)          │
                      │  - Bound to /data/db                  │
                      │  - Persistent ACID Storage on Host    │
                      └───────────────────────────────────────┘
```

---

## 5. Implementation Analysis

### 5.1 Multi-Stage Dockerfile Strategy

#### Backend Multi-Stage Build (`backend/Dockerfile`):
- **Stage 1 (`builder`)**: Installs native build tools (`python3`, `make`, `g++`) to build any compiled C++ Node bindings, then executes `npm ci --only=production`.
- **Stage 2 (`runtime`)**: Copies solely `node_modules` and source files into a clean `node:20-alpine` base. Build tools and dev dependencies are completely omitted.
- **Security & Signal Forwarding**: Switched to `USER node` and wrapped launch in `dumb-init`.

#### Frontend Multi-Stage Build (`frontend/Dockerfile`):
- **Stage 1 (`builder`)**: Uses `node:20-alpine` to install dependencies and run `npm run build` (generating the production `/dist` bundle).
- **Stage 2 (`nginx`)**: Uses `nginx:1.27-alpine` (~25 MB total). Discards Node.js runtime entirely. Copies static assets to `/usr/share/nginx/html` and mounts custom `nginx.conf`.

### 5.2 Nginx Reverse Proxy & Client Routing (`frontend/nginx.conf`)

To prevent 404 errors when reloading React Router paths (e.g. `/projects` or `/contact`), Nginx is configured with SPA fallback:
```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```
Furthermore, backend endpoints are transparently proxied using Docker internal DNS:
```nginx
location /api/ {
    proxy_pass http://backend:5001/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

### 5.3 Docker Compose Orchestrator (`docker-compose.yml`)

The declarative specification configures:
1. **Ordered Initialization**: The backend container pauses until the MongoDB healthcheck confirms the database is responsive:
   ```yaml
   depends_on:
     mongo:
       condition: service_healthy
   ```
2. **Persistence**:
   ```yaml
   volumes:
     mongo-data:
       driver: local
       name: awdf-mongo-storage
   ```
3. **Bridge Network**:
   ```yaml
   networks:
     awdf-network:
       driver: bridge
       name: awdf-bridge-network
   ```

---

## 6. Verification & Automated Test Output

The automated test script `node test_practical11_docker.js` verifies all container files, multi-stage syntax, Compose network configurations, and API endpoints:

```text
=================================================================
🧪 Running Practical 11 Verification: Docker & Docker Compose
👤 Student: Vishvam Patel (ID: 24IT110) | CHARUSAT
=================================================================

  ✅ PASS: Backend Dockerfile implements Multi-Stage build (node:20-alpine)
  ✅ PASS: Backend Dockerfile enforces non-root security isolation (USER node)
  ✅ PASS: Backend Dockerfile includes PID 1 signal forwarding (dumb-init) & container HEALTHCHECK
  ✅ PASS: Backend .dockerignore protects build context (excludes node_modules & secrets)
  ✅ PASS: Frontend Dockerfile implements Multi-Stage build (Vite Builder ➔ Nginx Alpine)
  ✅ PASS: Frontend nginx.conf configures SPA fallback routing & Docker internal DNS reverse proxy
  ✅ PASS: docker-compose.yml defines 3-Tier Multi-Container Stack (mongo, backend, frontend)
  ✅ PASS: docker-compose.yml provisions isolated custom bridge network (awdf-network)
  ✅ PASS: docker-compose.yml mounts persistent named volume for MongoDB ACID durability
  ✅ PASS: docker-compose.yml enforces startup order dependency checks (condition: service_healthy)
  ✅ PASS: GET /container/info responded in 35.11 ms with complete orchestration metadata
  ✅ PASS: Container Host: Vishvams-MacBook-Air.local | Arch: arm64 | Platform: darwin
  ✅ PASS: Memory Heap: 19.35 MB / 21.33 MB (Uptime: 10m 42s)
  ✅ PASS: Orchestration: 3 services configured on awdf-bridge-network (Driver: bridge)

=================================================================
🎉 All Practical 11 Containerization Tests Passed Successfully!
=================================================================
```

---

## 7. Viva Voce Questions & Model Answers

### Question 1: What is the core difference between Virtual Machines (VMs) and Docker Containers?
**Answer**:  
Virtual Machines (VMs) virtualize physical hardware via a Hypervisor (Type 1 bare-metal or Type 2 hosted) and execute an entire guest operating system with dedicated virtual hardware drivers and kernel. This results in heavy image sizes (several gigabytes), significant RAM consumption, and minute-long boot times.  
Docker Containers virtualize at the operating system kernel level using Linux namespaces (PID, NET, IPC, MNT, UTS) for process isolation and cgroups for CPU and memory resource limiting. All containers share the host Linux kernel, package only application binaries and libraries, boot in milliseconds, and consume minimal system overhead.

---

### Question 2: What is a Multi-Stage Docker build and why is it critical for React and Node.js microservices?
**Answer**:  
A Multi-Stage Docker build utilizes multiple `FROM` instructions within a single Dockerfile, allowing intermediate stages to build code and pass artifacts to subsequent stages.  
In our frontend container, Stage 1 uses `node:20-alpine` to install full dependencies and compile the React 19 SPA via Vite. Stage 2 copies *only* the compiled `/dist` directory into an ultra-lean `nginx:1.27-alpine` web server image, completely discarding the Node.js runtime and devDependencies. This reduces the production container size from ~1.2 GB to ~25 MB, reduces network deployment bandwidth, and eliminates potential compiler vulnerabilities from production containers.

---

### Question 3: How does Docker Compose handle service discovery and inter-container networking?
**Answer**:  
When services are defined in `docker-compose.yml`, Docker Compose automatically creates an isolated user-defined bridge network (e.g. `awdf-bridge-network`). Docker runs an embedded DNS server at IP `127.0.0.11`. Whenever a container resolves a service hostname (such as `mongo` or `backend`), the Docker DNS server automatically translates it into that container's internal bridge IP. This eliminates the need for hardcoded IP addresses or legacy `--link` flags and ensures seamless communication across microservices.

---

### Question 4: Why are Docker Named Volumes mandatory for persistent database containers (MongoDB)?
**Answer**:  
Docker container filesystems use a temporary Union File System (UnionFS) layer. When a container is stopped and removed (`docker rm` or `docker-compose down`), all data written to the container's writable layer is permanently lost.  
Named volumes (such as `awdf-mongo-storage:/data/db`) are managed directly by Docker outside of the container's storage driver on the host filesystem. They decouple persistent database state from the ephemeral container lifecycle, guaranteeing that NoSQL collections survive container crashes, restarts, and image updates.

---

### Question 5: What is the purpose of `dumb-init` and running as non-root (`USER node`) in production Dockerfiles?
**Answer**:  
1. **Security**: By default, Docker executes processes as `root` (UID 0). If an application vulnerability allows Remote Code Execution, an attacker possesses root privileges on the container. Using `USER node` restricts permissions and conforms to the Principle of Least Privilege.
2. **Signal Handling**: Node.js is not designed to run as Linux PID 1 (init process). It does not forward system signals (`SIGTERM`, `SIGINT`) to child processes and does not reap zombie child processes. Running `dumb-init` as PID 1 ensures that when Docker issues `docker stop`, `SIGTERM` is cleanly forwarded to Express, allowing the server to close active database connections and shut down gracefully without waiting for a 10-second `SIGKILL` timeout.

---

## 8. Conclusion

Practical 11 successfully implemented containerization and multi-container orchestration for the ITUE301 application stack. By creating production multi-stage Dockerfiles for both frontend (Nginx) and backend (Node.js) and orchestrating them alongside MongoDB via Docker Compose, the application achieves consistent development and production parity, zero-configuration microservice discovery, persistent data durability, and production-grade container security.
