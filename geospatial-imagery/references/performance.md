# Performance Optimization for Geospatial Imagery Serving

## Data Preparation Optimization

### Cloud-Optimized GeoTIFF (COG)

A Cloud-Optimized GeoTIFF organizes data with overviews first, internal tiling, and a layout optimized for HTTP range requests. This allows clients to fetch only the portion of the file they need rather than downloading the entire raster.

**Key structural properties:**
- Internal tiles (default 512x512 in the COG driver) instead of scanline strips
- Overviews (reduced-resolution copies) stored before full-resolution data
- TIFF directory entries ordered for minimal HTTP GET range requests
- Compatible with standard GeoTIFF readers

**Creating a COG with GDAL:**

```bash
# Basic COG creation with DEFLATE (lossless, good general-purpose choice)
gdal_translate -of COG \
  -co COMPRESS=DEFLATE \
  -co PREDICTOR=YES \
  -co BLOCKSIZE=512 \
  -co NUM_THREADS=ALL_CPUS \
  input.tif output_cog.tif

# COG with JPEG compression (lossy, smaller files for visual imagery)
gdal_translate -of COG \
  -co COMPRESS=JPEG \
  -co QUALITY=85 \
  -co BLOCKSIZE=512 \
  -co OVERVIEW_RESAMPLING=AVERAGE \
  input.tif output_cog.tif

# COG with WebP compression (lossy or lossless, smallest files)
gdal_translate -of COG \
  -co COMPRESS=WEBP \
  -co QUALITY=80 \
  -co BLOCKSIZE=512 \
  input.tif output_cog.tif

# COG in Web Mercator tiling scheme (pre-aligned to XYZ tiles)
gdal_translate -of COG \
  -co TILING_SCHEME=GoogleMapsCompatible \
  -co COMPRESS=JPEG \
  -co QUALITY=80 \
  input.tif output_webmerc_cog.tif

# Validate a COG
python -m cogeo_valid output_cog.tif
```

**Compression selection guide:**

| Compression | Type     | Best For                  | Relative Size | Decode Speed |
|-------------|----------|---------------------------|---------------|--------------|
| DEFLATE     | Lossless | General purpose, data     | Medium        | Fast         |
| LZW         | Lossless | General purpose, data     | Medium        | Fast         |
| ZSTD        | Lossless | Modern pipelines          | Small-Medium  | Very fast    |
| JPEG        | Lossy    | Visual imagery (RGB)      | Small         | Very fast    |
| WEBP        | Both     | Visual imagery, web       | Very small    | Fast         |
| LERC        | Lossy*   | Elevation, scientific     | Small         | Fast         |
| JXL         | Both     | Next-gen (limited support)| Very small    | Medium       |

*LERC is lossless when MAX_Z_ERROR=0.

**GDAL COG driver creation options:**
- `BLOCKSIZE`: Tile dimension in pixels (default 512, minimum 128, must be divisible by 16)
- `COMPRESS`: Compression algorithm (default LZW when available; supported: NONE, LZW, JPEG, DEFLATE, ZSTD, WEBP, LERC, LERC_DEFLATE, LERC_ZSTD, LZMA, JXL)
- `QUALITY`: JPEG/WebP quality 1-100 (default 75)
- `PREDICTOR`: YES, NO, STANDARD, or FLOATING_POINT (default FALSE; YES auto-selects STANDARD for integer data, FLOATING_POINT for float data)
- `OVERVIEW_RESAMPLING`: NEAREST, AVERAGE, BILINEAR, CUBIC, CUBICSPLINE, LANCZOS, MODE, RMS (default: NEAREST for color-table/complex data, CUBIC otherwise)
- `OVERVIEW_COUNT`: Number of overview levels (auto-calculated if omitted; generates until smallest overview fits within BLOCKSIZE)
- `OVERVIEWS`: AUTO, IGNORE_EXISTING, FORCE_USE_EXISTING, NONE
- `NUM_THREADS`: Number of encoding threads (use ALL_CPUS)
- `TILING_SCHEME`: Align to a standard grid (e.g., GoogleMapsCompatible); when set, BLOCKSIZE defaults to the tile matrix tile width

### Overview Pyramid Strategies

Overviews are reduced-resolution copies of the source image that enable fast rendering at lower zoom levels without reading the full-resolution data.

