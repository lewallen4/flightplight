#!/usr/bin/env bash
# generate_flights.sh
# Fetch live flights from OpenSky and produce index.html (Leaflet map)
# Meant to be run from GitHub Actions (or locally). Requires: curl, jq
set -euo pipefail

OUTFILE="index.html"
API_URL="https://opensky-network.org/api/states/all"
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

# Ensure required commands exist
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  fi
done

# Fetch OpenSky data
HTTP_CODE=$(curl -sS -w "%{http_code}" -o "$TMP_JSON" "$API_URL" || echo "000")
if [ "$HTTP_CODE" != "200" ]; then
  echo "Warning: OpenSky API returned HTTP $HTTP_CODE. Writing an error page to $OUTFILE."
  cat > "$OUTFILE" <<HTML_ERR
<!doctype html>
<html>
<head><meta charset="utf-8"><title>Flight Tracker - Error</title></head>
<body>
  <h1>Flight Tracker</h1>
  <p>Error fetching flight data from OpenSky (HTTP $HTTP_CODE).</p>
  <pre>$(head -n 200 "$TMP_JSON" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</pre>
</body>
</html>
HTML_ERR
  exit 0
fi

# Transform the OpenSky "states" into a compact array of objects we care about
# Each state array positions:
# 0: icao24, 1: callsign, 2: origin_country, 3: time_position, 4: last_contact,
# 5: longitude, 6: latitude, 7: baro_altitude, 8: on_ground, 9: velocity, 10: heading, 11: vertical_rate
FLIGHT_DATA=$(jq -c '
  if .states == null then [] 
  else [.states[]? | {
    icao24: .[0],
    callsign: (.[1] // "" | gsub("^\\s+|\\s+$"; "")),
    origin_country: .[2],
    time_position: .[3],
    last_contact: .[4],
    longitude: .[5],
    latitude: .[6],
    baro_altitude: .[7],
    on_ground: .[8],
    velocity: .[9],
    heading: .[10],
    vertical_rate: .[11]
  }] end
' "$TMP_JSON") || FLIGHT_DATA="[]"

# Escape any literal </script> sequences in the JSON so embedding in a <script type="application/json"> is safe
SAFE_FLIGHT_DATA=$(printf '%s' "$FLIGHT_DATA" | sed 's#</script>#<\\/script>#g')

# Build the HTML file
# Write header + a <script type="application/json"> block containing the JSON, then append JS that reads it and draws the map.
cat > "$OUTFILE" <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Flight Tracker</title>
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet/dist/leaflet.css" />
  <style>
    html,body { height:100%; margin:0; }
    #map { height:100vh; width:100%; }
    .leaflet-popup-content { font-family: monospace; font-size: 13px; }
    .topbar {
      position: absolute; left:36px; top:12px; z-index:1000;
      background: rgba(255,255,255,0.9); padding:8px 10px; border-radius:6px;
      box-shadow: 0 1px 4px rgba(0,0,0,0.2); font-family: Arial, sans-serif;
    }
    .search { width:220px; }
  </style>
</head>
<body>
  <div class="topbar">
    <strong>Flight Tracker</strong><br/>
    <input id="q" class="search" placeholder="filter by callsign/country (press Enter)"/>
    <button id="clear">Clear</button>
    <button id="fit">Fit to US</button>
  </div>

  <div id="map"></div>

  <!-- embedded flight data (application/json) -->
  <script id="flights-data" type="application/json">
HTML_HEAD

# Insert the JSON safely
printf '%s\n' "$SAFE_FLIGHT_DATA" >> "$OUTFILE"

# Write the rest of the HTML/JS
cat >> "$OUTFILE" <<'HTML_FOOT'
  </script>

  <script src="https://unpkg.com/leaflet/dist/leaflet.js"></script>
  <script>
    // Parse embedded flight JSON
    const flights = JSON.parse(document.getElementById('flights-data').textContent || '[]');

    // Initialize map centered on the continental US
    const map = L.map('map').setView([39.5, -98.35], 4);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);

    // Helper to format numbers nicely
    function fmt(n, dp=0){ return n===null||n===undefined ? 'N/A' : (Math.round(n * Math.pow(10,dp)) / Math.pow(10,dp)); }

    // Create markers for flights with valid lat/lon
    const markers = [];
    flights.forEach(f => {
      if (f.latitude === null || f.longitude === null) return;
      // Convert numeric strings to numbers (jq may have produced numbers or nulls)
      const lat = Number(f.latitude);
      const lon = Number(f.longitude);
      if (!isFinite(lat) || !isFinite(lon)) return;

      const title = (f.callsign && f.callsign.trim() !== '') ? f.callsign.trim() : f.icao24;
      const popupHtml = `
        <b>${title}</b><br/>
        <table>
          <tr><td>Origin Country:</td><td>${f.origin_country||'N/A'}</td></tr>
          <tr><td>Altitude (m):</td><td>${fmt(f.baro_altitude,1)}</td></tr>
          <tr><td>Speed (m/s):</td><td>${fmt(f.velocity,1)}</td></tr>
          <tr><td>Heading:</td><td>${fmt(f.heading,1)}</td></tr>
          <tr><td>ICAO24:</td><td>${f.icao24||'N/A'}</td></tr>
          <tr><td>Last contact:</td><td>${f.last_contact||'N/A'}</td></tr>
        </table>
      `;

      const m = L.marker([lat, lon]).addTo(map).bindPopup(popupHtml);
      m._meta = { callsign: (f.callsign||'').trim(), country: f.origin_country||'', icao24: f.icao24||'' };
      markers.push(m);
    });

    // Utility to filter markers by substring in callsign/country/icao
    function filterMarkers(q) {
      const ql = q.trim().toLowerCase();
      markers.forEach(m => {
        const keep = ql === '' || (m._meta.callsign && m._meta.callsign.toLowerCase().includes(ql))
                   || (m._meta.country && m._meta.country.toLowerCase().includes(ql))
                   || (m._meta.icao24 && m._meta.icao24.toLowerCase().includes(ql));
        if (keep) {
          if (!map.hasLayer(m)) m.addTo(map);
        } else {
          if (map.hasLayer(m)) map.removeLayer(m);
        }
      });
    }

    // Fit map to continental US bounds (approx) or to visible markers
    document.getElementById('fit').addEventListener('click', () => {
      // continental US approx bounds
      const usBounds = L.latLngBounds([[24.396308, -124.848974], [49.384358, -66.885444]]);
      map.fitBounds(usBounds);
    });

    // Search box
    const qbox = document.getElementById('q');
    qbox.addEventListener('keypress', (ev) => {
      if (ev.key === 'Enter') filterMarkers(qbox.value);
    });
    document.getElementById('clear').addEventListener('click', () => {
      qbox.value = '';
      filterMarkers('');
    });

    // If there are markers, optionally fit to them on load (comment/uncomment as desired)
    if (markers.length > 0) {
      try {
        const group = L.featureGroup(markers);
        map.fitBounds(group.getBounds(), { maxZoom: 6, padding: [40,40] });
      } catch(e) {
        // fallback: do nothing
      }
    } else {
      // nothing to show - keep US view
    }

    // Allow clicking map to show lat/lon (handy for debugging)
    map.on('click', function(e){
      const p = e.latlng;
      L.popup()
        .setLatLng(p)
        .setContent(`Latitude: ${p.lat.toFixed(4)}<br>Longitude: ${p.lng.toFixed(4)}`)
        .openOn(map);
    });

  </script>
</body>
</html>
HTML_FOOT

echo "Wrote $OUTFILE with $(jq 'length' <<< "$FLIGHT_DATA") flights."
