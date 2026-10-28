# ==============================================================================
# Practical 11: Containerization with Docker and Docker Compose
# Service: Frontend Single Page Application (React 19 + Vite)
# Student: Vishvam Patel (24IT110) | CHARUSAT - ITUE301
# ==============================================================================

# Stage 1: Build Static Production Assets
FROM node:20-alpine AS builder

WORKDIR /usr/src/app

# Copy package manifests for Docker layer caching
COPY package*.json ./

# Install dependencies cleanly
RUN npm ci

# Copy application source code
COPY . .

# Build production assets (Vite Rolldown bundle)
RUN npm run build

# ==============================================================================
# Stage 2: Serve with Lightweight Production Nginx
FROM nginx:1.27-alpine

# Set container environment metadata
ENV DOCKER_CONTAINER=true \
    NGINX_PORT=80

# Remove default Nginx welcome page
RUN rm -rf /usr/share/nginx/html/*

# Copy compiled SPA bundle from builder stage
COPY --from=builder /usr/src/app/dist /usr/share/nginx/html

# Copy optimized Nginx reverse proxy configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose HTTP port 80
EXPOSE 80

# Container Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/health || exit 1

# Start Nginx in foreground mode
CMD ["nginx", "-g", "daemon off;"]
