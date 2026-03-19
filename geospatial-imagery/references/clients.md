# Front-End Mapping Clients

Reference for how browser-based mapping clients request and display imagery from tile servers and OGC services.

## CesiumJS

WebGL-based 3D globe and 2D map engine. Imagery is managed through a provider/layer split: an **ImageryProvider** handles tile requests for a specific service, while an **ImageryLayer** represents displayed tiles and controls visual properties.

### ImageryProvider Classes

#### WebMapServiceImageryProvider

Connects to OGC WMS endpoints. Sends `GetMap` requests and optionally supports `GetFeatureInfo` for feature picking.

```javascript
const provider = new Cesium.WebMapServiceImageryProvider({
  url: "https://basemap.nationalmap.gov/arcgis/services/USGSHydroCached/MapServer/WMSServer",
  layers: "0",
  parameters: {
    format: "image/png",
    transparent: true,
  },
  tilingScheme: new Cesium.WebMercatorTilingScheme(),
  enablePickFeatures: true,
});
const layer = new Cesium.ImageryLayer(provider);
viewer.imageryLayers.add(layer);
```

Key constructor options:
- `url` (required) -- WMS service endpoint
- `layers` (required) -- comma-separated layer names
- `parameters` -- additional `GetMap` query parameters; defaults include `service=WMS`, `version=1.1.1`, `request=GetMap`, `styles=`, `format=image/jpeg`
- `getFeatureInfoParameters` -- additional `GetFeatureInfo` query parameters
- `enablePickFeatures` -- enables `GetFeatureInfo` on click (default `true`)
- `tilingScheme` -- `GeographicTilingScheme` or `WebMercatorTilingScheme`
- `tileWidth`, `tileHeight` -- tile dimensions in pixels (default 256)
- `minimumLevel`, `maximumLevel` -- zoom level range
- `clock`, `times` -- for time-dynamic WMS layers

#### WebMapTileServiceImageryProvider

Connects to OGC WMTS endpoints. Supports both KVP and RESTful request encoding.

```javascript
// RESTful URL template
const provider = new Cesium.WebMapTileServiceImageryProvider({
  url: "https://tiles.example.com/wmts/1.0.0/{layer}/{style}/{TileMatrixSet}/{TileMatrix}/{TileRow}/{TileCol}.png",
  layer: "imagery",
  style: "default",
  tileMatrixSetID: "GoogleMapsCompatible",
  format: "image/png",
  maximumLevel: 18,
});
viewer.imageryLayers.addImageryProvider(provider);

// KVP encoding
const kvpProvider = new Cesium.WebMapTileServiceImageryProvider({
  url: "https://tiles.example.com/wmts",
  layer: "imagery",
  style: "default",
  tileMatrixSetID: "GoogleMapsCompatible",
  format: "image/png",
});
```

Key constructor options:
- `url` (required) -- base URL (KVP) or URL template (RESTful) with placeholders `{style}`, `{TileMatrixSet}`, `{TileMatrix}`, `{TileRow}`, `{TileCol}`
- `layer` (required) -- WMTS layer name
- `style` (required) -- WMTS style name
- `tileMatrixSetID` (required) -- tile matrix set identifier
- `format` -- MIME type (default `image/jpeg`)
- `tileMatrixLabels` -- array of matrix identifiers, one per level
- `subdomains` -- string or array for `{s}` placeholder (default `"abc"`)
- `clock`, `times` -- for time-dynamic WMTS (e.g., NASA weather data)
- `dimensions` -- static key-value dimension pairs

#### UrlTemplateImageryProvider

Generic provider for XYZ, TMS, or any custom tile URL scheme.

```javascript
// Standard XYZ (e.g., OpenStreetMap-style)
const xyz = new Cesium.UrlTemplateImageryProvider({
  url: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
  subdomains: "abc",
  maximumLevel: 19,
  credit: "OpenStreetMap contributors",
});

// TMS (note {reverseY} for flipped Y-axis)
const tms = new Cesium.UrlTemplateImageryProvider({
  url: "https://tiles.example.com/{z}/{x}/{reverseY}.png",
  tilingScheme: new Cesium.GeographicTilingScheme(),
  maximumLevel: 14,
});
```

