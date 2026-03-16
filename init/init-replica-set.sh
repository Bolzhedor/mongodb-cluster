#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
# Ждём, пока mongo1 станет доступен
# ────────────────────────────────────────────────
echo "Ожидание mongo1 (${MONGO_ROOT_USER}) ..."

until mongosh --host mongo1:27017 \
  -u "${MONGO_ROOT_USER}" \
  -p "${MONGO_ROOT_PASSWORD}" \
  --authenticationDatabase admin \
  --quiet --eval "db.adminCommand('ping')" &>/dev/null; do
  echo "mongo1 ещё не готов... ждём 3 секунды"
  sleep 3
done

echo "mongo1 доступен → продолжаем"

# ────────────────────────────────────────────────
# Проверяем, инициализирован ли уже replica set
# ────────────────────────────────────────────────
if mongosh --host mongo1:27017 \
  -u "${MONGO_ROOT_USER}" \
  -p "${MONGO_ROOT_PASSWORD}" \
  --authenticationDatabase admin \
  --quiet --eval "rs.status()" &>/dev/null; then

  echo "Replica Set уже инициализирован → пропускаем rs.initiate"
else
  echo "Инициализируем Replica Set..."

  mongosh --host mongo1:27017 \
    -u "${MONGO_ROOT_USER}" \
    -p "${MONGO_ROOT_PASSWORD}" \
    --authenticationDatabase admin \
    --quiet <<EOF
rs.initiate({
  _id: "${REPLICA_SET_NAME}",
  members: [
    { _id: 0, host: "mongo1:27017", priority: 1 },
    { _id: 1, host: "mongo2:27017", priority: 0.5 },
    { _id: 2, host: "mongo3:27017", priority: 0.5 }
  ]
})
EOF

  echo "rs.initiate выполнен"
fi

# Ждём primary
echo "Ожидание primary..."
sleep 8

# ────────────────────────────────────────────────
# Создаём пользователя приложения (idempotentно)
# ────────────────────────────────────────────────
echo "Создаём / обновляем пользователя ${MONGO_APP_USER}..."

mongosh --host mongo1:27017 \
  -u "${MONGO_ROOT_USER}" \
  -p "${MONGO_ROOT_PASSWORD}" \
  --authenticationDatabase admin <<EOF
db = db.getSiblingDB("${MONGO_APP_DB}");

try {
  db.createUser({
    user: "${MONGO_APP_USER}",
    pwd: "${MONGO_APP_PASSWORD}",
    roles: [{ role: "readWrite", db: "${MONGO_APP_DB}" }]
  });
  print("Пользователь создан");
} catch (e) {
  if (e.codeName === "DuplicateKey" || e.errmsg.includes("already exists")) {
    print("Пользователь уже существует → пропускаем");
  } else {
    throw e;
  }
}
EOF

echo "Инициализация завершена успешно ✓"
exit 0
