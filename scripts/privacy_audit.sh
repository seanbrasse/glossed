#!/bin/bash
# Privacy audit through the real stack (GLO-258, session 22): real accounts (auth API), writes through
# PostgREST + the app's RPCs, reads as every viewer. Stages: setup · looks · reads.
# Needs the local stack up. State lives in $GLOSSED_AUDIT_STATE (default /tmp).
# Clean up: delete the accounts' personal products first (products.created_by has
# no cascade), then `delete from auth.users where email like 'audit-%'`.
set +u
S=${GLOSSED_AUDIT_STATE:-${TMPDIR:-/tmp}/glossed-privacy-audit}; mkdir -p "$S"
API=http://127.0.0.1:54321
ANON=$(supabase status -o json 2>/dev/null | jq -r .PUBLISHABLE_KEY)
RUN=${RUN:-$(date +%H%M%S)}
C=supabase_db_glossed
psql() { docker exec -i $C psql -U postgres -At -c "$1"; }

signup() { # name email birth display
  local name=$1 email="$2-$RUN@local.test"
  local out; out=$(curl -s -m 15 -X POST "$API/auth/v1/signup" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$email\",\"password\":\"audit-pass-$RUN\"}")
  echo "$out" | jq -r .access_token > "$S/$name.jwt"; echo "$out" | jq -r .user.id > "$S/$name.uid"
  echo "$name: $(cat $S/$name.uid) ($email)"
}
jwt() { cat "$S/$1.jwt"; }
uid() { cat "$S/$1.uid"; }
# as <name|anon> <method> <rest path> [json] [prefer]
as() {
  local who=$1 m=$2 path=$3 body=${4:-} prefer=${5:-return=representation}
  local auth=(); [ "$who" != anon ] && auth=(-H "Authorization: Bearer $(jwt $who)")
  if [ -n "$body" ]; then
    curl -s -m 20 -X "$m" "$API/rest/v1/$path" -H "apikey: $ANON" "${auth[@]}" -H "Content-Type: application/json" -H "Prefer: $prefer" --data-binary "$body"
  else
    curl -s -m 20 -X "$m" "$API/rest/v1/$path" -H "apikey: $ANON" "${auth[@]}"
  fi
}
rpc() { as "$1" POST "rpc/$2" "$3" ""; }
fail() { echo "  !! $*"; }