URL template placeholders:
- `{x}`, `{y}`, `{z}` -- tile column, row, zoom level
- `{reverseX}`, `{reverseY}`, `{reverseZ}` -- inverted coordinates
- `{s}` -- subdomain from the `subdomains` option
- `{westDegrees}`, `{southDegrees}`, `{eastDegrees}`, `{northDegrees}` -- geographic bounds
- `{westProjected}`, `{southProjected}`, `{eastProjected}`, `{northProjected}` -- projected bounds
- `{width}`, `{height}` -- tile pixel dimensions

The `customTags` option accepts an object of functions for user-defined placeholders.

#### TileMapServiceImageryProvider

Connects to TMS REST endpoints. Tiles can be generated with tools like GDAL2Tiles or Cesium Ion.

```javascript
const tms = await Cesium.TileMapServiceImageryProvider.fromUrl(
  "https://tiles.example.com/tms/imagery",
  { maximumLevel: 18 }
);
viewer.imageryLayers.addImageryProvider(tms);
```

#### Other Providers

- **IonImageryProvider** -- Cesium Ion hosted imagery assets
- **SingleTileImageryProvider** -- overlays a single image at a given rectangle
- **OpenStreetMapImageryProvider** -- OpenStreetMap / Slippy Map tiles
- **ArcGisMapServerImageryProvider** -- Esri ArcGIS REST services
- **BingMapsImageryProvider** -- Bing Maps (requires API key)
- **MapboxImageryProvider** -- Mapbox tiles (requires access token)
- **TileCoordinatesImageryProvider** -- debug overlay showing tile grid coordinates

### Imagery Layer Management

Layers are stored in an `ImageryLayerCollection` on the viewer. Layers draw bottom-to-top in collection order.

```javascript
const layers = viewer.imageryLayers;

// Add a layer
const layer = Cesium.ImageryLayer.fromProviderAsync(
  Cesium.IonImageryProvider.fromAssetId(3830183)
);
layers.add(layer);

// Adjust visual properties
layer.alpha = 0.7;          // 0.0 = transparent, 1.0 = opaque
layer.brightness = 1.2;     // >1.0 brighter, <1.0 darker (default 1.0)
layer.contrast = 1.0;       // >1.0 more contrast (default 1.0)
layer.gamma = 1.0;          // gamma correction (default 1.0)
layer.hue = 0.0;            // color rotation in radians (default 0.0)
layer.saturation = 1.0;     // >1.0 more saturated (default 1.0)

// Day/night alpha (when Globe lighting is enabled)
layer.dayAlpha = 1.0;
layer.nightAlpha = 0.5;

// Reorder layers
layers.raise(layer);         // move up one position
layers.raiseToTop(layer);    // move to top
layers.lower(layer);         // move down one position
layers.lowerToBottom(layer); // move to bottom

// Remove
layers.remove(layer);
```

Additional layer properties:
- `show` -- visibility toggle (boolean)
- `cutoutRectangle` -- rectangular region excluded from display
- `colorToAlpha` / `colorToAlphaThreshold` -- make a specific color transparent
- `minificationFilter`, `magnificationFilter` -- texture filtering (`LINEAR` default)
- `splitDirection` -- for split-screen comparisons

### Tiling Schemes

CesiumJS includes two built-in tiling schemes:

**GeographicTilingScheme (EPSG:4326)**
- At level 0: 2 tiles wide, 1 tile tall (covering the full globe)
- Each level quadruples the tile count
- Used by TMS and many geographic datasets

**WebMercatorTilingScheme (EPSG:3857)**
- At level 0: 1 tile covers the visible globe
- Standard web mapping projection (Google Maps, OSM, Mapbox)
- Default for `UrlTemplateImageryProvider`

At each level-of-detail, every tile subdivides into 4 children (2 in each direction).

### Level of Detail and Tile Selection

Cesium determines which tiles to load based on camera distance and screen-space error (SSE):