**Resampling method selection:**

| Method  | Use Case                              | Quality   | Speed  |
|---------|---------------------------------------|-----------|--------|
| NEAREST | Classified/categorical data, DEMs     | Preserves values | Fast |
| AVERAGE | Continuous data, imagery              | Smooth    | Fast   |
| CUBIC   | Visual imagery needing sharp results  | Sharp     | Medium |
| LANCZOS | Highest quality visual imagery        | Sharpest  | Slow   |
| MODE    | Categorical rasters (land use/cover)  | Preserves categories | Medium |

**Overview level calculation:**

Overviews should be generated until the smallest overview level has a maximum dimension under 512 pixels. Standard levels are powers of 2:

```bash
# Generate overviews at 2x, 4x, 8x, 16x, 32x reduction
gdaladdo -r average input.tif 2 4 8 16 32

# The COG driver auto-calculates levels when using -of COG
# To control explicitly:
gdal_translate -of COG \
  -co OVERVIEW_COUNT=5 \
  -co OVERVIEW_RESAMPLING=CUBIC \
  input.tif output_cog.tif
```

**Internal vs. external overviews:**
- Internal overviews (stored inside the TIFF): Single file, simpler management, required for COGs
- External overviews (.ovr sidecar files): Source file unchanged, flexible updates
- For serving, always prefer internal overviews (COG format) to minimize HTTP requests

### Tile Pre-generation vs. On-Demand Rendering

**Tile count per zoom level:**

The number of tiles at zoom level z is `4^z` (equivalently `2^z * 2^z`):

| Zoom | Tiles       | Typical Use              |
|------|-------------|--------------------------|
| 0    | 1           | World overview            |
| 5    | 1,024       | Country level             |
| 10   | 1,048,576   | City level                |
| 15   | ~1.07B      | Street level              |
| 18   | ~68.7B      | Building level            |
| 20   | ~1.1T       | Maximum detail            |

**Disk space estimation formula:**

```
total_tiles = sum(4^z for z in range(min_zoom, max_zoom + 1))
storage_bytes = total_tiles * avg_tile_size_bytes

# For a bounded region:
tiles_in_region(z) = ceil((lon_max - lon_min) / tile_width(z)) *
                     ceil((lat_max - lat_min) / tile_height(z))
```

Average tile sizes: PNG ~30-40 KB, JPEG ~15-25 KB, WebP ~10-18 KB.

**Decision guide:**

| Strategy         | When to Use                                    |
|------------------|------------------------------------------------|
| Pre-generate     | Zoom 0-12, high-traffic areas, static data     |
| On-demand + cache| Zoom 13+, low-traffic areas, frequently updated |
| Hybrid           | Pre-generate low zooms, render high zooms on demand |

Pre-rendering the entire world through all zoom levels is impractical -- tile count grows as 4^z per level. At 15 KB/JPEG tile: zoom 0-12 requires ~22 million tiles (~330 GB), zoom 0-15 reaches ~1.4 billion tiles (~21 TB), and zoom 0-18 reaches ~91 billion tiles (~1.4 PB). Full coverage through zoom 20 reaches ~1.5 trillion tiles (~22 PB). Use a hybrid approach: pre-generate tiles for low zoom levels (0-12) and high-traffic regions, render on demand for higher zoom levels and low-traffic areas.

### Tile Format Selection for Serving

| Format | Size    | Encode Speed | Decode Speed | Transparency | Browser Support |
|--------|---------|--------------|--------------|--------------|-----------------|
| PNG    | Large   | Medium       | Fast         | Yes (alpha)  | Universal       |
| JPEG   | Small   | Fast         | Very fast    | No           | Universal       |
| WebP   | Smaller | 3-8x slower than JPEG | Fast | Yes (alpha) | Wide (check caniuse.com) |
| AVIF   | Smallest| Very slow    | Medium       | Yes (alpha)  | Growing (check caniuse.com) |

**Practical guidance:**
- Use JPEG for opaque imagery tiles (satellite, aerial): best speed/size balance
- Use PNG for tiles requiring transparency or pixel-exact rendering
- Use WebP as a progressive enhancement (serve via Accept header negotiation)
- Avoid AVIF for real-time rendering due to slow encoding; consider for pre-generated tiles only
- WebP tiles are typically 25-34% smaller than JPEG at equivalent quality, reducing load times
- Example: a 560 KB source photo produces approximately 289 KB (JPEG q75), 206 KB (WebP q75), 101 KB (AVIF q30)

