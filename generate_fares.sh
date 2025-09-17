#!/usr/bin/env bash
set -euo pipefail

OUTFILE="index.html"
TMP_APTS="airports.json"
TMP_FARES="fares.json"

# Minimal airports list for demo (replace with full Alaska Airlines codes)
cat > "$TMP_APTS" <<'JSON'
[
  {"code":"SEA","name":"Seattle-Tacoma Intl","state":"WA","lat":47.4502,"lon":-122.3088,"image":"https://upload.wikimedia.org/wikipedia/commons/9/95/Seattle-Tacoma_International_Airport_from_the_air.jpg"},
  {"code":"ANC","name":"Ted Stevens Anchorage Intl","state":"AK","lat":61.1743,"lon":-149.9982,"image":"https://upload.wikimedia.org/wikipedia/commons/8/8a/Ted_Stevens_Anchorage_International_Airport.jpg"}
]
JSON

current_year=$(date +%Y)
current_month=$(date +%m)

echo "[" > "$TMP_FARES"
first=1
jq -c '.[]' "$TMP_APTS" | while read -r ap; do
  code=$(jq -r '.code' <<<"$ap")
  name=$(jq -r '.name' <<<"$ap")
  state=$(jq -r '.state' <<<"$ap")
  lat=$(jq -r '.lat' <<<"$ap")
  lon=$(jq -r '.lon' <<<"$ap")
  image=$(jq -r '.image' <<<"$ap")

  fares_arr="["
  m=$current_month
  y=$current_year
  for i in $(seq 1 12); do
    price=$(shuf -i 150-600 -n 1)
    label=$(printf "%02d/%d" $m $y)
    fares_arr+="{\"month\":\"$label\",\"fare\":$price}"
    if [ $i -lt 12 ]; then fares_arr+=","; fi
    m=$((m+1))
    if [ $m -gt 12 ]; then m=1; y=$((y+1)); fi
  done
  fares_arr+="]"

  entry="{\"code\":\"$code\",\"name\":\"$name\",\"state\":\"$state\",\"lat\":$lat,\"lon\":$lon,\"image\":\"$image\",\"fares\":$fares_arr}"
  if [ $first -eq 1 ]; then
    echo "$entry" >> "$TMP_FARES"
    first=0
  else
    echo ",$entry" >> "$TMP_FARES"
  fi
done
echo "]" >> "$TMP_FARES"

# Build HTML
cat > "$OUTFILE" <<'HTML_HEAD'
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Fare Map</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet/dist/leaflet.css" />
  <style>html,body{height:100%;margin:0}#map{height:100%}.airport-image{width:100%;max-height:150px;object-fit:cover}</style>
</head>
<body><div id="map"></div>
<script src="https://unpkg.com/leaflet/dist/leaflet.js"></script>
<script>
const airports=
HTML_HEAD

cat "$TMP_FARES" >> "$OUTFILE"

cat >> "$OUTFILE" <<'HTML_FOOT';
;
const map=L.map('map').setView([47.5,-120],4);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{attribution:'&copy; OpenStreetMap'}).addTo(map);
airports.forEach(ap=>{
  let idx=0;
  const marker=L.marker([ap.lat,ap.lon]).addTo(map);
  function render(i){
    const f=ap.fares[i];
    return `<div><img src="${ap.image}" class="airport-image"/><b>${ap.name} (${ap.code})</b><br>${ap.state}<br><b>${f.month}</b>: $${f.fare}<br>
      <button onclick="prev()">Prev</button><button onclick="next()">Next</button></div>`;
  }
  function update(){marker.getPopup().setContent(render(idx));}
  function prev(){idx=(idx-1+ap.fares.length)%ap.fares.length;update();}
  function next(){idx=(idx+1)%ap.fares.length;update();}
  marker.bindPopup(render(idx));
});
</script>
</body></html>
HTML_FOOT
