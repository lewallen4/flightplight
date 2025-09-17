#!/usr/bin/env bash
# generate_fares_full.sh
set -euo pipefail

# You might need jq, curl, and optionally a tool to parse html or use wiki API
# Assumes API_NINJAS_KEY for Airports API if used

OUTFILE="index.html"
TMP_APTS="airports_full.json"
TMP_FARES="fares_full.json"

# 1. Get Alaska Airlines destinations list (airport codes) manually or via scraping
#    For simplicity, use a hardcoded list or you could scrape Wikipedia.
#    E.g., extract IATA codes from the Wikipedia “List of Alaska Airlines destinations”
#    We'll hardcode a sample for demo; you can fill in all.

AIRPORT_CODES=(SEA ANC LAX PDX JNU YVR YEG SFO ... )  # add all you want

# 2. For each code, fetch airport metadata: lat, lon, name, state, image URL
#    Use Airports API (api-ninjas) or Wikipedia.

echo "[" > "$TMP_APTS"
first=1
for code in "${AIRPORT_CODES[@]}"; do
  # fetch metadata
  # Example with API Ninjas:
  resp=$(curl -s "https://api.api-ninjas.com/v1/airports?iata=$code" -H "X-Api-Key=$API_NINJAS_KEY")
  # If response empty, try fallback
  name=$(jq -r '.[0].name // empty' <<< "$resp")
  state=$(jq -r '.[0].state // empty' <<< "$resp")
  lat=$(jq -r '.[0].latitude // empty' <<< "$resp")
  lon=$(jq -r '.[0].longitude // empty' <<< "$resp")
  # image: try Wikipedia API
  # Query wiki page for the airport
  wiki_img=$(curl -s "https://en.wikipedia.org/w/api.php?action=query&prop=pageimages&format=json&piprop=original&titles=$code%20Airport" | jq -r '.query.pages[]?.original.source // empty')
  if [ -z "$wiki_img" ]; then
    # fallback generic or placeholder
    wiki_img="https://via.placeholder.com/320x180?text=$code"
  fi

  # build JSON entry
  entry=$(jq -nc --arg code "$code" --arg name "$name" --arg state "$state" --arg lat "$lat" --arg lon "$lon" --arg img "$wiki_img" \
    '{code: $code, name: $name, state: $state, lat: ($lat|tonumber), lon: ($lon|tonumber), image: $img}')
  if [ $first -eq 1 ]; then
    echo "$entry" >> "$TMP_APTS"
    first=0
  else
    echo ",$entry" >> "$TMP_APTS"
  fi
done
echo "]" >> "$TMP_APTS"

# 3. Generate fares data for a rolling next 12 months starting from current date
#    e.g., if today is Sept 2025, then Sept2025 to Aug2026

current_year=$(date +%Y)
current_month=$(date +%m)  # e.g. “09”

# Helper function: increment month/year
next_month_year() {
  m=$1; y=$2
  m=$((m+1))
  if [ $m -gt 12 ]; then
    m=1
    y=$((y+1))
  fi
  printf "%02d" $m $y
  echo $y
}

# Build fares JSON
echo "[" > "$TMP_FARES"
first=1
jq -c '.[]' "$TMP_APTS" | while read -r ap; do
  code=$(jq -r '.code' <<<"$ap")
  name=$(jq -r '.name' <<<"$ap")
  state=$(jq -r '.state' <<<"$ap")
  lat=$(jq -r '.lat' <<<"$ap")
  lon=$(jq -r '.lon' <<<"$ap")
  image=$(jq -r '.image' <<<"$ap")

  # for this airport, build monthly fares list
  fares_arr="["

  m=$current_month
  y=$current_year
  for i in $(seq 1 12); do
    # generate random fare, or call real API
    price=$(shuf -i 150-600 -n 1)
    # month label
    label=$(printf "%02d/%d" $m $y)
    fares_arr="${fares_arr}{\"month\":\"$label\",\"fare\":$price}"
    if [ $i -lt 12 ]; then
      fares_arr="${fares_arr},"
    fi

    # advance m,y
    m=$((m+1))
    if [ $m -gt 12 ]; then
      m=1
      y=$((y+1))
    fi
  done
  fares_arr="${fares_arr}]"

  entry=$(jq -nc --arg code "$code" --arg name "$name" --arg state "$state" --arg lat "$lat" --arg lon "$lon" --arg img "$image" --argjson fares "$fares_arr" \
    '{code: $code, name: $name, state: $state, lat: ($lat|tonumber), lon: ($lon|tonumber), image: $img, fares: $fares}')
  
  if [ $first -eq 1 ]; then
    echo "$entry" >> "$TMP_FARES"
    first=0
  else
    echo ",$entry" >> "$TMP_FARES"
  fi
