#!/usr/bin/env bash
# EVO-1999 — Roda migrations no boot da imagem, em QUALQUER orquestrador.
#
# Motivo: plataformas como o CapRover deployam apenas pela imagem e sobem o
# container com o ENTRYPOINT/CMD da imagem, IGNORANDO o `command:`/`entrypoint:`
# do docker-compose (onde hoje o db:migrate acontece). Sem isto, cada atualização
# de imagem deixa migrations pendentes e o web sobe com schema desatualizado
# (ex.: 500 em rotas que dependem de colunas novas).
#
# Gate RUN_MIGRATIONS (default 'true' = fail-safe: nunca sobe com schema velho).
# Defina RUN_MIGRATIONS=false nos serviços *-sidekiq para não migrar em duplicado.
# O db:migrate do Rails usa advisory lock do Postgres, então é seguro mesmo que
# mais de um processo tente migrar ao mesmo tempo.
set -e

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
  echo "[evo-auth-entrypoint] Preparando banco (db:create + db:migrate)..."
  n=0
  until [ "$n" -ge 30 ]; do
    if bundle exec rails db:create db:migrate; then
      echo "[evo-auth-entrypoint] Migrations aplicadas."
      break
    fi
    n=$((n + 1))
    echo "[evo-auth-entrypoint] banco indisponível ou migrate falhou — tentativa ${n}/30; aguardando 2s..."
    sleep 2
  done
  if [ "$n" -ge 30 ]; then
    echo "[evo-auth-entrypoint] AVISO: migrations não concluídas após 30 tentativas; seguindo o boot."
  fi
else
  echo "[evo-auth-entrypoint] RUN_MIGRATIONS=${RUN_MIGRATIONS} — pulando migrations."
fi

exec "$@"
