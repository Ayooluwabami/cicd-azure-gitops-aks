# node:20-alpine ships with a built-in 'node' user (uid 1000).
# We use it directly — no need to create an additional user.
FROM node:20-alpine AS runtime

WORKDIR /app

# Copy manifests first so Docker cache is invalidated only when deps change.
# Use npm ci (not npm install): ci requires package-lock.json, ensuring the
# exact dependency tree is reproducible across every build.
COPY package*.json ./
RUN npm ci --only=production

# Copy source after deps — preserves cache on source-only changes.
COPY --chown=node:node app.js .

# Drop to non-root.
# Reason: node:alpine's default user is root; running as 'node' (uid 1000)
# limits blast radius if the app process is compromised.
USER node

EXPOSE 3000

CMD ["node", "app.js"]
