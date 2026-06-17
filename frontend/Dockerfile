# ──────────────────────────────────────────────────────────────
# Ignisia26 — React/Vite frontend (built static SPA served by nginx)
# Build:  docker build -t ignisia26-frontend ./frontend \
#           --build-arg VITE_SUPABASE_URL=... \
#           --build-arg VITE_SUPABASE_ANON_KEY=...
# ──────────────────────────────────────────────────────────────

# ---- Stage 1: build the static bundle ----
FROM node:20-alpine AS build

WORKDIR /app

# Vite inlines VITE_* vars at BUILD time, so they must be passed as build args.
ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_ANON_KEY
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL
ENV VITE_SUPABASE_ANON_KEY=$VITE_SUPABASE_ANON_KEY

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# ---- Stage 2: serve with nginx ----
FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