### Image Quantization

Reduce PNG tile sizes by quantizing to 8-bit (256-color) palette:

```bash
# Using pngquant for 8-bit PNG optimization
pngquant --quality=65-80 --speed 1 --output tile_q.png tile.png

# Batch process tiles
find /tiles -name "*.png" -exec pngquant --ext .png --force --quality=65-80 {} \;
```

8-bit palette PNGs are typically 60-80% smaller than 24-bit (truecolor) PNGs. This works well for map tiles with limited color ranges (road maps, thematic maps) but not for photographic imagery.

## Caching Strategies

### Multi-Tier Caching

A tiered caching architecture minimizes latency by serving from the fastest available layer:

```
Request -> L1 (In-Memory LRU) -> L2 (Disk/SSD) -> L3 (Object Storage) -> Origin Render
              < 1ms               1-5ms              10-100ms              100-5000ms
```

**L1: In-memory cache (hot)**
- LRU (Least Recently Used) eviction policy
- Size: 256 MB to 2 GB depending on available RAM
- Holds the most frequently accessed tiles (low zoom levels, popular areas)
- Implementation: Go `sync.Map` with LRU wrapper, or `groupcache`

**L2: Disk/SSD cache (warm)**
- Filesystem-based tile store organized by z/x/y path
- Size: 10-500 GB on SSD
- Serves tiles that overflow the memory cache
- Implementation: Directory tree (`/cache/{layer}/{z}/{x}/{y}.png`) or MBTiles/SQLite

**L3: Object storage (cold)**
- S3, GCS, or Azure Blob Storage
- Virtually unlimited capacity
- Higher latency but highly durable
- Implementation: S3-compatible API with prefix-based key scheme

### CDN Integration

CDNs (CloudFront, CloudFlare, Akamai, Fastly) cache tiles at edge locations worldwide, reducing latency for geographically distributed users.

**Cache key design:**

```
# Standard XYZ pattern
/{layer}/{z}/{x}/{y}.{format}

# Versioned tiles for cache busting
/v{version}/{layer}/{z}/{x}/{y}.{format}

# With style variant
/{layer}/{style}/{z}/{x}/{y}.{format}
```

**CloudFront configuration considerations:**
- Cache policy based on path pattern (no query string needed for XYZ tiles)
- Origin request policy: forward only necessary headers
- TTL: Set high (days to weeks) for static imagery, lower for dynamic data
- Compress objects automatically: No (tiles are already compressed as PNG/JPEG)

**Cache purge strategies:**
- Path-based invalidation: `/layer-name/*` to clear an entire layer
- Versioned paths: Increment version in URL to bypass all caches instantly
- Tag-based purge (Fastly/CloudFlare): Tag tiles by source dataset for selective invalidation

### Edge Caching Headers

```http
# Static/versioned tiles (content never changes at this URL)
Cache-Control: public, max-age=31536000, immutable

# Semi-static tiles (update occasionally)
Cache-Control: public, max-age=86400, stale-while-revalidate=604800

# Dynamic tiles (change frequently)
Cache-Control: public, max-age=300, stale-while-revalidate=60
```

**Key directives:**
- `immutable`: Tells browsers not to revalidate even on reload (use with versioned URLs)
- `stale-while-revalidate`: Serve stale content immediately while fetching fresh copy in background (supported by CloudFront, Fastly, and modern browsers)
- `stale-if-error`: Serve stale content if origin is down

### Metatiling

Metatiling renders a larger area (e.g., 4x4 tiles = 1024x1024 px) as a single image, then slices it into individual tiles.

**Benefits:**
- Eliminates duplicate label/symbol rendering at tile boundaries
- Reduces WMS backend overhead (one request instead of 16 for a 4x4 metatile)
- Improves label placement across tile edges
- Generally faster for the WMS backend to render one large image than many small ones

**Configuration (GeoWebCache):**

```xml
<metaWidthHeight>
  <int>4</int>
  <int>4</int>
</metaWidthHeight>
<gutter>20</gutter>
```