if [ "${1:-setup}" = setup ]; then
  echo "=== accounts (run $RUN) ==="
  signup aria audit-aria; signup bea audit-bea; signup cal audit-cal; signup dee audit-dee; signup mia audit-mia; signup xan audit-xan
  echo "=== profiles ==="
  for who in aria bea cal dee xan; do
    as $who POST profiles "{\"user_id\":\"$(uid $who)\",\"birth_year_month\":\"1994-03\",\"display_name\":\"$who\",\"domains\":[\"skincare\",\"makeup\"],\"skin_type\":\"combo\",\"tone_band\":4,\"hair_pattern\":\"3b\"}" "return=minimal" | head -c 200
  done
  # mia is 14: a minor
  as mia POST profiles "{\"user_id\":\"$(uid mia)\",\"birth_year_month\":\"2012-05\",\"display_name\":\"mia\",\"domains\":[\"skincare\"]}" "return=minimal" | head -c 200
  echo "profiles: $(psql "select count(*) from profiles where display_name in ('aria','bea','cal','dee','xan','mia')")"
  echo "=== handles ==="
  for who in aria bea cal xan; do printf '%s -> ' $who; rpc $who claim_handle "{\"p_handle\":\"$who$RUN\"}" | head -c 120; echo; done
  printf 'mia (minor) -> '; rpc mia claim_handle "{\"p_handle\":\"mia$RUN\"}" | jq -c '.message // .' | head -c 160; echo
  echo "=== privacy scopes (aria public/public, bea friends/only_you, cal only_you, dee public, mia tries public, xan public) ==="
  scope() { as $1 POST privacy_scopes "{\"user_id\":\"$(uid $1)\",\"shelf\":\"$2\",\"rankings\":\"$3\",\"discoverable\":$4}" "resolution=merge-duplicates,return=minimal" | head -c 200; }
  scope aria public public true; scope bea friends only_you true; scope cal only_you only_you false; scope dee public public true; scope mia public public true; scope xan public public true
  echo "scopes on file: $(psql "select display_name||'='||s.shelf||'/'||s.rankings||'/'||s.discoverable from privacy_scopes s join profiles p using(user_id) where display_name in ('aria','bea','cal','dee','xan','mia') order by 1" | tr '\n' ' ')"
  echo "=== badges: aria opts in to all three ==="
  as aria POST profile_badges "{\"user_id\":\"$(uid aria)\",\"show_skin_type\":true,\"show_anchor\":true,\"show_hair_pattern\":true}" "resolution=merge-duplicates,return=minimal" | head -c 120
  echo "=== items ==="
  V_BLUSH=00508c3b-c623-4013-a7e7-0972b071f7cc; V_CLEANSER=0067f34f-b6d7-46f7-9207-26408abbd7c2; V_FOUNDATION=004f89b7-e642-4b98-8eb8-59f4cbdcdf7c; V_SERUM=00579bc2-2d38-4414-9326-7da0f936b293; V_SUN=00d4dce7-a0f1-4b7e-9f75-521c2c9e8f85; V_MOIST=001a4e6e-6a70-4147-9b12-4ec2517274e2
  item() { as $1 POST user_items "{\"user_id\":\"$(uid $1)\",\"variant_id\":\"$2\",\"status\":\"$3\",\"client_id\":\"$(uuidgen | tr A-Z a-z)\"}" | jq -r '.[0].id // ("ERR " + (.message // tostring))'; }
  A1=$(item aria $V_CLEANSER own); A2=$(item aria $V_SERUM own); A3=$(item aria $V_FOUNDATION own); A4=$(item aria $V_SUN want_to_try)
  B1=$(item bea $V_CLEANSER own); B2=$(item bea $V_MOIST own)
  C1=$(item cal $V_SERUM own)
  D1=$(item dee $V_BLUSH own); D2=$(item dee $V_CLEANSER own)
  M1=$(item mia $V_SUN own)
  X1=$(item xan $V_MOIST own)
  echo "aria items: $A1 $A2 $A3 (want_to_try $A4); bea: $B1 $B2; cal: $C1; dee: $D1 $D2; mia: $M1; xan: $X1"
  printf '%s\n' "$A1" "$A2" "$A3" "$A4" "$B1" "$B2" "$C1" "$D1" "$D2" "$M1" "$X1" > $S/items.txt
  echo "=== fit on aria's foundation (Regulated) ==="
  rpc aria capture_fit "{\"p_user_item_id\":\"$A3\",\"p_fits\":[\"just_right\"],\"p_season\":null}" | head -c 120; echo
  echo "=== rankings: aria ranks cleanser>serum in skincare category of each; dee too ==="
  CAT_CLEANSER=$(psql "select p.category_id from variants v join products p on p.id=v.product_id where v.id='$V_CLEANSER'")
  CAT_SERUM=$(psql "select p.category_id from variants v join products p on p.id=v.product_id where v.id='$V_SERUM'")
  rpc aria apply_face_off_session "{\"p_face_offs\":[{\"category_id\":\"$CAT_CLEANSER\",\"winner_item_id\":\"$A1\",\"loser_item_id\":\"$A2\",\"client_id\":\"$(uuidgen | tr A-Z a-z)\"}],\"p_positions\":[{\"category_id\":\"$CAT_CLEANSER\",\"user_item_id\":\"$A1\",\"position\":1},{\"category_id\":\"$CAT_SERUM\",\"user_item_id\":\"$A2\",\"position\":1}]}" | head -c 120
  rpc dee apply_face_off_session "{\"p_face_offs\":[],\"p_positions\":[{\"category_id\":\"$CAT_CLEANSER\",\"user_item_id\":\"$D2\",\"position\":1}]}" | head -c 120
  echo "rank rows: $(psql "select count(*) from rank_positions where user_id in ('$(uid aria)','$(uid dee)')")"
  echo "=== routines: aria public + only_you; bea friends; cal only_you ==="
  routine() { as $1 POST routines "{\"user_id\":\"$(uid $1)\",\"title\":\"$2\",\"slot\":\"$3\",\"cadence\":\"daily\",\"visibility\":\"$4\"}" | jq -r '.[0].id // ("ERR " + (.message // tostring))'; }
  RA1=$(routine aria "aria am public" am public); RA2=$(routine aria "aria pm private" pm only_you); RB1=$(routine bea "bea am friends" am friends); RC1=$(routine cal "cal am private" am only_you)
  as aria POST routine_steps "[{\"routine_id\":\"$RA1\",\"user_item_id\":\"$A1\",\"position\":1},{\"routine_id\":\"$RA2\",\"user_item_id\":\"$A2\",\"position\":1}]" "return=minimal" | head -c 120
  as bea POST routine_steps "[{\"routine_id\":\"$RB1\",\"user_item_id\":\"$B1\",\"position\":1}]" "return=minimal" | head -c 120
  echo "routines: $RA1 $RA2 $RB1 $RC1"; printf '%s\n' "$RA1" "$RA2" "$RB1" "$RC1" > $S/routines.txt
  echo "=== collections: aria public + only_you (items inside); bea friends; cal (shelf only_you) ONE public collection ==="
  coll() { as $1 POST collections "{\"user_id\":\"$(uid $1)\",\"title\":\"$2\",\"visibility\":\"$3\"}" | jq -r '.[0].id // ("ERR " + (.message // tostring))'; }
  KA1=$(coll aria "aria public kit" public); KA2=$(coll aria "aria private kit" only_you); KB1=$(coll bea "bea friends kit" friends); KC1=$(coll cal "cal public kit" public)
  as aria POST collection_items "[{\"collection_id\":\"$KA1\",\"user_item_id\":\"$A1\",\"position\":1},{\"collection_id\":\"$KA2\",\"user_item_id\":\"$A3\",\"position\":1}]" "return=minimal" | head -c 120
  as bea POST collection_items "[{\"collection_id\":\"$KB1\",\"user_item_id\":\"$B2\",\"position\":1}]" "return=minimal" | head -c 120
  as cal POST collection_items "[{\"collection_id\":\"$KC1\",\"user_item_id\":\"$C1\",\"position\":1}]" "return=minimal" | head -c 120
  echo "collections: $KA1 $KA2 $KB1 $KC1"; printf '%s\n' "$KA1" "$KA2" "$KB1" "$KC1" > $S/collections.txt
  echo "=== looks: aria public (published) + draft; bea friends (published); mia tries ==="
  look() { as $1 POST looks "{\"user_id\":\"$(uid $1)\",\"caption\":\"$2\",\"visibility\":\"$3\"}" | jq -r '.[0].id // ("ERR " + (.message // tostring))'; }
  LA1=$(look aria "aria public look" public); LA2=$(look aria "aria draft look" public); LB1=$(look bea "bea friends look" friends); LM=$(look mia "mia look" public)
  echo "mia's look insert (minor): $LM"
  as aria POST look_photos "[{\"look_id\":\"$LA1\",\"r2_key\":\"audit/aria1.jpg\",\"position\":1},{\"look_id\":\"$LA2\",\"r2_key\":\"audit/aria2.jpg\",\"position\":1}]" "return=minimal" | head -c 120
  as bea POST look_photos "[{\"look_id\":\"$LB1\",\"r2_key\":\"audit/bea1.jpg\",\"position\":1}]" "return=minimal" | head -c 120
  as aria PATCH "looks?id=eq.$LA1" '{"state":"public"}' "return=minimal" | head -c 120
  as bea PATCH "looks?id=eq.$LB1" '{"state":"public"}' "return=minimal" | head -c 120
  echo "looks: $LA1 (public) $LA2 (draft) $LB1 (friends public)"; printf '%s\n' "$LA1" "$LA2" "$LB1" > $S/looks.txt
  echo "look states: $(psql "select caption||':'||state||'/'||visibility from looks where caption like 'aria%' or caption like 'bea%' or caption like 'mia%' order by 1" | tr '\n' ' ')"
  echo "=== bio (aria), personal product (aria) ==="
  as aria POST public_texts "{\"user_id\":\"$(uid aria)\",\"kind\":\"bio\",\"body\":\"ranks everything, repurchases nothing\"}" "return=minimal" | head -c 120
  BRAND=$(psql "select id from brands order by name limit 1")
  rpc aria create_personal_product "{\"p_brand_id\":\"$BRAND\",\"p_category_id\":\"$CAT_SERUM\",\"p_domain\":\"skincare\",\"p_name\":\"aria secret serum $RUN\",\"p_gtin\":null,\"p_variant\":null}" | head -c 160; echo
  echo "=== graph: aria<->bea mutual; cal->aria one-way; xan blocks aria ==="
  as aria POST follows "{\"follower_id\":\"$(uid aria)\",\"followed_id\":\"$(uid bea)\"}" "return=minimal" | head -c 100
  as bea POST follows "{\"follower_id\":\"$(uid bea)\",\"followed_id\":\"$(uid aria)\"}" "return=minimal" | head -c 100
  as cal POST follows "{\"follower_id\":\"$(uid cal)\",\"followed_id\":\"$(uid aria)\"}" "return=minimal" | head -c 100
  as xan POST follows "{\"follower_id\":\"$(uid xan)\",\"followed_id\":\"$(uid aria)\"}" "return=minimal" | head -c 100
  as xan POST blocks "{\"user_id\":\"$(uid xan)\",\"blocked_id\":\"$(uid aria)\"}" "return=minimal" | head -c 100
  echo "follows on file: $(psql "select count(*) from follows where follower_id in (select user_id from profiles where display_name in ('aria','bea','cal','xan'))") (expect 3: xan's severed by the block)"
  echo "setup done (run $RUN)"; echo "$RUN" > $S/run.txt