1. **Geometric error** -- each tile level has an associated geometric error representing the maximum error introduced by using that level instead of higher resolution data
2. **Screen-space error** -- the geometric error is projected to screen pixels based on camera distance; closer tiles have higher SSE
3. **Tile refinement** -- when a tile's SSE exceeds `maximumScreenSpaceError`, Cesium requests its children (higher resolution tiles)
4. **Dynamic SSE** -- the `dynamicScreenSpaceError` option applies a bell-curve falloff, selecting lower resolution tiles far from the camera to reduce total tile count

### Request Scheduling

CesiumJS uses a `RequestScheduler` to manage concurrent tile requests:

| Property | Default | Description |
|---|---|---|
| `maximumRequests` | 50 | Global limit on simultaneous active requests |
| `maximumRequestsPerServer` | 18 | Per-server limit (ignored for servers in `requestsByServer`) |
| `throttleRequests` | true | Whether the scheduler constrains requests |
| `requestsByServer` | `{}` | Per-server overrides, e.g., `{"tiles.example.com:443": 32}` |

Un-throttled requests bypass these limits. For HTTP/2+ servers, increase `maximumRequestsPerServer` or add the server to `requestsByServer` to avoid the default bottleneck. When the camera moves, the scheduler deprioritizes stale in-flight requests in favor of tiles visible in the new view.

---

## OpenLayers

Canvas and WebGL 2D map engine. Tile sources are attached to layers, and the view's projection drives reprojection when source and view projections differ.

### Tile Sources

#### ol/source/TileWMS

Requests WMS tiles by constructing `GetMap` URLs with automatically managed `WIDTH`, `HEIGHT`, `BBOX`, and `CRS`/`SRS` parameters.

```javascript
import TileLayer from "ol/layer/Tile.js";
import TileWMS from "ol/source/TileWMS.js";

const wmsLayer = new TileLayer({
  source: new TileWMS({
    url: "https://ahocevar.com/geoserver/wms",
    params: {
      LAYERS: "ne:NE1_HR_LC_SR_W_DR",
      FORMAT: "image/png",
      TRANSPARENT: true,
    },
    serverType: "geoserver",
    crossOrigin: "anonymous",
  }),
});
map.addLayer(wmsLayer);
```

Key options:
- `url` / `urls` -- single or multiple WMS endpoints (for load balancing)
- `params` (required) -- WMS parameters; `LAYERS` is required. `VERSION` defaults to `1.3.0`; `STYLES` defaults to empty string. Dynamic parameters (`WIDTH`, `HEIGHT`, `BBOX`, `CRS`/`SRS`) are set automatically.
- `serverType` -- `"geoserver"`, `"mapserver"`, `"carmentaserver"`, or `"qgis"` (required when `hidpi: true`)
- `gutter` -- pixel buffer around tiles to eliminate edge artifacts (default 0); server returns tiles wider by `2 * gutter`
- `crossOrigin` -- CORS attribute for Canvas pixel access
- `tileGrid` -- custom `TileGrid`; if omitted, a default grid is generated from the projection
- `projection` -- source projection (defaults to view projection)
- `hidpi` -- request tiles at device pixel ratio (default true)
- `transition` -- opacity transition in ms; `0` disables

#### ol/source/WMTS

Connects to OGC WMTS services. Supports manual configuration or auto-configuration from a capabilities document.

**Manual configuration:**

```javascript
import WMTS from "ol/source/WMTS.js";
import WMTSTileGrid from "ol/tilegrid/WMTS.js";
import { get as getProjection } from "ol/proj.js";
import { getWidth, getTopLeft } from "ol/extent.js";

const projection = getProjection("EPSG:3857");
const projectionExtent = projection.getExtent();
const size = getWidth(projectionExtent) / 256;
const resolutions = new Array(19);
const matrixIds = new Array(19);
for (let z = 0; z < 19; z++) {
  resolutions[z] = size / Math.pow(2, z);
  matrixIds[z] = z;
}

const wmtsSource = new WMTS({
  url: "https://tiles.example.com/wmts",
  layer: "imagery",
  matrixSet: "EPSG:3857",
  format: "image/png",
  style: "default",
  tileGrid: new WMTSTileGrid({
    origin: getTopLeft(projectionExtent),
    resolutions: resolutions,
    matrixIds: matrixIds,
  }),
});
```

**From capabilities document:**

