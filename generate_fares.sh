#!/usr/bin/env bash
# generate_fares.sh
# Build an interactive Alaska Airlines fare map
set -euo pipefail

OUTFILE="index.html"

# --- STEP 1: Airport data (sample subset of Alaska Airlines airports) ---
cat > airports.json <<'JSON'
[
  {"code": "SEA", "name": "Seattle-Tacoma Intl", "state": "WA", "lat": 47.4502, "lon": -122.3088, "image": "https://upload.wikimedia.org/wikipedia/commons/thumb/9/95/Seattle-Tacoma_International_Airport_from_the_air.jpg/320px-Seattle-Tacoma_International_Airport_from_the_air.jpg"},
  {"code": "ANC", "name": "Ted Stevens Anchorage Intl", "state": "AK", "lat": 61.1743, "lon": -149.9982, "image": "https://upload.wikimedia.org/wikipedia/commons/thumb/8/8a/Ted_Stevens_Anchorage_International_Airport.jpg/320px-Ted_Stevens_Anchorage_International_Airport.jpg"},
  {"code": "LAX", "name": "Los Angeles Intl", "state": "CA", "lat": 33.9416, "lon": -118.4085, "image": "https://upload.wikimedia.org/wikipedia/commons/thumb/5/57/LAX_airport_sign.jpg/320px-LAX_airport_sign.jpg"},
  {"code": "PDX", "name": "Portland Intl", "state": "OR", "lat": 45.5898, "lon": -122.5951, "image": "https://upload.wikimedia.org/wikipedia/commons/thumb/8/86/Portland_International_Airport%2C_Oregon.JPG/320px-Portland_International_Airport%2C_Oregon.JPG"},
  {"code": "JNU", "name": "Juneau Intl", "state": "AK", "lat": 58.3549, "lon": -134.5763, "image": "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d0/Juneau_Airport.jpg/320px-Juneau_Airport.jpg"}
]
JSON

# --- STEP 2: Generate fake fare data in Bash ---
echo "[" > fares.json
first=1
jq -c '.[]' airports.json | while read -r ap; do
  code=$(jq -r '.code' <<<"$ap")
  name=$(jq -r '.name' <<<"$ap")
  state=$(jq -r '.state' <<<"$ap")
  lat=$(jq -r '.lat' <<<"$ap")
  lon=$(jq -r '.lon' <<<"$ap")
  image=$(jq -r '.image' <<<"$ap")

  # generate 12 months of fares (random 200–500)
  fares="["
  for m in $(seq 1 12); do
    price=$(shuf -i 200-500 -n 1)
    fares+="{\"month\":$m,\"fare\":$price},"
  done
  fares="${fares%,}]"

  entry="{\"code\":\"$code\",\"name\":\"$name\",\"state\":\"$state\",\"lat\":$lat,\"lon\":$lon,\"image\":\"$image\",\"fares\":$fares}"
  if [ $first -eq 1 ]; then
    echo "$entry" >> fares.json
    first=0
  else
    echo ",$entry" >> fares.json
  fi
done
echo "]" >> fares.json

# --- STEP 3: Build HTML ---
cat > "$OUTFILE" <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Alaska Airlines Fare Map</title>
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet/dist/leaflet.css" />
  <style>
    html,body { height:100%; margin:0; }
    #map { height:100vh; width:100%; }
    .popup { font-family: Arial, sans-serif; font-size: 14px; }
    .fare-grid { display:grid; grid-template-columns: repeat(4,1fr); gap:4px; margin-top:6px; }
    .fare { padding:4px; background:#f0f0f0; border-radius:4px; text-align:center; }
  </style>
</head>
<body>
  <div id="map"></div>

  <script src="https://unpkg.com/leaflet/dist/leaflet.js"></script>
  <script>
    var map = L.map('map').setView([47.5, -120], 4);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);

    var airports = 
HTML_HEAD

cat fares.json >> "$OUTFILE"

cat >> "$OUTFILE" <<'HTML_FOOT';
    ;

    airports.forEach(ap => {
      var marker = L.marker([ap.lat, ap.lon]).addTo(map);
      var fareHtml = '<div class="popup">'
        + '<img src="'+ap.image+'" style="width:100%;border-radius:6px;margin-bottom:6px"/>'
        + '<b>'+ap.name+' ('+ap.code+')</b><br/>'+ap.state
        + '<div class="fare-grid">';
      ap.fares.forEach(f => {
        fareHtml += '<div class="fare">'+f.month+'/2025<br><b>$'+f.fare+'</b></div>';
      });
      fareHtml += '</div></div>';
      marker.bindPopup(fareHtml, {maxWidth: 300});
    });
  </script>
</body>
</html>
HTML_FOOT

echo "Wrote $OUTFILE with $(jq length fares.json) airports."