fi

if [ "${1:-}" = looks ]; then
  RUN=$(cat $S/run.txt)
  look() { # insert the way the app does (id/user_id/caption), then visibility and state as their own updates
    local id; id=$(as $1 POST looks "{\"user_id\":\"$(uid $1)\",\"caption\":\"$2\"}" | jq -r '.[0].id // ("ERR " + (.message // tostring))')
    case "$id" in ERR*) echo "$id" >&2; echo ""; return;; esac
    as $1 PATCH "looks?id=eq.$id" "{\"visibility\":\"$3\"}" "return=minimal" >/dev/null
    echo "$id"
  }
  LA1=$(look aria "aria public look" public); LA2=$(look aria "aria draft look" public); LB1=$(look bea "bea friends look" friends); LM=$(look mia "mia look" public)
  echo "mia's look insert (minor, expect refused): '${LM:-refused}'"
  as aria POST look_photos "[{\"look_id\":\"$LA1\",\"r2_key\":\"audit/aria1.jpg\",\"position\":1},{\"look_id\":\"$LA2\",\"r2_key\":\"audit/aria2.jpg\",\"position\":1}]" "return=minimal" | head -c 200
  as bea POST look_photos "[{\"look_id\":\"$LB1\",\"r2_key\":\"audit/bea1.jpg\",\"position\":1}]" "return=minimal" | head -c 200
  as aria PATCH "looks?id=eq.$LA1" '{"state":"public"}' "return=minimal" | head -c 200
  as bea PATCH "looks?id=eq.$LB1" '{"state":"public"}' "return=minimal" | head -c 200
  printf '%s\n' "$LA1" "$LA2" "$LB1" > $S/looks.txt
  echo "look states: $(psql "select caption||':'||state||'/'||visibility from looks where caption like 'aria%' or caption like 'bea%' or caption like 'mia%' order by 1" | tr '\n' ' ')"
  echo "=== bio via set_public_text ==="; rpc aria set_public_text '{"p_kind":"bio","p_subject":null,"p_body":"ranks everything, repurchases nothing"}' | head -c 200; echo
  echo "bio state: $(psql "select kind||':'||state||':'||body from public_texts where user_id='$(uid aria)'")"