```javascript
import WMTSCapabilities from "ol/format/WMTSCapabilities.js";
import WMTS, { optionsFromCapabilities } from "ol/source/WMTS.js";

const parser = new WMTSCapabilities();

fetch("https://tiles.example.com/wmts?SERVICE=WMTS&REQUEST=GetCapabilities")
  .then((response) => response.text())
  .then((text) => {
    const result = parser.read(text);
    const options = optionsFromCapabilities(result, {
      layer: "imagery",
      matrixSet: "EPSG:3857",
    });
    map.addLayer(
      new TileLayer({
        source: new WMTS(options),
      })
    );
  });
```

Key options:
- `layer`, `matrixSet`, `style` (required) -- WMTS service parameters
- `tileGrid` (required) -- `WMTSTileGrid` instance
- `requestEncoding` -- `"KVP"` (default) or `"REST"`
- `format` -- image MIME type (default `image/jpeg`)
- `dimensions` -- extra dimension parameters matching WMTS capabilities
- `version` -- WMTS version (default `1.0.0`)
- `tilePixelRatio` -- for retina/HiDPI tiles (default 1)

#### ol/source/XYZ

Generic XYZ tile source for slippy map URLs.

```javascript
import XYZ from "ol/source/XYZ.js";

const xyzSource = new XYZ({
  url: "https://{a-c}.tile.openstreetmap.org/{z}/{x}/{y}.png",
  maxZoom: 19,
  crossOrigin: "anonymous",
});
```

The URL template supports `{x}`, `{y}`, `{z}` for tile coordinates and `{a-c}` or `{1-4}` range syntax for subdomains.

#### ol/source/ImageWMS

Single-image WMS (no tiling). Requests one image for the entire visible extent. Useful for small areas or when server-side rendering of the full extent is preferred.

```javascript
import ImageLayer from "ol/layer/Image.js";
import ImageWMS from "ol/source/ImageWMS.js";

const imageLayer = new ImageLayer({
  source: new ImageWMS({
    url: "https://ahocevar.com/geoserver/wms",
    params: { LAYERS: "ne:NE1_HR_LC_SR_W_DR" },
    serverType: "geoserver",
    ratio: 1,
  }),
});
```

#### Other Sources

- **ol/source/OSM** -- OpenStreetMap preset (extends XYZ)
- **ol/source/TileArcGISRest** -- Esri ArcGIS REST tile services
- **ol/source/TileJSON** -- TileJSON specification
- **ol/source/Zoomify** -- Zoomify and IIP image servers

### Tile Grid

Tile grids define the resolution hierarchy and tile coordinate system.

**ol/tilegrid/TileGrid** -- base class for custom grids:
- `origin` -- top-left corner of the grid
- `resolutions` -- array of resolutions per zoom level (map units per pixel)
- `tileSize` -- pixel dimensions (default 256)

**ol/tilegrid/WMTS** -- extends TileGrid for WMTS:
- `matrixIds` -- array of tile matrix identifiers per zoom level

Zoom levels map directly to indices in the `resolutions` array. The view's `constrainResolution: true` option snaps to exact zoom levels.

### Projection Handling

OpenLayers natively supports:
- EPSG:4326 (WGS 84 Geographic)
- EPSG:3857 (Web Mercator)
- EPSG:32601 through EPSG:32660 and EPSG:32701 through EPSG:32760 (UTM zones)

**On-the-fly reprojection** occurs automatically when the source projection differs from the view projection. The source raster is divided into triangles, vertices are transformed, and affine transformations fill each triangle using hardware-accelerated Canvas 2D rendering.

**Custom projections with proj4js:**

```javascript
import proj4 from "proj4";
import { register } from "ol/proj/proj4.js";

proj4.defs(
  "EPSG:27700",
  "+proj=tmerc +lat_0=49 +lon_0=-2 +k=0.9996012717 " +
    "+x_0=400000 +y_0=-100000 +ellps=airy " +
    "+towgs84=446.448,-125.157,542.06,0.15,0.247,0.842,-20.489 " +
    "+units=m +no_defs"
);
register(proj4);

// Use in a view
const map = new Map({
  view: new View({
    projection: "EPSG:27700",
    center: [400000, 650000],
    zoom: 4,
  }),
});
```