done
echo "]" >> "$TMP_FARES"

# 4. Build index.html with Leaflet, popups with prev/next month buttons

cat > "$OUTFILE" <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Alaska Fare Map Interactive</title>
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet/dist/leaflet.css" />
  <style>
    html, body { height:100%; margin:0; padding:0;}
    #map { height:100vh; width:100%; }
    .popup { font-family: Arial, sans-serif; font-size: 14px; }
    .fare-display { margin-top:8px; }
    .nav-buttons { margin-top:4px; }
    .nav-buttons button { margin: 2px; }
    .airport-image { width:100%; border-radius:6px; margin-bottom:6px; max-height:150px; object-fit:cover; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script src="https://unpkg.com/leaflet/dist/leaflet.js"></script>
  <script>
    const airports = 
HTML_HEAD

cat "$TMP_FARES" >> "$OUTFILE"

cat >> "$OUTFILE" <<'JS_AFTER_DATA'
    ;

    // initialize map
    const map = L.map('map', { 
      // so that popups have room
      paddingTopLeft: [0, 100] 
    }).setView([47.5, -120], 4);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);

    // helper to avoid popups being cut off
    function openPopupCentered(marker, content) {
      marker.bindPopup(content, {maxWidth: 300}).openPopup();
      // after open, pan map so popup is fully visible
      const px = map.project(marker.getLatLng());
      const popupHeight = 200; // approximate - adjust
      const newY = px.y - popupHeight;
      map.panTo(map.unproject([px.x, newY]), {animate:true});
    }

    airports.forEach(ap => {
      const marker = L.marker([ap.lat, ap.lon]).addTo(map);
      let currentIdx = 0;

      function popupContent(idx) {
        const fare = ap.fares[idx];
        const total = ap.fares.length;
        return `
          <div class="popup">
            <img src="${ap.image}" class="airport-image" alt="${ap.name}" />
            <b>${ap.name} (${ap.code})</b><br>${ap.state}<br/>
            <div class="fare-display">
              <b>${fare.month}</b>: $${fare.fare}
            </div>
            <div class="nav-buttons">
              <button id="prev">Prev</button>
              <button id="next">Next</button>
            </div>
            <div><small>Airport ${idx+1} of ${total} months</small></div>
          </div>
        `;
      }

      marker.on('click', () => {
        currentIdx = 0;
        const content = popupContent(currentIdx);
        openPopupCentered(marker, content);

        // after the popup opens, set up event listeners on the buttons
        map.once('popupopen', () => {
          const prevBtn = document.getElementById('prev');
          const nextBtn = document.getElementById('next');
          prevBtn.addEventListener('click', () => {
            currentIdx = (currentIdx - 1 + ap.fares.length) % ap.fares.length;
            const newContent = popupContent(currentIdx);
            openPopupCentered(marker, newContent);
          });
          nextBtn.addEventListener('click', () => {
            currentIdx = (currentIdx + 1) % ap.fares.length;
            const newContent = popupContent(currentIdx);
            openPopupCentered(marker, newContent);
          });
        });
      });
    });
  </script>
</body>
</html>
JS_AFTER_DATA

echo "Generated $OUTFILE with $(jq length "$TMP_FARES") airports, each has $(jq '.[0].fares | length' "$TMP_FARES") months of fares."
