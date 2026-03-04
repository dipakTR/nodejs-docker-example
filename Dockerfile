# Stage 1
FROM node:20-alpine as builder

WORKDIR /build

COPY package*.json ./
RUN npm ci --only=production

COPY src/ src/
COPY tsconfig.json .

RUN npm install typescript
RUN npm run build

# Stage 2
FROM node:20-alpine as runner

# Install curl for health check
RUN apk --no-cache add curl

WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodeuser -u 1001

COPY --from=builder --chown=nodeuser:nodejs /build/package*.json ./
COPY --from=builder --chown=nodeuser:nodejs /build/node_modules ./node_modules/
COPY --from=builder --chown=nodeuser:nodejs /build/dist ./dist/

USER nodeuser

EXPOSE 8000

# Add health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["npm", "start"]
