FROM node

COPY frontend /opt/frontend

WORKDIR /opt/frontend

RUN npm i

EXPOSE 5173

CMD ["npm", "run", "dev-host"]