fi

if [ "${1:-}" = reads ]; then
  RUN=$(cat $S/run.txt); BAD=0
  count() { as "$1" GET "$2" | jq 'if type=="array" then length else ("ERR:" + (.message // tostring)) end' -r; }
  expect() { # label actual expected
    if [ "$2" != "$3" ]; then echo "  !! $1: got $2, expected $3"; BAD=$((BAD+1)); fi
  }
  in_list() { local f=$1; shift; paste -sd, "$f"; }
  ITEMS=$(paste -sd, $S/items.txt); ROUT=$(paste -sd, $S/routines.txt); COLL=$(paste -sd, $S/collections.txt); LOOKS=$(paste -sd, $S/looks.txt)
  # owner: what a STRANGER with an account sees (public scope); friends and blocks adjust below
  # aria: shelf public (3 own, wtt never), rankings public (2), routines 1 public, collections 1 public, looks 1 public
  # bea: friends (mutual with aria only): items 2, routine 1, collection 1, look 1 — to aria only
  # cal: only_you everywhere; ONE public collection with one item
  # dee: public scopes, NO handle: items 2, rank 1
  # mia: minor: nothing; xan: public: 1 item, nothing else; blocked <-> aria
  stranger() { # owner -> "items rank routines colls looks"
    case $1 in aria) echo "3 2 1 1 1";; bea) echo "0 0 0 0 0";; cal) echo "0 0 0 1 0";; dee) echo "2 1 0 0 0";; mia) echo "0 0 0 0 0";; xan) echo "1 0 0 0 0";; esac
  }
  self() { case $1 in aria) echo "4 2 2 2 2";; bea) echo "2 0 1 1 1";; cal) echo "1 0 1 1 0";; dee) echo "2 1 0 0 0";; mia) echo "1 0 0 0 0";; xan) echo "1 0 0 0 0";; esac; }
  expected() { # viewer owner
    local v=$1 o=$2
    if [ "$v" = "$o" ]; then self $o; return; fi
    if { [ "$v" = aria ] && [ "$o" = xan ]; } || { [ "$v" = xan ] && [ "$o" = aria ]; }; then echo "0 0 0 0 0"; return; fi
    if [ "$v" = aria ] && [ "$o" = bea ]; then echo "2 0 1 1 1"; return; fi   # mutual friends
    stranger $o
  }
  echo "=== matrix: items rank routines collections looks  (viewer → owner) ==="
  for v in aria bea cal dee mia xan anon; do
    for o in aria bea cal dee mia xan; do
      ou=$(uid $o)
      i=$(count $v "user_items?user_id=eq.$ou&select=id&deleted_at=is.null")
      r=$(count $v "rank_positions?user_id=eq.$ou&select=user_item_id")
      t=$(count $v "routines?user_id=eq.$ou&select=id")
      c=$(count $v "collections?user_id=eq.$ou&select=id")
      l=$(count $v "looks?user_id=eq.$ou&select=id")
      wtt=$(count $v "user_items?user_id=eq.$ou&status=eq.want_to_try&select=id")
      printf '%-5s → %-4s  %s %s %s %s %s   (wtt %s)\n' $v $o $i $r $t $c $l $wtt
      exp=$(expected $v $o); set -- $exp
      expect "$v→$o items" "$i" "$1"; expect "$v→$o rank" "$r" "$2"; expect "$v→$o routines" "$t" "$3"; expect "$v→$o collections" "$c" "$4"; expect "$v→$o looks" "$l" "$5"
      [ "$v" != "$o" ] && expect "$v→$o want_to_try leak" "$wtt" "0"
    done
  done
  echo "=== children: routine_steps / collection_items / look_photos / item_fits / face_offs (viewer sees, all owners) ==="
  for v in aria bea cal dee mia xan anon; do
    printf '%-5s steps %s  coll_items %s  photos %s  fits %s  face_offs %s\n' $v \
      "$(count $v "routine_steps?routine_id=in.($ROUT)&select=position")" \
      "$(count $v "collection_items?collection_id=in.($COLL)&select=position")" \
      "$(count $v "look_photos?look_id=in.($LOOKS)&select=id")" \
      "$(count $v "item_fits?user_item_id=in.($ITEMS)&select=user_item_id")" \
      "$(count $v "face_offs?user_id=in.($(for n in aria bea cal dee mia xan; do uid $n; done | paste -sd, -))&select=id")"
  done
  echo "=== never-public tables, as a stranger (bea) and anon, for every owner: profiles handles privacy_scopes badges public_texts blocks follows ==="
  for v in bea anon; do for o in aria cal dee mia xan; do
    ou=$(uid $o)
    p=$(count $v "profiles?user_id=eq.$ou&select=user_id"); h=$(count $v "handles?user_id=eq.$ou&select=handle"); s=$(count $v "privacy_scopes?user_id=eq.$ou&select=user_id"); b=$(count $v "profile_badges?user_id=eq.$ou&select=user_id"); t=$(count $v "public_texts?user_id=eq.$ou&select=id"); k=$(count $v "blocks?user_id=eq.$ou&select=user_id"); f=$(count $v "follows?or=(follower_id.eq.$ou,followed_id.eq.$ou)&select=follower_id")
    printf '%-4s → %-4s profiles %s handles %s scopes %s badges %s texts %s blocks %s follows %s\n' $v $o $p $h $s $b $t $k $f
    for pair in "profiles $p" "handles $h" "privacy_scopes $s" "badges $b" "public_texts $t" "blocks $k"; do set -- $pair; expect "$v→$o $1" "$2" "0"; done
    if [ "$v" = anon ] || [ "$o" != aria ]; then expect "$v→$o follows" "$f" "0"; fi
  done; done
  echo "=== public_profile(handle) as each viewer ==="
  for v in aria bea cal xan mia anon; do for o in aria bea xan; do
    printf '%-5s → %-4s ' $v $o; rpc $v public_profile "{\"p_handle\":\"$o$RUN\"}" | jq -c 'if type=="array" then (if length==0 then "no rows" else .[0] | {handle, badge_skin_type, badge_anchor, badge_hair_pattern, followers, following, shelf_n, ranked_lists_n, shelf_visible, rankings_visible, bio: (.bio|tostring|.[0:20])} end) else ("ERR:" + (.message // tostring)) end' -c
  done; done
  echo "=== a handle-less public owner (dee): public_profile by handle is impossible — but her rows are readable by user_id (see matrix) ==="
  echo "=== suggested_people as each viewer ==="
  for v in aria bea cal dee mia xan; do printf '%-5s: ' $v; rpc $v suggested_people '{"p_limit":10}' | jq -c 'if type=="array" then [.[] | {handle, reason, n}] else ("ERR:" + (.message // tostring)) end'; done
  echo "=== the personal product aria created: search_catalog as aria / bea / anon ==="
  for v in aria bea anon; do printf '%-5s: ' $v; rpc $v search_catalog "{\"q\":\"aria secret serum\",\"p_domain\":null}" | jq -c 'if type=="array" then [.[] | {name, scope}] else ("ERR:" + (.message // tostring)) end'; done
  echo "=== browse_routines(am) as cal (stranger) and anon: whose routines appear ==="
  for v in cal anon; do printf '%-5s: ' $v; rpc $v browse_routines '{"p_slot":"am","p_skin_type":null,"p_hair_pattern":null,"p_limit":20,"p_cursor":null}' | jq -c 'if type=="array" then [.[] | .title // .routine_title // keys] else ("ERR:" + (.message // tostring)) end' | head -c 400; echo; done
  echo "=== leaderboard(cleanser, all) as bea: rows and their n (min-n must hold) ==="
  CAT_CLEANSER=$(psql "select id from categories where slug='cleanser'")
  rpc bea leaderboard "{\"p_category\":\"$CAT_CLEANSER\",\"p_scope\":\"all\",\"p_ascending\":false,\"p_limit\":5}" | jq -c 'if type=="array" then [.[] | {n: (.n_face_offs // .n // .meets_min_n), name: (.name // .product_name)}] else ("ERR:" + (.message // tostring)) end' | head -c 300; echo
  echo "=== blocks: aria tries to follow xan; can_follow ==="
  printf 'can_follow(xan) as aria: '; rpc aria can_follow "{\"p_target\":\"$(uid xan)\"}"; echo
  printf 'aria inserts follow→xan: '; as aria POST follows "{\"follower_id\":\"$(uid aria)\",\"followed_id\":\"$(uid xan)\"}" "return=minimal" | jq -c '.message // .' 2>/dev/null; echo
  printf 'bea can_follow(aria): '; rpc bea can_follow "{\"p_target\":\"$(uid aria)\"}"; echo
  echo "=== minor: mia sets scopes (refused), posts a look (refused) — re-checked ==="
  printf 'mia scopes on file: '; psql "select shelf||'/'||rankings||'/'||discoverable from privacy_scopes where user_id='$(uid mia)'"
  echo "=== writes across owners: bea tries to update aria's item / collection / routine visibility ==="
  printf 'bea PATCH aria item: '; as bea PATCH "user_items?id=eq.$(sed -n 1p $S/items.txt)" '{"note":"pwned"}' "return=representation" | jq -c 'if type=="array" then length else (.message // .) end'
  printf 'bea PATCH aria collection→public: '; as bea PATCH "collections?id=eq.$(sed -n 2p $S/collections.txt)" '{"visibility":"public"}' "return=representation" | jq -c 'if type=="array" then length else (.message // .) end'
  printf 'bea PATCH aria look→public: '; as bea PATCH "looks?id=eq.$(sed -n 2p $S/looks.txt)" '{"state":"public"}' "return=representation" | jq -c 'if type=="array" then length else (.message // .) end'
  printf 'bea inserts a follow AS aria: '; as bea POST follows "{\"follower_id\":\"$(uid aria)\",\"followed_id\":\"$(uid cal)\"}" "return=minimal" | jq -c '.message // .' 2>/dev/null; echo
  echo "=== unfiltered scrape: anon lists user_items with no filter — how many rows, how many distinct owners ==="
  as anon GET "user_items?select=user_id&limit=1000" | jq -c 'if type=="array" then {rows: length, owners: ([.[].user_id]|unique|length)} else ("ERR:" + (.message // tostring)) end'
  as anon GET "rank_positions?select=user_id&limit=1000" | jq -c 'if type=="array" then {rank_rows: length, owners: ([.[].user_id]|unique|length)} else ("ERR:" + (.message // tostring)) end'
  echo; echo "=== UNEXPECTED cells: $BAD ==="
fi