The `reprojectionErrorThreshold` option (default 0.5 pixels) controls the dynamic triangulation precision. Lower values produce more accurate results but use more triangles.

### Tile Loading Events

```javascript
source.on("tileloadstart", (event) => {
  // tile request initiated
});

source.on("tileloadend", (event) => {
  // tile successfully loaded
});

source.on("tileloaderror", (event) => {
  // tile request failed
});
```

---

## Leaflet

Lightweight 2D map library. Simpler API than CesiumJS or OpenLayers, with a plugin ecosystem for extended protocol support.

### L.tileLayer (XYZ Tiles)

```javascript
const osm = L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19,
  subdomains: "abc",
  attribution: "&copy; OpenStreetMap contributors",
}).addTo(map);
```

URL template placeholders:
- `{s}` -- subdomain (cycles through `subdomains` option, default `"abc"`)
- `{z}` -- zoom level
- `{x}` -- tile column
- `{y}` -- tile row
- `{r}` -- retina modifier (e.g., `"@2x"` on HiDPI displays when `detectRetina: true`)
- `{-y}` -- inverted Y for TMS (alternative to `tms: true`)

Key options:

| Option | Default | Description |
|---|---|---|
| `minZoom` | 0 | Minimum zoom level |
| `maxZoom` | 18 | Maximum zoom level |
| `subdomains` | `"abc"` | Subdomains for `{s}` placeholder |
| `errorTileUrl` | `""` | URL for fallback tile image on error |
| `tms` | `false` | Invert Y-axis numbering for TMS |
| `zoomOffset` | 0 | Offset added to zoom in tile URLs |
| `zoomReverse` | `false` | Use `maxZoom - zoom` instead of zoom |
| `detectRetina` | `false` | Request higher resolution tiles on HiDPI |
| `crossOrigin` | `false` | CORS attribute for tile requests |

Events: `loading`, `tileloadstart`, `tileload`, `tileerror`, `tileunload`, `load`, `tileabort`.

### L.tileLayer.wms (WMS Tiles)

```javascript
const wms = L.tileLayer
  .wms("https://ows.mundialis.de/services/service?", {
    layers: "TOPO-OSM-WMS",
    format: "image/png",
    transparent: true,
    attribution: "mundialis GmbH",
  })
  .addTo(map);
```

WMS-specific options:
- `layers` (required) -- comma-separated WMS layer names
- `styles` -- WMS styles (default `""`)
- `format` -- image format (default `"image/jpeg"`)
- `transparent` -- request transparent tiles (default `false`)
- `version` -- WMS version (default `"1.1.1"`)
- `crs` -- coordinate reference system (default: map CRS)
- `uppercase` -- send parameter keys in uppercase (default `false`)

Leaflet supports CRS options `L.CRS.EPSG3857`, `L.CRS.EPSG3395`, and `L.CRS.EPSG4326`.

### TMS with Leaflet

```javascript
// Using tms option (legacy)
const tms = L.tileLayer(
  "https://tiles.example.com/tms/1.0.0/imagery/{z}/{x}/{y}.png",
  { tms: true }
).addTo(map);

// Using {-y} placeholder (Leaflet 1.0+, preferred)
const tms2 = L.tileLayer(
  "https://tiles.example.com/tms/1.0.0/imagery/{z}/{x}/{-y}.png"
).addTo(map);
```

### WMTS with Leaflet

Leaflet has no built-in WMTS support. WMTS services that use standard XYZ-compatible tiling can be accessed via `L.tileLayer` with a crafted URL template. For full WMTS support, use plugins:

- **leaflet-tilelayer-wmts** -- adds `L.TileLayer.WMTS` for RESTful and KVP WMTS
- **leaflet.wms** -- enhanced WMS support with `GetFeatureInfo` and GeoJSON parsing

---

## Common Client Patterns

### Tile URL Construction

All clients build tile URLs from a combination of zoom level and tile coordinates. The two main coordinate systems:

**XYZ / Slippy Map (Google/OSM scheme):**
- Origin at top-left (northwest)
- Y increases downward
- URL pattern: `/{z}/{x}/{y}.png`