- Metatile size: 4x4 is the GeoServer default, balancing performance and memory
- Gutter: Extra pixels (typically 10-20) around the metatile to prevent clipped labels/symbols at edges
- Trade-off: Larger metatiles use more memory per render but reduce total render calls

### Request Coalescing (Singleflight Pattern)

When multiple concurrent requests arrive for the same uncached tile, only one render operation executes while others wait for the result.

**Go implementation using `golang.org/x/sync/singleflight`:**

```go
import "golang.org/x/sync/singleflight"

var group singleflight.Group

func getTile(z, x, y int, format string) ([]byte, error) {
    key := fmt.Sprintf("%d/%d/%d.%s", z, x, y, format)

    result, err, _ := group.Do(key, func() (interface{}, error) {
        // Check cache first
        if tile, ok := cache.Get(key); ok {
            return tile, nil
        }
        // Render tile
        tile, err := renderTile(z, x, y, format)
        if err != nil {
            return nil, err
        }
        // Store in cache
        cache.Set(key, tile)
        return tile, nil
    })

    if err != nil {
        return nil, err
    }
    return result.([]byte), nil
}
```

This prevents the "thundering herd" problem where hundreds of users requesting the same tile cause hundreds of redundant renders. Only the first request triggers rendering; all concurrent duplicates receive the same result.

### Cache Warming and Seeding

Pre-populate caches for high-traffic areas and zoom levels before users request them:

```bash
# Seed tiles for a bounding box using GDAL
gdal2tiles.py -z 0-14 --xyz --processes=4 input.tif /output/tiles/

# Seed GeoWebCache via REST API
curl -u admin:geoserver -X POST \
  "http://localhost:8080/geoserver/gwc/rest/seed/layer_name.json" \
  -H "Content-Type: application/json" \
  -d '{
    "seedRequest": {
      "name": "layer_name",
      "zoomStart": 0,
      "zoomStop": 14,
      "type": "seed",
      "threadCount": 4
    }
  }'
```

**Seeding strategy:**
- Always seed zoom levels 0-10 (relatively few tiles, frequently accessed)
- Seed zoom 11-14 for known high-traffic geographic areas
- Leave zoom 15+ for on-demand rendering with caching
- Schedule re-seeding during off-peak hours when source data updates

### Cache Invalidation

| Strategy             | Mechanism                                  | Use Case                    |
|----------------------|--------------------------------------------|-----------------------------|
| Versioned paths      | `/v2/layer/{z}/{x}/{y}.png`                | Full dataset replacement    |
| Time-based expiry    | `Cache-Control: max-age=86400`             | Regularly updated data      |
| Event-driven purge   | Webhook triggers CDN invalidation          | On-demand source updates    |
| Tag-based purge      | Purge by surrogate key / cache tag         | Selective layer invalidation|
| Bounding box purge   | Invalidate tiles intersecting updated bbox | Partial data updates        |

### ETag and Conditional Requests

Use ETags to avoid re-transmitting unchanged tiles:

```http
# Response with ETag
HTTP/1.1 200 OK
ETag: "a1b2c3d4e5"
Cache-Control: public, max-age=3600

# Subsequent conditional request
GET /tiles/10/512/340.png HTTP/1.1
If-None-Match: "a1b2c3d4e5"

# Server response if tile unchanged
HTTP/1.1 304 Not Modified
```

Generate ETags from tile content hash or last-modified timestamp of source data. This reduces bandwidth for clients that already have the tile cached locally.

## Server-Side Performance

### Connection Pooling

For database-backed tile stores (PostGIS, Oracle) and GDAL dataset handles:

```go
// Database connection pool (Go example with pgxpool)
config, _ := pgxpool.ParseConfig(connString)
config.MaxConns = 20              // Max concurrent connections
config.MinConns = 5               // Keep minimum connections warm
config.MaxConnLifetime = 30 * time.Minute
config.MaxConnIdleTime = 5 * time.Minute
pool, _ := pgxpool.NewWithConfig(ctx, config)
```

For GDAL dataset handles, maintain a pool of open datasets to avoid the overhead of repeatedly opening and closing large files. Close and reopen periodically to release file handles.

### Thread/Goroutine Management

Limit concurrent render operations to prevent resource exhaustion:

```go
// Semaphore pattern to limit concurrent tile renders
renderSem := make(chan struct{}, runtime.NumCPU())

func renderTile(z, x, y int) ([]byte, error) {
    renderSem <- struct{}{}        // Acquire slot
    defer func() { <-renderSem }() // Release slot

    // Perform CPU-intensive rendering
    return doRender(z, x, y)
}
```

Set the concurrency limit to the number of CPU cores for CPU-bound rendering. For I/O-bound operations (reading from storage), a higher limit (2-4x CPU count) may be appropriate.

### Memory Management

**Buffer pooling for image encoding:**

```go
// Reuse byte buffers for tile encoding to reduce GC pressure
var bufPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

func encodeTile(img image.Image) ([]byte, error) {
    buf := bufPool.Get().(*bytes.Buffer)
    defer bufPool.Put(buf)
    buf.Reset()

    if err := png.Encode(buf, img); err != nil {
        return nil, err
    }
    return append([]byte(nil), buf.Bytes()...), nil  // Copy out
}
```

**Memory-mapped file access:**
- Use `mmap` for large raster files to let the OS manage page caching
- Avoids loading entire files into application memory
- Particularly effective for COGs where only tile-aligned portions are read

**Avoid allocations in hot paths:**
- Pre-allocate image buffers of known tile dimensions (256x256 or 512x512)
- Reuse `image.RGBA` or `image.Paletted` structures across renders
- Use `sync.Pool` for any temporary buffers in the render pipeline

### HTTP/2 and Multiplexing

HTTP/2 multiplexes multiple tile requests over a single TCP connection, significantly reducing connection overhead when a map client requests dozens of tiles simultaneously.

**Benefits for tile serving:**
- A full screen of tiles (typically 20-40 tiles) can be fetched over one connection
- Eliminates the HTTP/1.1 per-domain connection limit (6 connections)
- Header compression (HPACK) reduces repeated header overhead
- Binary framing is more efficient for many small responses (tiles)

**Server configuration (nginx example):**

```nginx
server {
    listen 443 ssl http2;

    location /tiles/ {
        # Enable sendfile for pre-rendered tiles on disk
        sendfile on;
        tcp_nopush on;

        # Disable gzip for already-compressed tiles
        gzip off;
    }
}
```

### Compression

**Do compress:** WMS XML/GML responses, GeoJSON, vector tile metadata, HTML responses
**Do not compress:** PNG, JPEG, WebP tiles (already compressed; double-compression wastes CPU)

```nginx
# nginx example: compress text responses, skip image tiles
gzip on;
gzip_types application/json application/xml text/xml application/vnd.mapbox-vector-tile;
gzip_min_length 256;

# Brotli (better compression ratio than gzip)
brotli on;
brotli_types application/json application/xml text/xml;
```

### Load Balancing

| Strategy              | Best For                             |
|-----------------------|--------------------------------------|
| Round-robin           | Stateless tile servers, simple setup |
| Consistent hashing    | Cache affinity (same tile -> same server) |
| Least connections     | Uneven tile render times             |
| Geographic routing    | Multi-region deployments             |

Consistent hashing on the tile key (`{z}/{x}/{y}`) ensures the same tile always routes to the same backend, maximizing local cache hit rates. When a server is added or removed, only a fraction of keys are redistributed.

## GeoServer-Specific Tuning

### JVM Settings

```bash
# Production JVM flags for GeoServer
JAVA_OPTS="\
  -server \
  -Xms2g -Xmx2g \
  -XX:+UseG1GC \
  -XX:+UseStringDeduplication \
  -XX:SoftRefLRUPolicyMSPerMB=36000 \
  -Dsun.java2d.renderer=org.marlin.pisces.MarlinRenderingEngine \
  -Dorg.geotools.referencing.forceXY=true"
```

**Heap sizing guidelines:**
- Default JVM behavior: allocates approximately 1/4 of system memory as max heap
- Start with `-Xms128m` minimum to avoid memory allocation pauses during heavy load
- Set `-Xms` equal to `-Xmx` for stable heap management under heavy load
- Vector-only serving: 512 MB - 1 GB is typically sufficient (streaming uses minimal memory)
- Raster/coverage serving: 2-4 GB recommended; configure JAI tile cache to 75% of heap (`0.75`)
- For containers, set heap to ~75% of container memory limit

