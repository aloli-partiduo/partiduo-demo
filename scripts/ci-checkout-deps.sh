#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# shard.yml référence le cœur, l'interface et chaque extension composée
# (`../partiduo-<nom>`) ainsi que les shards maison (`../../prod-crystal/<nom>`) en
# `path:` tant qu'ils ne sont pas publiés. En CI, on les clone à ces
# emplacements, à côté du dépôt.
set -eu

cd "$(dirname "$0")/.."
base="${PARTIDUO_DEPS_BASE_URL:-https://github.com/aloli-crystal}"

for repo in partiduo-app partiduo-ui-bulma partiduo-document partiduo-einvoicing partiduo-superpdp \
  partiduo-esalink partiduo-choruspro partiduo-teledec partiduo-urssaf partiduo-crm partiduo-modeles; do
  if [ ! -d "../$repo" ]; then
    git clone --depth 1 --branch "${PARTIDUO_APP_BRANCH:-development}" "${PARTIDUO_REPOS_BASE_URL:-https://github.com/aloli-partiduo}/$repo.git" "../$repo"
  fi
done

../partiduo-app/scripts/ci-checkout-deps.sh