**TMS (Tile Map Service):**
- Origin at bottom-left (southwest)
- Y increases upward
- Conversion: `tms_y = (2^z - 1) - xyz_y`

**WMTS:**
- Uses `TileMatrix` (zoom), `TileRow` (y), `TileCol` (x)
- Matrix identifiers may be strings rather than integers

### Request Throttling and Queuing

Clients manage concurrent tile requests to avoid overwhelming servers and browsers:

- **CesiumJS** -- `RequestScheduler` with configurable global (50) and per-server (18) limits. Deprioritizes stale requests when the camera moves. Supports HTTP/2+ overrides.
- **OpenLayers** -- delegates to the browser's connection pool. The `tileLoadFunction` option allows custom request logic.
- **Leaflet** -- no built-in request scheduler. Relies on browser connection limits (6 per domain for HTTP/1.1). The `subdomains` option distributes requests across multiple hostnames to increase parallelism.

### Client-Side Caching

- **Browser HTTP cache** -- tile responses with appropriate `Cache-Control` or `Expires` headers are cached by the browser automatically. Typical TTLs range from hours (dynamic data) to months (static basemaps).
- **Service workers** -- can intercept tile requests and serve from `Cache API` storage for offline use.
- **IndexedDB** -- used by some offline mapping libraries to store tile blobs persistently.

### Error Handling

| Client | Mechanism |
|---|---|
| CesiumJS | `TileDiscardPolicy` to detect and discard bad tiles; provider `errorEvent` |
| OpenLayers | `tileloaderror` event; custom `tileLoadFunction` for retry logic |
| Leaflet | `tileerror` event; `errorTileUrl` option for placeholder image |

### Retina / HiDPI Support

- **CesiumJS** -- request larger tiles (512x512) via `tileWidth`/`tileHeight` on providers; display at half size
- **OpenLayers** -- `hidpi: true` on `TileWMS` (default); `tilePixelRatio` on WMTS; `{a-c}.tiles.example.com/{z}/{x}/{y}@2x.png` URL patterns for XYZ
- **Leaflet** -- `detectRetina: true` option loads tiles at `zoom + 1` and displays at half size; `{r}` placeholder in URL templates for `@2x` suffix

### CORS Requirements

Tile servers must send appropriate CORS headers for tiles to be usable in WebGL textures or Canvas pixel operations:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, HEAD, OPTIONS
Access-Control-Allow-Headers: Range, If-Match
```

Without CORS headers:
- CesiumJS -- cannot use tiles as WebGL textures; requires a proxy server
- OpenLayers -- tiles display but Canvas pixel operations (`getImageData`) fail
- Leaflet -- tiles display (loaded via `<img>` tags) but cross-origin restrictions apply to Canvas export

Set `crossOrigin: "anonymous"` on the source/layer to make CORS-enabled requests (the browser sends an `Origin` header and checks `Access-Control-Allow-Origin` in the response). Normal tile GET requests are "simple" CORS requests and do NOT trigger a preflight OPTIONS request -- preflight only occurs with custom headers or non-simple methods.

### Authentication

Common patterns for authenticated tile requests:

- **URL query parameter** -- `?api_key=TOKEN` appended to tile URLs
- **Custom headers** -- set via `tileLoadFunction` (OpenLayers) or custom `Resource` headers (CesiumJS)
- **Subdomains with tokens** -- some services encode tokens in the subdomain
- **Cookie-based** -- `crossOrigin: "use-credentials"` to send cookies with tile requests

```javascript
// CesiumJS -- API key in URL
const provider = new Cesium.UrlTemplateImageryProvider({
  url: "https://tiles.example.com/{z}/{x}/{y}.png?api_key=YOUR_KEY",
});

// OpenLayers -- custom header via tileLoadFunction
const source = new TileWMS({
  url: "https://tiles.example.com/wms",
  params: { LAYERS: "data" },
  tileLoadFunction: (tile, src) => {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", src);
    xhr.setRequestHeader("Authorization", "Bearer YOUR_TOKEN");
    xhr.responseType = "blob";
    xhr.onload = () => {
      const url = URL.createObjectURL(xhr.response);
      tile.getImage().src = url;
    };
    xhr.send();
  },
});
```
