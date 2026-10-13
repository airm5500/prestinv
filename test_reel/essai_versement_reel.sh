#!/bin/bash
# Essai réel « création d'inventaire + versement de la collecte » contre un serveur Prestige de TEST,
# avec instantané de la base avant / après et suppression de l'inventaire de test.
# Usage (sur la machine du serveur de test, accès mysql local) :
#   PRESTINV_REEL_MDP=... MYSQL="mysql laborex" bash test_reel/essai_versement_reel.sh
# Variables : PRESTINV_REEL_HOTE (localhost), PRESTINV_REEL_PORT (8080), PRESTINV_REEL_LOGIN (admin),
#   PRESTINV_REEL_CODES (code:quantité,… dont un inconnu), PRESTINV_REEL_CIP_SECOURS (CIP pour l'import CSV
#   de secours si la création est impossible sur ce serveur).
set -u
cd "$(dirname "$0")/.."
MYSQL=${MYSQL:-mysql laborex}
HOTE=${PRESTINV_REEL_HOTE:-localhost}
PORT=${PRESTINV_REEL_PORT:-8080}
LOGIN=${PRESTINV_REEL_LOGIN:-admin}
CODES=${PRESTINV_REEL_CODES:-3000000258453:5,8438629:2,1234567890128:3}
SECOURS=${PRESTINV_REEL_CIP_SECOURS:-8050457,8438629,8521508}
TMP=$(mktemp -d)

etat() {
  $MYSQL -N -e "select 'inventaires', count(*) from t_inventaire; select 'lignes', count(*) from t_inventaire_famille;
    select 'auto_increment', auto_increment from information_schema.tables where table_schema=database() and table_name='t_inventaire_famille';
    checksum table t_inventaire, t_inventaire_famille;"
}
etat > "$TMP/avant.txt"
AI=$(awk '$1=="auto_increment"{print $2}' "$TMP/avant.txt")

flutter test test_reel/essai_versement_reel_test.dart -r expanded \
  --dart-define=PRESTINV_REEL_HOTE="$HOTE" --dart-define=PRESTINV_REEL_PORT="$PORT" \
  --dart-define=PRESTINV_REEL_LOGIN="$LOGIN" --dart-define=PRESTINV_REEL_MDP="${PRESTINV_REEL_MDP:?mot de passe requis}" \
  --dart-define=PRESTINV_REEL_CODES="$CODES" --dart-define=PRESTINV_REEL_CIP_SECOURS="$SECOURS" 2>&1 | tee "$TMP/essai.txt"
RESULTAT=${PIPESTATUS[0]}

for ID in $(grep -o 'ESSAI-INVENTAIRE [^ ]*' "$TMP/essai.txt" | awk '{print $2}' | sort -u); do
  echo "--- Inventaire de test $ID : lignes comptées (auteur enregistré par le serveur)"
  $MYSQL -e "select f.lg_INVENTAIRE_FAMILLE_ID, t.int_CIP, f.int_NUMBER_INIT, f.int_NUMBER, f.dt_UPDATED, f.str_UPDATED_ID, u.str_LOGIN
      from t_inventaire_famille f join t_famille t on t.lg_FAMILLE_ID=f.lg_FAMILLE_ID left join t_user u on u.lg_USER_ID=f.str_UPDATED_ID
      where f.lg_INVENTAIRE_ID='$ID' and f.dt_UPDATED is not null"
  echo "--- Suppression de l'inventaire de test $ID"
  $MYSQL -e "DELETE FROM t_inventaire_famille WHERE lg_INVENTAIRE_ID='$ID'; DELETE FROM t_inventaire WHERE lg_INVENTAIRE_ID='$ID';"
done
[ -n "$AI" ] && $MYSQL -e "ALTER TABLE t_inventaire_famille AUTO_INCREMENT = $AI"
etat > "$TMP/apres.txt"
echo "--- Base avant / après"
paste "$TMP/avant.txt" "$TMP/apres.txt"
if diff -q "$TMP/avant.txt" "$TMP/apres.txt" >/dev/null; then echo "BASE REVENUE À L'ÉTAT INITIAL"; else echo "ÉCART DANS LA BASE"; RESULTAT=1; fi
rm -rf "$TMP"
exit $RESULTAT