**Garbage collector selection:**
- `ParallelGC` (`-XX:+UseParallelGC`): Pauses application during GC; acceptable for light workloads
- `G1GC` (`-XX:+UseG1GC`): Default since Java 9; uses background threads for scanning; recommended for continuous heavy load. Optionally add `-XX:+UseStringDeduplication` to optimize common text strings
- `ZGC` (`-XX:+UseZGC`): Ultra-low pause times (sub-millisecond); production-ready since Java 15 (JEP 377); Java 21 added Generational ZGC (`-XX:+ZGenerational`) for improved throughput; recommended for latency-sensitive deployments with large heaps
- Only one garbage collector can be active at a time
- Enable GC logging in production for diagnostics: `-Xlog:gc*:file=gc.log:time,level,tags`

### JAI Configuration

Configure via the GeoServer web admin (Server > Global Settings > JAI Settings):

| Setting                   | Recommended Value | Notes                                        |
|---------------------------|-------------------|----------------------------------------------|
| Memory Capacity           | 0.75              | 75% of heap allocated to JAI tile cache      |
| Memory Threshold          | 0.75              | Trigger tile recycling at 75% cache capacity |
| Tile Threads              | Match CPU cores   | Parallel tile processing threads             |
| Tile Recycling            | Enabled           | Reuse tile memory instead of GC              |
| JPEG Native Acceleration  | Enabled           | Use native codec for JPEG encoding           |
| PNG Native Acceleration   | Enabled           | Use native codec for PNG encoding            |
| Mosaic Native Acceleration| Enabled           | Faster mosaic operations                     |

Install native JAI and ImageIO extensions for significant performance improvement on all raster operations (rescaling, reprojection, mosaicking).

### GeoWebCache Tuning

**BlobStore configuration:**
- File BlobStore: Default, stores tiles as files on disk (z/x/y directory structure)
- S3 BlobStore: For cloud deployments, stores tiles in S3-compatible object storage
- MBTiles BlobStore: Compact SQLite-based storage

**Key parameters:**

| Parameter        | Default | Recommended           | Purpose                            |
|------------------|---------|-----------------------|------------------------------------|
| Metatile size    | 4x4     | 4x4 (adjust per layer)| Tiles rendered per backend request  |
| Gutter           | 0       | 10-20 pixels          | Extra pixels for label overflow     |
| Disk quota       | None    | Set based on capacity | Prevents disk exhaustion            |
| Tile formats     | PNG/JPEG| Match client needs    | Output format for cached tiles      |

**Metatile thread configuration:**
After a metatile is produced, it is split into individual tiles for encoding and saving. The user-requested tile is encoded on the main request thread and returned immediately; the remaining tiles are encoded on asynchronous threads. The default thread pool size is 2x the number of CPU cores. Setting to 0 disables concurrency (all tiles encoded on the main request thread). This setting only affects user requests, not seeding operations.

**Default cached gridsets:**
- EPSG:4326 (geographic): 22 maximum zoom levels, 256x256 pixel tiles
- EPSG:900913 (spherical Mercator): 31 maximum zoom levels, 256x256 pixel tiles

### Connection Pool Tuning

For PostGIS-backed data stores:

```xml
<!-- GeoServer connection pool settings -->
<connectionParameters>
  <entry key="max connections">20</entry>
  <entry key="min connections">5</entry>
  <entry key="Connection timeout">20000</entry>
  <entry key="validate connections">true</entry>
  <entry key="Loose bbox">true</entry>
  <entry key="preparedStatements">true</entry>
</connectionParameters>
```

`Loose bbox` uses the faster `&&` operator (bounding box overlap) instead of exact geometry comparison. `preparedStatements` reuses query plans for repeated spatial queries.

### Coverage Access Settings

- **Overview policy**: QUALITY (best visual), SPEED (fastest overview selection), NEAREST (closest resolution match)
- **Input/output limits**: Restrict maximum raster dimensions to prevent memory exhaustion on large GetMap/GetCoverage requests
- **Footprint management**: Use footprint masks to avoid rendering NoData regions at edges of raster mosaics

### Concurrent Request Limits

Configure in WMS settings to prevent runaway requests:

| Parameter           | Default | Recommended | Description                                    |
|---------------------|---------|-------------|------------------------------------------------|
| Max rendering memory| 0 (off) | 16384 KB    | Maximum memory per GetMap request; 16 MB supports 2048x2048 at 4 bytes/pixel or 8x8 metatiles |
| Max rendering time  | 0 (off) | 120 seconds | Maximum processing time; limits data reading and rendering, not network transmission |
| Max rendering errors| 0 (off) | 100         | Error tolerance before aborting; 100 errors likely indicates a projection mismatch |

All limits default to 0 (disabled). In production, always set explicit limits. The memory estimate is checked before execution based on image size, pixel bit depth, and number of active FeatureTypeStyles. Each FeatureTypeStyle uses a separate memory buffer, so an SLD with two FeatureTypeStyles at 16 MB limit restricts images to approximately 1448x1448 pixels.

### Logging

- Use `PRODUCTION_LOGGING.properties` profile (minimal logging)
- Logging visibly affects performance; reduce to WARN or ERROR in production
- Enable the GeoServer monitoring extension for request-level metrics without verbose logging
- Switch to detailed logging temporarily for debugging, then revert

**Service strategy (web.xml or context parameter):**

| Strategy        | Description                                                   |
|-----------------|---------------------------------------------------------------|
| SPEED           | Serves output immediately; fastest but may omit proper OGC errors |
| BUFFER          | Buffers entire result in memory before serving; proper error reporting but higher latency and memory |
| FILE            | Buffers to file instead of memory; slower but avoids memory exhaustion |
| PARTIAL-BUFFER2 | Buffers a few KB in memory then streams; recommended balance of speed and error handling |

## Monitoring and Benchmarking

### Key Metrics

| Metric               | Target         | Why It Matters                          |
|----------------------|----------------|-----------------------------------------|
| Tile latency p50     | < 50ms         | Median user experience                  |
| Tile latency p95     | < 200ms        | Tail latency for most users             |
| Tile latency p99     | < 500ms        | Worst-case user experience              |
| Cache hit ratio      | > 90%          | Effectiveness of caching layers         |
| Tiles/second         | Varies         | Overall throughput capacity              |
| Error rate           | < 0.1%         | Service reliability                     |
| Source read time     | Monitor trend  | Data access performance                 |
| Encode time          | Monitor trend  | Image encoding bottlenecks              |
| Memory usage         | < 80% of limit | Headroom for traffic spikes             |

**Zoom level distribution:** Track which zoom levels receive the most requests. Typically zoom 10-16 dominate traffic. Use this to prioritize cache warming.

**Geographic hot spots:** Identify frequently requested bounding boxes to prioritize pre-generation and cache warming for those areas.

### Benchmarking Tools

**wrk (HTTP benchmarking):**

```bash
# Basic tile endpoint benchmark: 12 threads, 400 connections, 30 seconds
wrk -t12 -c400 -d30s http://localhost:8080/tiles/10/512/340.png

# With Lua script for random tile requests
wrk -t8 -c200 -d60s -s random_tiles.lua http://localhost:8080/tiles/
```

**vegeta (constant-rate load testing):**

```bash
# Generate tile URLs and attack at 1000 requests/second for 30 seconds
echo "GET http://localhost:8080/tiles/10/512/340.png" | \
  vegeta attack -duration=30s -rate=1000/s | \
  tee results.bin | \
  vegeta report

# Detailed latency report
vegeta report -type=text results.bin

# Generate histogram
vegeta report -type='hist[0,50ms,100ms,200ms,500ms,1s]' results.bin

# JSON output for further analysis
vegeta report -type=json results.bin > metrics.json

# Multiple endpoints from a file
vegeta attack -targets=tile_urls.txt -duration=60s -rate=500/s | vegeta report
```

**k6 (scripted load testing):**

```javascript
// tile_load_test.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '30s', target: 50 },   // Ramp up
    { duration: '2m',  target: 200 },   // Sustained load
    { duration: '30s', target: 0 },     // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<200'],    // 95% under 200ms
    errors: ['rate<0.01'],               // Error rate under 1%
  },
};

export default function () {
  const z = Math.floor(Math.random() * 5) + 10;  // Zoom 10-14
  const x = Math.floor(Math.random() * Math.pow(2, z));
  const y = Math.floor(Math.random() * Math.pow(2, z));

  const res = http.get(`http://localhost:8080/tiles/${z}/${x}/${y}.png`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  errorRate.add(res.status !== 200);
  sleep(0.1);
}
```

```bash
# Run the k6 test
k6 run tile_load_test.js

