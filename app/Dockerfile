FROM public.ecr.aws/docker/library/node:20-bookworm-slim

ARG NPM_CONFIG_REGISTRY=https://registry.npmjs.org/
ENV NPM_CONFIG_REGISTRY=${NPM_CONFIG_REGISTRY}

WORKDIR /app

COPY package*.json ./
RUN echo "registry=https://registry.npmjs.org/" > /root/.npmrc && \
    npm ci --omit=dev

COPY . .
RUN mkdir -p uploads

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "server.js"]