# Run with custom VUs and duration
k6 run --vus 100 --duration 60s tile_load_test.js
```

**Tile-specific benchmarking tools:**
- [TileSiege](https://github.com/bdon/TileSiege): Realistic load testing that simulates map browsing patterns (zoom, pan)
- Generate realistic tile request patterns: random region selection, progressive zoom-in, surrounding tile fetches

### Profiling

**CPU profiling:** Identify render bottlenecks (reprojection, compression, label placement)

```bash
# Go pprof for Go-based tile servers
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# Java Flight Recorder for GeoServer
-XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints
-XX:StartFlightRecording=duration=60s,filename=geoserver.jfr
```

**Memory profiling:** Detect leaks from unclosed GDAL handles, growing tile caches, or buffer accumulation.

**Breakdown timing:** Instrument the tile render pipeline to measure time spent in each phase:
1. Request parsing and validation
2. Source data read (file I/O, database query)
3. Reprojection / resampling
4. Styling / symbolization
5. Image encoding (PNG/JPEG/WebP)
6. Response transmission

## Scaling Patterns

### Horizontal Scaling

Stateless tile servers behind a load balancer with shared cache:

```
                    ┌─────────────┐
                    │  Load       │
         ┌────────>│  Balancer   │<────────┐
         │         └──────┬──────┘         │
         │                │                │
    ┌────┴────┐    ┌──────┴──────┐    ┌────┴────┐
    │ Tile    │    │ Tile        │    │ Tile    │
    │ Server 1│    │ Server 2    │    │ Server N│
    └────┬────┘    └──────┬──────┘    └────┬────┘
         │                │                │
         └────────┬───────┴────────┬───────┘
                  │                │
           ┌──────┴──────┐  ┌─────┴──────┐
           │ Redis       │  │ S3 / Shared│
           │ (L2 cache)  │  │ Storage    │
           └─────────────┘  └────────────┘
```

**Requirements for horizontal scaling:**
- Tile servers must be stateless (no local-only cache dependencies)
- Shared cache layer (Redis, Memcached, or S3) for cross-instance consistency
- Consistent hashing in the load balancer for cache affinity (optional but improves hit rates)

### Vertical Scaling

| Resource | Impact                                           |
|----------|--------------------------------------------------|
| CPU      | More concurrent renders, faster encoding          |
| RAM      | Larger in-memory tile cache, more GDAL handles    |
| SSD      | Faster disk-based cache reads/writes              |
| Network  | Higher throughput for serving cached tiles         |

### Serverless Tile Rendering

AWS Lambda (or equivalent) for on-demand tile rendering directly from COGs stored in S3:

**Architecture:**
```
Client -> CloudFront -> API Gateway -> Lambda -> S3 (COGs)
                ↓
          Edge Cache (CDN)
```

**Benefits:**
- Zero cost when idle; scales automatically to thousands of concurrent requests
- Pay-per-request pricing ideal for bursty or low-traffic workloads
- No server management or capacity planning

**Considerations:**
- Cold start latency (1-3 seconds for first invocation)
- Memory/CPU constraints per function invocation
- GDAL library and dependencies must be packaged in the Lambda runtime
- Best combined with aggressive CDN caching to minimize Lambda invocations

**Reference implementations:**
- [Tilegarden](https://github.com/azavea/tilegarden): Serverless Mapnik rendering on AWS Lambda
- [landsat-tiler](https://github.com/mapbox/landsat-tiler): Serverless Landsat tile server using Lambda + COGs

### Container Orchestration

**Kubernetes deployment considerations:**

```yaml
# HPA based on request latency or CPU
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: tile-server-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: tile-server
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**Pod affinity for cache locality:** Schedule pods on the same nodes to share local disk caches. Use pod anti-affinity to spread across availability zones for resilience.

**Resource limits:** Set CPU and memory limits based on profiling. Tile rendering is CPU-intensive; allocate at least 1 CPU core per pod for acceptable latency.

### Read Replicas

For database-backed stores (PostGIS):
- Multiple read-only replicas behind a read-only connection pool
- Primary handles writes (data ingestion, updates)
- Replicas serve tile rendering queries
- Use streaming replication for near-real-time consistency
- Route tile rendering to replicas; route administrative operations to primary
